"""CocoTB testbench for uart.sv — PL011-compatible UART peripheral."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer

# Register offsets (byte addresses)
UARTDR    = 0x000
UARTFR    = 0x018
UARTIBRD  = 0x024
UARTFBRD  = 0x028
UARTLCR_H = 0x02C
UARTCR    = 0x030

# UARTFR bits
TXFE = 1 << 7  # TX FIFO empty
RXFF = 1 << 6  # RX FIFO full
TXFF = 1 << 5  # TX FIFO full
RXFE = 1 << 4  # RX FIFO empty
BUSY = 1 << 3  # transmitter active

# UARTCR bits
UARTEN = 1 << 0
TXE    = 1 << 8
RXE    = 1 << 9

# AHB baud divisor for tests (small = fast simulation)
TEST_IBRD = 4


# ---------------------------------------------------------------------------
# AHB-Lite helpers
# ---------------------------------------------------------------------------

async def ahb_write(dut, addr, data):
    """AHB write: address phase then data phase."""
    dut.htrans.value = 0b10  # NONSEQ
    dut.hwrite.value = 1
    dut.haddr.value = addr
    await RisingEdge(dut.clk)
    dut.htrans.value = 0b00  # IDLE
    dut.hwdata.value = data
    await RisingEdge(dut.clk)


async def ahb_read(dut, addr):
    """AHB read: address phase then data phase, returns hrdata."""
    dut.htrans.value = 0b10  # NONSEQ
    dut.hwrite.value = 0
    dut.haddr.value = addr
    await RisingEdge(dut.clk)
    dut.htrans.value = 0b00  # IDLE
    await RisingEdge(dut.clk)
    return int(dut.hrdata.value)


# ---------------------------------------------------------------------------
# UART bit-bang helpers
# ---------------------------------------------------------------------------

async def tx_capture(dut, ibrd):
    """Monitor uart_tx and decode one 8N1 frame. Returns the byte."""
    # Wait for start bit (falling edge)
    await FallingEdge(dut.uart_tx)
    # Advance to middle of start bit
    await ClockCycles(dut.clk, ibrd // 2)

    byte = 0
    for bit in range(8):
        await ClockCycles(dut.clk, ibrd)
        byte |= (int(dut.uart_tx.value) << bit)

    # Skip stop bit
    await ClockCycles(dut.clk, ibrd)
    return byte


async def rx_inject(dut, byte, ibrd):
    """Bit-bang one 8N1 frame onto uart_rx."""
    # Start bit
    dut.uart_rx.value = 0
    await ClockCycles(dut.clk, ibrd)

    # 8 data bits, LSB first
    for bit in range(8):
        dut.uart_rx.value = (byte >> bit) & 1
        await ClockCycles(dut.clk, ibrd)

    # Stop bit
    dut.uart_rx.value = 1
    await ClockCycles(dut.clk, ibrd)


# ---------------------------------------------------------------------------
# Shared reset + init
# ---------------------------------------------------------------------------

async def reset_and_init(dut, ibrd=TEST_IBRD):
    """Start clock, reset, configure baud rate and enable UART."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.uart_rx.value = 1
    dut.htrans.value = 0
    dut.hwrite.value = 0
    dut.haddr.value = 0
    dut.hwdata.value = 0
    dut.hsize.value = 2  # word

    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    await ahb_write(dut, UARTIBRD, ibrd)
    await ahb_write(dut, UARTCR, UARTEN | TXE | RXE)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_tx_basic(dut):
    """TX 'H' (0x48) and verify uart_tx output."""
    await reset_and_init(dut)

    await ahb_write(dut, UARTDR, 0x48)

    got = await tx_capture(dut, TEST_IBRD)
    assert got == 0x48, f"TX: expected 0x48 ('H'), got 0x{got:02x}"


@cocotb.test()
async def test_rx_basic(dut):
    """Inject 0x55 on uart_rx, read back from UARTDR."""
    await reset_and_init(dut)

    await rx_inject(dut, 0x55, TEST_IBRD)
    # Wait a few cycles for RX state machine to push into FIFO
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    got = await ahb_read(dut, UARTDR)
    got &= 0xFF
    assert got == 0x55, f"RX: expected 0x55, got 0x{got:02x}"


@cocotb.test()
async def test_rx_regression_bit0(dut):
    """Regression: old double-shift bug turned 0x01 into 0x80."""
    await reset_and_init(dut)

    await rx_inject(dut, 0x01, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    got = await ahb_read(dut, UARTDR)
    got &= 0xFF
    assert got == 0x01, f"RX regression: expected 0x01, got 0x{got:02x}"


@cocotb.test()
async def test_rx_regression_high_byte(dut):
    """Regression: old bug set bit 7 to 1. Verify 0xA5 roundtrips."""
    await reset_and_init(dut)

    await rx_inject(dut, 0xA5, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    got = await ahb_read(dut, UARTDR)
    got &= 0xFF
    assert got == 0xA5, f"RX regression: expected 0xA5, got 0x{got:02x}"


@cocotb.test()
async def test_txfe_flag(dut):
    """TXFE (bit 7 of UARTFR): 1 when empty, 0 after write, 1 after drain."""
    await reset_and_init(dut)

    # Should start empty
    fr = await ahb_read(dut, UARTFR)
    assert fr & TXFE, f"TXFE should be set on empty FIFO, got UARTFR=0x{fr:03x}"

    # Write two bytes — FSM immediately dequeues the first into its shift
    # register, so we need a second byte to keep the FIFO non-empty.
    await ahb_write(dut, UARTDR, 0x41)
    await ahb_write(dut, UARTDR, 0x42)
    fr = await ahb_read(dut, UARTFR)
    assert not (fr & TXFE), f"TXFE should be clear with byte in FIFO, got UARTFR=0x{fr:03x}"

    # Wait for both bytes to finish: 2 * (start + 8 data + stop) = 20 bit periods
    await ClockCycles(dut.clk, TEST_IBRD * 22)

    # Should be empty again
    fr = await ahb_read(dut, UARTFR)
    assert fr & TXFE, f"TXFE should be set after drain, got UARTFR=0x{fr:03x}"


@cocotb.test()
async def test_loopback(dut):
    """Wire uart_tx back to uart_rx, TX a byte, verify RX receives it."""
    await reset_and_init(dut)

    # Background task: continuously copy uart_tx to uart_rx (loopback)
    async def loopback():
        while True:
            await RisingEdge(dut.clk)
            dut.uart_rx.value = int(dut.uart_tx.value)

    cocotb.start_soon(loopback())

    # TX 0x37
    await ahb_write(dut, UARTDR, 0x37)

    # Wait for full frame: start + 8 data + stop = 10 bit periods, plus margin
    await ClockCycles(dut.clk, TEST_IBRD * 14)

    # Check RXFE — should have data
    fr = await ahb_read(dut, UARTFR)
    assert not (fr & RXFE), f"RX FIFO should have data after loopback, UARTFR=0x{fr:03x}"

    got = await ahb_read(dut, UARTDR)
    got &= 0xFF
    assert got == 0x37, f"Loopback: expected 0x37, got 0x{got:02x}"


# ---------------------------------------------------------------------------
# Standalone runner (avoids cocotb Makefile system)
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import os, pathlib
    from cocotb_tools.runner import get_runner

    repo = pathlib.Path(__file__).resolve().parents[2]
    runner = get_runner("verilator")
    runner.build(
        verilog_sources=[str(repo / "rtl/soc/peripheral/uart.sv")],
        hdl_toplevel="uart",
        build_args=["--trace", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="uart", test_module="test_uart")
