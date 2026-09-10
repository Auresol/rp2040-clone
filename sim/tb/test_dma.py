"""CocoTB testbench for dma.sv — 4-channel DMA controller."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Channel register offsets (byte addresses, channel stride = 0x10)
def CH_READ_ADDR(n):  return n * 0x10 + 0x00
def CH_WRITE_ADDR(n): return n * 0x10 + 0x04
def CH_TRANS_COUNT(n): return n * 0x10 + 0x08
def CH_CTRL(n):       return n * 0x10 + 0x0C

IRQ_STATUS = 0x40

# CTRL field helpers
CTRL_EN       = 1 << 0
CTRL_INCR_RD  = 1 << 1
CTRL_INCR_WR  = 1 << 2
CTRL_SIZE_BYTE = 0 << 3
CTRL_SIZE_HALF = 1 << 3
CTRL_SIZE_WORD = 2 << 3
CTRL_DREQ_NONE = 0 << 5
CTRL_DREQ_0    = 1 << 5
CTRL_DREQ_1    = 2 << 5
CTRL_IRQ_EN    = 1 << 8


# ---------------------------------------------------------------------------
# AHB-Lite helpers (slave port — configure DMA)
# ---------------------------------------------------------------------------

async def ahb_write(dut, addr, data):
    dut.s_htrans.value = 0b10
    dut.s_hwrite.value = 1
    dut.s_haddr.value = addr
    await RisingEdge(dut.clk)
    dut.s_htrans.value = 0b00
    dut.s_hwdata.value = data
    await RisingEdge(dut.clk)


async def ahb_read(dut, addr):
    dut.s_htrans.value = 0b10
    dut.s_hwrite.value = 0
    dut.s_haddr.value = addr
    await RisingEdge(dut.clk)
    dut.s_htrans.value = 0b00
    await RisingEdge(dut.clk)
    return int(dut.s_hrdata.value)


# ---------------------------------------------------------------------------
# Memory helpers (direct port)
# ---------------------------------------------------------------------------

async def mem_write(dut, word_addr, data):
    dut.mem_addr.value = word_addr << 2
    dut.mem_we.value = 1
    dut.mem_wdata.value = data
    await RisingEdge(dut.clk)
    dut.mem_we.value = 0


async def mem_read(dut, word_addr):
    dut.mem_we.value = 0
    dut.mem_addr.value = word_addr << 2
    await RisingEdge(dut.clk)
    return int(dut.mem_rdata.value)


# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------

async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.s_htrans.value = 0
    dut.s_hwrite.value = 0
    dut.s_haddr.value = 0
    dut.s_hwdata.value = 0
    dut.s_hsize.value = 2
    dut.dreq.value = 0
    dut.mem_addr.value = 0
    dut.mem_we.value = 0
    dut.mem_wdata.value = 0

    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_mem_to_mem_word(dut):
    """Memory-to-memory word transfer (4 words, free-running)."""
    await reset(dut)

    # Seed source memory: words at addresses 0x00..0x0C
    for i in range(4):
        await mem_write(dut, i, 0xDEAD0000 + i)

    # Configure channel 0: read from 0x00, write to 0x40, 4 words
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)  # src = word 0
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)  # dst = word 64
    await ahb_write(dut, CH_TRANS_COUNT(0), 4)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD)

    # Wait for DMA to complete (4 transfers × ~5 cycles each = ~20 cycles)
    await ClockCycles(dut.clk, 40)

    # Verify destination
    for i in range(4):
        val = await mem_read(dut, 64 + i)
        assert val == 0xDEAD0000 + i, f"word {i}: expected 0x{0xDEAD0000+i:08x}, got 0x{val:08x}"


@cocotb.test()
async def test_register_readback(dut):
    """Channel registers round-trip correctly."""
    await reset(dut)

    await ahb_write(dut, CH_READ_ADDR(1),  0x12345678)
    await ahb_write(dut, CH_WRITE_ADDR(1), 0xABCD0000)
    await ahb_write(dut, CH_TRANS_COUNT(1), 42)
    await ahb_write(dut, CH_CTRL(1), 0x0000017F)

    ra = await ahb_read(dut, CH_READ_ADDR(1))
    wa = await ahb_read(dut, CH_WRITE_ADDR(1))
    tc = await ahb_read(dut, CH_TRANS_COUNT(1))
    ct = await ahb_read(dut, CH_CTRL(1))

    assert ra == 0x12345678, f"READ_ADDR: got 0x{ra:08x}"
    assert wa == 0xABCD0000, f"WRITE_ADDR: got 0x{wa:08x}"
    assert tc == 42, f"TRANS_COUNT: got {tc}"
    assert ct == 0x0000017F, f"CTRL: got 0x{ct:08x}"


@cocotb.test()
async def test_irq_on_completion(dut):
    """IRQ fires when transfer count reaches zero."""
    await reset(dut)

    # Seed 1 word
    await mem_write(dut, 0, 0xCAFE)

    # Ch0: 1 transfer, IRQ enabled
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 1)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD | CTRL_IRQ_EN)

    # IRQ should be low now
    assert int(dut.dma_irq.value) == 0, "IRQ should be low before completion"

    await ClockCycles(dut.clk, 20)

    # IRQ should be high
    assert int(dut.dma_irq.value) == 1, "IRQ should be high after completion"

    # Read IRQ status
    status = await ahb_read(dut, IRQ_STATUS)
    assert status & 1, f"IRQ_STATUS bit 0 should be set, got 0x{status:x}"

    # Write-1-to-clear
    await ahb_write(dut, IRQ_STATUS, 1)
    await ClockCycles(dut.clk, 2)
    assert int(dut.dma_irq.value) == 0, "IRQ should clear after W1C"


@cocotb.test()
async def test_dreq_paced(dut):
    """DREQ-paced transfer: DMA waits for DREQ pulses."""
    await reset(dut)

    # Seed source
    for i in range(3):
        await mem_write(dut, i, 0xBEEF0000 + i)

    # Ch0: 3 transfers, paced by dreq[0]
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 3)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD | CTRL_DREQ_0)

    # No DREQ yet — wait and verify nothing happened
    await ClockCycles(dut.clk, 20)
    val = await mem_read(dut, 64)
    assert val != 0xBEEF0000, "DMA should not transfer without DREQ"

    # Pulse DREQ 3 times with gaps
    for pulse in range(3):
        dut.dreq.value = 1
        await ClockCycles(dut.clk, 10)  # hold DREQ for a few cycles
        dut.dreq.value = 0
        await ClockCycles(dut.clk, 10)

    # Check all 3 words arrived
    for i in range(3):
        val = await mem_read(dut, 64 + i)
        assert val == 0xBEEF0000 + i, f"word {i}: expected 0x{0xBEEF0000+i:08x}, got 0x{val:08x}"


@cocotb.test()
async def test_abort_mid_transfer(dut):
    """Disabling a channel mid-transfer stops it."""
    await reset(dut)

    # Seed 8 words
    for i in range(8):
        await mem_write(dut, i, 0xAA000000 + i)

    # Ch0: 8 transfers, free-running
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 8)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD)

    # Let a few transfers happen
    await ClockCycles(dut.clk, 15)

    # Disable
    await ahb_write(dut, CH_CTRL(0), 0)
    await ClockCycles(dut.clk, 5)

    # Read remaining count — should be > 0 (not all 8 completed)
    remaining = await ahb_read(dut, CH_TRANS_COUNT(0))
    assert remaining > 0, f"expected some transfers remaining, got {remaining}"
    assert remaining < 8, f"expected some transfers done, got {remaining}"


@cocotb.test()
async def test_no_incr_read(dut):
    """Fixed read address (peripheral-style): reads same address repeatedly."""
    await reset(dut)

    # Seed one word at address 0
    await mem_write(dut, 0, 0x42)

    # Ch0: 3 transfers, incr_write only (read address fixed)
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 3)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_WR | CTRL_SIZE_WORD)

    await ClockCycles(dut.clk, 30)

    # All 3 destinations should have the same value
    for i in range(3):
        val = await mem_read(dut, 64 + i)
        assert val == 0x42, f"word {i}: expected 0x42, got 0x{val:08x}"


@cocotb.test()
async def test_channel_disable_auto(dut):
    """Channel auto-disables (EN=0) when count reaches zero."""
    await reset(dut)

    await mem_write(dut, 0, 0x1234)

    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 1)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD)

    await ClockCycles(dut.clk, 20)

    ctrl = await ahb_read(dut, CH_CTRL(0))
    assert (ctrl & CTRL_EN) == 0, f"channel should auto-disable, CTRL=0x{ctrl:08x}"

    count = await ahb_read(dut, CH_TRANS_COUNT(0))
    assert count == 0, f"count should be 0, got {count}"


@cocotb.test()
async def test_multi_channel_round_robin(dut):
    """Two channels running simultaneously get round-robin service."""
    await reset(dut)

    # Seed source for ch0 (words 0-3) and ch1 (words 8-11)
    for i in range(4):
        await mem_write(dut, i, 0xAA000000 + i)
        await mem_write(dut, 8 + i, 0xBB000000 + i)

    # Ch0: 4 words from 0x00 to 0x100
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 4)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD)

    # Ch1: 4 words from 0x20 to 0x140
    await ahb_write(dut, CH_READ_ADDR(1),  0x020)
    await ahb_write(dut, CH_WRITE_ADDR(1), 0x140)
    await ahb_write(dut, CH_TRANS_COUNT(1), 4)
    await ahb_write(dut, CH_CTRL(1), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD)

    # Wait for both to complete
    await ClockCycles(dut.clk, 80)

    # Verify ch0 destination
    for i in range(4):
        val = await mem_read(dut, 64 + i)
        assert val == 0xAA000000 + i, f"ch0 word {i}: expected 0x{0xAA000000+i:08x}, got 0x{val:08x}"

    # Verify ch1 destination
    for i in range(4):
        val = await mem_read(dut, 80 + i)
        assert val == 0xBB000000 + i, f"ch1 word {i}: expected 0x{0xBB000000+i:08x}, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Standalone runner
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import pathlib
    from cocotb_tools.runner import get_runner

    repo = pathlib.Path(__file__).resolve().parents[2]
    runner = get_runner("verilator")
    runner.build(
        verilog_sources=[
            str(repo / "rtl/soc/peripheral/dma.sv"),
            str(repo / "sim/tb/dma_test_wrapper.sv"),
        ],
        hdl_toplevel="dma_test_wrapper",
        build_args=["--trace", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="dma_test_wrapper", test_module="test_dma")
