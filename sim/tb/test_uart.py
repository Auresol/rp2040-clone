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
UARTIFLS  = 0x034
UARTIMSC  = 0x038
UARTRIS   = 0x03C
UARTMIS   = 0x040
UARTICR   = 0x044
UARTDMACR = 0x048

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
RTSEn  = 1 << 11
CTSEn  = 1 << 14
LBE    = 1 << 15

# RIS / IMSC bit positions
OE_BIT = 1 << 10
RT_BIT = 1 << 6
TX_BIT = 1 << 5
RX_BIT = 1 << 4

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


async def measure_bit_durations(dut):
    """Measure clock cycles between edges on uart_tx for an alternating-bit byte.
    Returns a list of durations (one per edge-to-edge interval)."""
    durations = []
    # Wait for start bit (falling edge)
    await FallingEdge(dut.uart_tx)
    count = 0
    prev_val = 0
    # Measure through 8 data bits + stop (expect edges every bit for 0x55)
    for _ in range(10000):
        await RisingEdge(dut.clk)
        count += 1
        cur = int(dut.uart_tx.value)
        if cur != prev_val:
            durations.append(count)
            count = 0
            prev_val = cur
        # After stop bit (high), we expect no more edges — break after enough
        if len(durations) >= 9:
            break
    return durations


async def rx_drain_loop(dut, expected_count):
    """Concurrent coroutine: drain RX FIFO as bytes arrive.
    Returns list of received bytes once expected_count reached."""
    received = []
    while len(received) < expected_count:
        fr = await ahb_read(dut, UARTFR)
        if not (fr & RXFE):
            val = await ahb_read(dut, UARTDR)
            received.append(val & 0xFF)
        else:
            await ClockCycles(dut.clk, 4)
    return received


# ---------------------------------------------------------------------------
# Shared reset + init
# ---------------------------------------------------------------------------

async def reset_and_init(dut, ibrd=TEST_IBRD):
    """Start clock, reset, configure baud rate and enable UART."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.uart_rx.value = 1
    dut.uart_cts_n.value = 0  # CTS asserted (clear to send)
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


# ===========================================================================
# Tests — basic TX/RX (existing)
# ===========================================================================

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


# ===========================================================================
# Group 1 — FIFO depth & flags
# ===========================================================================

@cocotb.test()
async def test_tx_fifo_full_flag(dut):
    """Fill TX FIFO to capacity, verify TXFF flag, then drain and verify TXFE."""
    await reset_and_init(dut)

    # Write 9 bytes rapidly. FSM dequeues 1st into shift reg, leaving 8 in FIFO.
    for i in range(9):
        await ahb_write(dut, UARTDR, 0x40 + i)

    fr = await ahb_read(dut, UARTFR)
    assert fr & TXFF, f"TXFF should be set after 9 writes, got UARTFR=0x{fr:03x}"

    # Wait for all to drain: 9 frames * 10 bits = 90 bit periods
    await ClockCycles(dut.clk, TEST_IBRD * 95)

    fr = await ahb_read(dut, UARTFR)
    assert fr & TXFE, f"TXFE should be set after full drain, got UARTFR=0x{fr:03x}"
    assert not (fr & TXFF), f"TXFF should be clear after drain, got UARTFR=0x{fr:03x}"


@cocotb.test()
async def test_rx_fifo_full_flag(dut):
    """Fill RX FIFO to 8 entries, verify RXFF, drain and verify RXFE."""
    await reset_and_init(dut)

    for i in range(8):
        await rx_inject(dut, 0x10 + i, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    fr = await ahb_read(dut, UARTFR)
    assert fr & RXFF, f"RXFF should be set with 8 bytes, got UARTFR=0x{fr:03x}"
    assert not (fr & RXFE), f"RXFE should be clear with 8 bytes, got UARTFR=0x{fr:03x}"

    # Drain all 8
    for i in range(8):
        val = await ahb_read(dut, UARTDR)
        assert (val & 0xFF) == 0x10 + i, f"RX byte {i}: expected 0x{0x10+i:02x}, got 0x{val & 0xFF:02x}"

    fr = await ahb_read(dut, UARTFR)
    assert fr & RXFE, f"RXFE should be set after drain, got UARTFR=0x{fr:03x}"
    assert not (fr & RXFF), f"RXFF should be clear after drain, got UARTFR=0x{fr:03x}"


# ===========================================================================
# Group 2 — Multi-byte ordering
# ===========================================================================

@cocotb.test()
async def test_tx_multi_byte_order(dut):
    """TX 4 bytes, capture all, verify they arrive in order."""
    await reset_and_init(dut)

    send = [0x10, 0x20, 0x30, 0x40]
    for b in send:
        await ahb_write(dut, UARTDR, b)

    for i, expected in enumerate(send):
        got = await tx_capture(dut, TEST_IBRD)
        assert got == expected, f"TX byte {i}: expected 0x{expected:02x}, got 0x{got:02x}"


@cocotb.test()
async def test_rx_multi_byte_order(dut):
    """Inject 4 bytes, read all, verify they arrive in order."""
    await reset_and_init(dut)

    send = [0xAA, 0xBB, 0xCC, 0xDD]
    for b in send:
        await rx_inject(dut, b, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    for i, expected in enumerate(send):
        got = await ahb_read(dut, UARTDR)
        assert (got & 0xFF) == expected, f"RX byte {i}: expected 0x{expected:02x}, got 0x{got & 0xFF:02x}"


# ===========================================================================
# Group 3 — IFLS thresholds
# ===========================================================================

@cocotb.test()
async def test_tx_irq_threshold_quarter(dut):
    """TXIFLSEL=1/4 (threshold=2): RIS[5] fires when tx_level <= 2."""
    await reset_and_init(dut)
    await ahb_write(dut, UARTIFLS, 0b000_001)  # RX=default(1/8), TX=1/4

    # Empty FIFO: level=0 <= 2, so RIS[5] should be set
    ris = await ahb_read(dut, UARTRIS)
    assert ris & TX_BIT, f"RIS TX should be set when empty (level 0 <= 2), got RIS=0x{ris:03x}"

    # Fill above threshold: write 4 bytes. FSM dequeues 1, level=3 > 2.
    for i in range(4):
        await ahb_write(dut, UARTDR, 0x60 + i)

    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & TX_BIT), f"RIS TX should be clear when level > 2, got RIS=0x{ris:03x}"

    # Wait for FSM to drain enough (1 frame = 40 clocks, need level to drop to 2)
    await ClockCycles(dut.clk, TEST_IBRD * 12)

    ris = await ahb_read(dut, UARTRIS)
    assert ris & TX_BIT, f"RIS TX should be set after drain to <= 2, got RIS=0x{ris:03x}"


@cocotb.test()
async def test_tx_irq_threshold_three_quarter(dut):
    """TXIFLSEL=3/4 (threshold=6): RIS[5] fires when tx_level <= 6."""
    await reset_and_init(dut)
    await ahb_write(dut, UARTIFLS, 0b000_011)  # TX=3/4

    # Empty: level=0 <= 6, RIS[5] should be set
    ris = await ahb_read(dut, UARTRIS)
    assert ris & TX_BIT, f"RIS TX should be set when empty, got RIS=0x{ris:03x}"

    # Fill to 8: write 9 bytes (FSM dequeues 1, level=8 > 6). But actually
    # with 9 writes, the FIFO is full (8 entries). Wait: tx_full blocks the
    # 9th write from tx_wptr advancing... no, 9 writes: 1st dequeued by FSM
    # so 8 land in FIFO. 8 > 6, so RIS[5] = 0.
    for i in range(9):
        await ahb_write(dut, UARTDR, 0x50 + i)

    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & TX_BIT), f"RIS TX should be clear when level=8 > 6, got RIS=0x{ris:03x}"

    # Wait for 2 frames to drain (level drops to 6), RIS[5] should set
    await ClockCycles(dut.clk, TEST_IBRD * 22)

    ris = await ahb_read(dut, UARTRIS)
    assert ris & TX_BIT, f"RIS TX should be set after drain to <= 6, got RIS=0x{ris:03x}"


@cocotb.test()
async def test_rx_irq_threshold_quarter(dut):
    """RXIFLSEL=1/4 (threshold=2): RIS[4] fires when rx_level >= 2."""
    await reset_and_init(dut)
    await ahb_write(dut, UARTIFLS, 0b001_000)  # RX=1/4, TX=default(1/8)

    # Inject 1 byte — level=1 < 2
    await rx_inject(dut, 0x11, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & RX_BIT), f"RIS RX should be clear at level 1 < 2, got RIS=0x{ris:03x}"

    # Inject 2nd — level=2 >= 2
    await rx_inject(dut, 0x22, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    ris = await ahb_read(dut, UARTRIS)
    assert ris & RX_BIT, f"RIS RX should be set at level 2 >= 2, got RIS=0x{ris:03x}"


@cocotb.test()
async def test_rx_irq_threshold_three_quarter(dut):
    """RXIFLSEL=3/4 (threshold=6): RIS[4] fires when rx_level >= 6."""
    await reset_and_init(dut)
    await ahb_write(dut, UARTIFLS, 0b011_000)  # RX=3/4

    # Inject 5 bytes — level=5 < 6
    for i in range(5):
        await rx_inject(dut, 0x30 + i, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & RX_BIT), f"RIS RX should be clear at level 5 < 6, got RIS=0x{ris:03x}"

    # Inject 6th — level=6 >= 6
    await rx_inject(dut, 0x35, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    ris = await ahb_read(dut, UARTRIS)
    assert ris & RX_BIT, f"RIS RX should be set at level 6 >= 6, got RIS=0x{ris:03x}"


# ===========================================================================
# Group 4 — Interrupt masking
# ===========================================================================

@cocotb.test()
async def test_interrupt_masking(dut):
    """Verify MIS = RIS & IMSC: masking gates interrupt status."""
    await reset_and_init(dut)

    # TX FIFO is empty at default IFLS (1/2), so RIS[5] (TXRIS) should be set
    ris = await ahb_read(dut, UARTRIS)
    assert ris & TX_BIT, f"RIS TX should be set when empty, got RIS=0x{ris:03x}"

    # IMSC = 0 (all masked) → MIS should be 0
    await ahb_write(dut, UARTIMSC, 0)
    mis = await ahb_read(dut, UARTMIS)
    assert mis == 0, f"MIS should be 0 with IMSC=0, got MIS=0x{mis:03x}"

    # Enable TX interrupt mask
    await ahb_write(dut, UARTIMSC, TX_BIT)
    mis = await ahb_read(dut, UARTMIS)
    assert mis & TX_BIT, f"MIS TX should be set with IMSC TX enabled, got MIS=0x{mis:03x}"

    # Mask it again
    await ahb_write(dut, UARTIMSC, 0)
    mis = await ahb_read(dut, UARTMIS)
    assert mis == 0, f"MIS should be 0 after re-masking, got MIS=0x{mis:03x}"


@cocotb.test()
async def test_uart_irq_signal(dut):
    """Verify uart_irq output tracks |MIS."""
    await reset_and_init(dut)

    # IMSC = 0 → irq should be 0
    await ahb_write(dut, UARTIMSC, 0)
    await RisingEdge(dut.clk)
    assert int(dut.uart_irq.value) == 0, "uart_irq should be 0 with all masked"

    # Enable TX interrupt (TX FIFO empty → RIS[5]=1)
    await ahb_write(dut, UARTIMSC, TX_BIT)
    await RisingEdge(dut.clk)
    assert int(dut.uart_irq.value) == 1, "uart_irq should be 1 with TX unmasked and FIFO empty"

    # Mask again
    await ahb_write(dut, UARTIMSC, 0)
    await RisingEdge(dut.clk)
    assert int(dut.uart_irq.value) == 0, "uart_irq should be 0 after re-masking"


# ===========================================================================
# Group 5 — Overrun error
# ===========================================================================

@cocotb.test()
async def test_rx_overrun(dut):
    """Fill RX FIFO (8), inject 9th byte, verify OE in RIS, clear via ICR."""
    await reset_and_init(dut)

    # Fill FIFO
    for i in range(8):
        await rx_inject(dut, 0x70 + i, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    # Verify full
    fr = await ahb_read(dut, UARTFR)
    assert fr & RXFF, f"RXFF should be set after 8 injects, got UARTFR=0x{fr:03x}"

    # No overrun yet
    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & OE_BIT), f"OE should be clear before overflow, got RIS=0x{ris:03x}"

    # Inject 9th byte — overrun
    await rx_inject(dut, 0xFF, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    ris = await ahb_read(dut, UARTRIS)
    assert ris & OE_BIT, f"OE should be set after 9th inject, got RIS=0x{ris:03x}"

    # Clear via ICR
    await ahb_write(dut, UARTICR, OE_BIT)
    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & OE_BIT), f"OE should be clear after ICR, got RIS=0x{ris:03x}"


@cocotb.test()
async def test_overrun_dr_bit(dut):
    """Verify DR[11] (OE) reflects overrun latch, and clears via ICR."""
    await reset_and_init(dut)

    # Fill and overflow
    for i in range(9):
        await rx_inject(dut, 0x80 + i, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    # Read DR — OE bit should be set
    dr = await ahb_read(dut, UARTDR)
    assert dr & (1 << 11), f"DR[11] (OE) should be set, got DR=0x{dr:03x}"

    # Clear OE
    await ahb_write(dut, UARTICR, OE_BIT)

    # Read DR again — OE bit should be clear
    dr = await ahb_read(dut, UARTDR)
    assert not (dr & (1 << 11)), f"DR[11] should be clear after ICR, got DR=0x{dr:03x}"


# ===========================================================================
# Group 6 — Receive timeout
# ===========================================================================

@cocotb.test()
async def test_receive_timeout(dut):
    """Inject 1 byte, don't read it, wait 32 bit periods → RT fires."""
    await reset_and_init(dut)

    await rx_inject(dut, 0xAA, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    # Should not be timed out yet
    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & RT_BIT), f"RT should be clear immediately after inject, got RIS=0x{ris:03x}"

    # Wait 32 bit periods + margin
    await ClockCycles(dut.clk, TEST_IBRD * 35)

    ris = await ahb_read(dut, UARTRIS)
    assert ris & RT_BIT, f"RT should be set after 32 bit-period timeout, got RIS=0x{ris:03x}"

    # Clear via ICR
    await ahb_write(dut, UARTICR, RT_BIT)
    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & RT_BIT), f"RT should be clear after ICR, got RIS=0x{ris:03x}"


@cocotb.test()
async def test_timeout_reset_on_dr_read(dut):
    """Reading DR resets the timeout counter."""
    await reset_and_init(dut)

    await rx_inject(dut, 0xBB, TEST_IBRD)
    await rx_inject(dut, 0xCC, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    # Partial wait (not enough for timeout)
    await ClockCycles(dut.clk, TEST_IBRD * 15)

    # Read DR — resets timeout counter. 1 byte still in FIFO.
    await ahb_read(dut, UARTDR)

    # Wait another partial period — should not timeout yet
    await ClockCycles(dut.clk, TEST_IBRD * 15)
    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & RT_BIT), f"RT should be clear: counter was reset by DR read, got RIS=0x{ris:03x}"

    # Now wait full timeout
    await ClockCycles(dut.clk, TEST_IBRD * 35)
    ris = await ahb_read(dut, UARTRIS)
    assert ris & RT_BIT, f"RT should fire after full timeout from last reset, got RIS=0x{ris:03x}"


@cocotb.test()
async def test_timeout_reset_on_new_byte(dut):
    """New RX byte arriving resets the timeout counter."""
    await reset_and_init(dut)

    await rx_inject(dut, 0xDD, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    # Partial wait
    await ClockCycles(dut.clk, TEST_IBRD * 15)

    # Inject 2nd byte — resets counter
    await rx_inject(dut, 0xEE, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    # Wait partial — should not timeout
    await ClockCycles(dut.clk, TEST_IBRD * 15)
    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & RT_BIT), f"RT should be clear: counter reset by new byte, got RIS=0x{ris:03x}"

    # Full timeout from last byte
    await ClockCycles(dut.clk, TEST_IBRD * 35)
    ris = await ahb_read(dut, UARTRIS)
    assert ris & RT_BIT, f"RT should fire after full timeout, got RIS=0x{ris:03x}"


# ===========================================================================
# Group 7 — ICR independent clear
# ===========================================================================

@cocotb.test()
async def test_icr_independent_clear(dut):
    """Trigger both OE and RT, clear them independently via ICR."""
    await reset_and_init(dut)

    # Trigger OE: fill 8 + inject 9th
    for i in range(9):
        await rx_inject(dut, 0x90 + (i & 7), TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    # Drain FIFO so it's not full, but OE latch stays set
    for _ in range(8):
        await ahb_read(dut, UARTDR)

    # Re-inject 1 byte so FIFO is non-empty (needed for RT to fire)
    await rx_inject(dut, 0xAA, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    # Wait for receive timeout
    await ClockCycles(dut.clk, TEST_IBRD * 35)

    ris = await ahb_read(dut, UARTRIS)
    assert ris & OE_BIT, f"OE should be set, got RIS=0x{ris:03x}"
    assert ris & RT_BIT, f"RT should be set, got RIS=0x{ris:03x}"

    # Clear only RT
    await ahb_write(dut, UARTICR, RT_BIT)
    ris = await ahb_read(dut, UARTRIS)
    assert ris & OE_BIT, f"OE should still be set after clearing RT, got RIS=0x{ris:03x}"
    assert not (ris & RT_BIT), f"RT should be clear after ICR, got RIS=0x{ris:03x}"

    # Clear OE
    await ahb_write(dut, UARTICR, OE_BIT)
    ris = await ahb_read(dut, UARTRIS)
    assert not (ris & OE_BIT), f"OE should be clear after ICR, got RIS=0x{ris:03x}"


# ===========================================================================
# Group 8 — CTS flow control
# ===========================================================================

@cocotb.test()
async def test_cts_flow_control(dut):
    """CTSEn blocks TX when uart_cts_n is deasserted (high)."""
    await reset_and_init(dut)

    # Enable CTS flow control
    await ahb_write(dut, UARTCR, UARTEN | TXE | RXE | CTSEn)

    # Deassert CTS (high = "don't send")
    dut.uart_cts_n.value = 1
    await RisingEdge(dut.clk)

    # Write a byte
    await ahb_write(dut, UARTDR, 0x42)

    # Wait — TX should NOT start
    await ClockCycles(dut.clk, TEST_IBRD * 12)
    fr = await ahb_read(dut, UARTFR)
    assert not (fr & BUSY), f"TX should not start with CTS deasserted, got UARTFR=0x{fr:03x}"
    assert int(dut.uart_tx.value) == 1, "uart_tx should stay high (idle) with CTS deasserted"

    # Assert CTS (low = "clear to send")
    dut.uart_cts_n.value = 0
    await ClockCycles(dut.clk, 2)

    # TX should start now
    got = await tx_capture(dut, TEST_IBRD)
    assert got == 0x42, f"TX byte after CTS release: expected 0x42, got 0x{got:02x}"


# ===========================================================================
# Group 9 — RTS flow control
# ===========================================================================

@cocotb.test()
async def test_rts_flow_control(dut):
    """RTSEn deasserts uart_rts_n when RX FIFO is full."""
    await reset_and_init(dut)

    # Enable RTS flow control
    await ahb_write(dut, UARTCR, UARTEN | TXE | RXE | RTSEn)
    await RisingEdge(dut.clk)

    # RX FIFO empty → RTS asserted (low)
    assert int(dut.uart_rts_n.value) == 0, "RTS should be asserted (low) with empty FIFO"

    # Fill RX FIFO to 8
    for i in range(8):
        await rx_inject(dut, 0xC0 + i, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    # RX full → RTS deasserted (high)
    assert int(dut.uart_rts_n.value) == 1, "RTS should be deasserted (high) with full FIFO"

    # Read one byte — FIFO no longer full → RTS re-asserted
    await ahb_read(dut, UARTDR)
    await RisingEdge(dut.clk)
    assert int(dut.uart_rts_n.value) == 0, "RTS should be re-asserted (low) after reading 1 byte"


# ===========================================================================
# Group 10 — Hardware loopback (LBE)
# ===========================================================================

@cocotb.test()
async def test_hardware_loopback_lbe(dut):
    """CR[15] LBE routes tx_pin → RX path internally. Use ibrd=8 for margin."""
    ibrd = 8
    await reset_and_init(dut, ibrd=ibrd)

    # Enable loopback via CR
    await ahb_write(dut, UARTCR, UARTEN | TXE | RXE | LBE)

    # TX a byte — should loop back to RX internally
    await ahb_write(dut, UARTDR, 0x5A)

    # Wait for full frame + margin
    await ClockCycles(dut.clk, ibrd * 14)

    # Check RX has data
    fr = await ahb_read(dut, UARTFR)
    assert not (fr & RXFE), f"RX FIFO should have data after LBE loopback, got UARTFR=0x{fr:03x}"

    got = await ahb_read(dut, UARTDR)
    assert (got & 0xFF) == 0x5A, f"LBE loopback: expected 0x5A, got 0x{got & 0xFF:02x}"


# ===========================================================================
# Group 11 — DMA control
# ===========================================================================

@cocotb.test()
async def test_dma_tx_dreq(dut):
    """TXDMAE: uart_tx_dreq asserted when TX FIFO has room, deasserted when full."""
    await reset_and_init(dut)

    # Enable TX DMA
    await ahb_write(dut, UARTDMACR, 0x02)  # TXDMAE=1
    await RisingEdge(dut.clk)

    # TX FIFO empty → dreq should be 1 (has room)
    assert int(dut.uart_tx_dreq.value) == 1, "tx_dreq should be 1 with empty FIFO"

    # Fill FIFO: write 9 bytes (FSM dequeues 1, 8 in FIFO = full)
    for i in range(9):
        await ahb_write(dut, UARTDR, 0xD0 + i)

    await RisingEdge(dut.clk)
    assert int(dut.uart_tx_dreq.value) == 0, "tx_dreq should be 0 with full FIFO"

    # Wait for some to drain
    await ClockCycles(dut.clk, TEST_IBRD * 12)
    assert int(dut.uart_tx_dreq.value) == 1, "tx_dreq should be 1 after drain"


@cocotb.test()
async def test_dma_rx_dreq(dut):
    """RXDMAE: uart_rx_dreq asserted when RX FIFO has data."""
    await reset_and_init(dut)

    # Enable RX DMA
    await ahb_write(dut, UARTDMACR, 0x01)  # RXDMAE=1
    await RisingEdge(dut.clk)

    # Empty → dreq = 0
    assert int(dut.uart_rx_dreq.value) == 0, "rx_dreq should be 0 with empty FIFO"

    # Inject 1 byte
    await rx_inject(dut, 0xE0, TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    assert int(dut.uart_rx_dreq.value) == 1, "rx_dreq should be 1 with data in FIFO"

    # Read it out
    await ahb_read(dut, UARTDR)
    await RisingEdge(dut.clk)
    assert int(dut.uart_rx_dreq.value) == 0, "rx_dreq should be 0 after drain"


@cocotb.test()
async def test_dma_onerr_blocks_dreq(dut):
    """DMAONERR blocks both DMA channels when OE is set."""
    await reset_and_init(dut)

    # Enable all DMA features
    await ahb_write(dut, UARTDMACR, 0x07)  # DMAONERR=1, TXDMAE=1, RXDMAE=1
    await RisingEdge(dut.clk)

    # tx_dreq should be 1 initially (FIFO not full, no error)
    assert int(dut.uart_tx_dreq.value) == 1, "tx_dreq should be 1 before error"

    # Trigger overrun: fill 8 + inject 9th
    for i in range(9):
        await rx_inject(dut, 0xF0 + (i & 7), TEST_IBRD)
    await ClockCycles(dut.clk, TEST_IBRD * 2)

    # OE is set → both dreqs should be blocked
    assert int(dut.uart_tx_dreq.value) == 0, "tx_dreq should be 0 with DMAONERR and OE set"
    assert int(dut.uart_rx_dreq.value) == 0, "rx_dreq should be 0 with DMAONERR and OE set"

    # Clear OE via ICR
    await ahb_write(dut, UARTICR, OE_BIT)
    await RisingEdge(dut.clk)

    # tx_dreq should resume (TX FIFO not full)
    assert int(dut.uart_tx_dreq.value) == 1, "tx_dreq should resume after OE cleared"


# ===========================================================================
# Group 12 — Fractional baud rate
# ===========================================================================

@cocotb.test()
async def test_fractional_baud(dut):
    """FBRD=32 with IBRD=4: every other bit period gets +1 cycle (4 or 5)."""
    await reset_and_init(dut)
    await ahb_write(dut, UARTFBRD, 32)

    # TX 0x55 (alternating bits → edge every bit period)
    await ahb_write(dut, UARTDR, 0x55)

    durations = await measure_bit_durations(dut)

    # We should see a mix of 4-cycle and 5-cycle intervals
    has_4 = any(d == 4 for d in durations)
    has_5 = any(d == 5 for d in durations)
    assert has_4, f"Expected some 4-cycle bit periods, got durations: {durations}"
    assert has_5, f"Expected some 5-cycle bit periods, got durations: {durations}"

    # Verify no unexpected durations
    for d in durations:
        assert d in (4, 5), f"Unexpected bit duration {d}, expected 4 or 5. All: {durations}"


# ===========================================================================
# Group 13 — Register readback
# ===========================================================================

@cocotb.test()
async def test_register_readback(dut):
    """Write/read all RW registers, verify round-trip values."""
    await reset_and_init(dut)

    tests = [
        (UARTIBRD,  0xBEEF, 0xFFFF,  "IBRD"),
        (UARTFBRD,  0x3F,   0x3F,    "FBRD"),
        (UARTLCR_H, 0xAB,   0xFF,    "LCR_H"),
        (UARTCR,    0xC301, 0xFFFF,  "CR"),
        (UARTIFLS,  0x1B,   0x3F,    "IFLS"),
        (UARTIMSC,  0x7FF,  0x7FF,   "IMSC"),
        (UARTDMACR, 0x07,   0x07,    "DMACR"),
    ]

    for addr, val, mask, name in tests:
        await ahb_write(dut, addr, val)
        got = await ahb_read(dut, addr)
        expected = val & mask
        assert got == expected, f"{name}: wrote 0x{val:04x}, expected 0x{expected:04x}, got 0x{got:04x}"


# ===========================================================================
# Group 14 — Long stream / clock drift
# ===========================================================================

@cocotb.test()
async def test_long_stream_loopback(dut):
    """TX 64 bytes via LBE loopback with fractional baud. Tests clock drift,
    FIFO wrap-around, and sustained throughput."""
    ibrd = 8
    await reset_and_init(dut, ibrd=ibrd)
    await ahb_write(dut, UARTFBRD, 10)
    await ahb_write(dut, UARTCR, UARTEN | TXE | RXE | LBE)

    num_bytes = 64

    # Start a concurrent RX drain coroutine
    rx_task = cocotb.start_soon(rx_drain_loop(dut, num_bytes))

    # Feed TX: write bytes as space opens in the TX FIFO (8 deep)
    for i in range(num_bytes):
        # Wait until TX FIFO has room
        for _ in range(50000):
            fr = await ahb_read(dut, UARTFR)
            if not (fr & TXFF):
                break
            await ClockCycles(dut.clk, 2)
        else:
            assert False, f"TX FIFO stuck full at byte {i}"

        await ahb_write(dut, UARTDR, i & 0xFF)

    # Wait for RX drain to complete
    received = await rx_task

    assert len(received) == num_bytes, f"Expected {num_bytes} bytes, got {len(received)}"
    for i, b in enumerate(received):
        assert b == (i & 0xFF), f"Byte {i}: expected 0x{i & 0xFF:02x}, got 0x{b:02x}"


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
