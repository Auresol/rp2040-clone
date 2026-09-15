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

def CTRL_CHAIN_TO(ch):  return (ch & 0xF) << 9
def CTRL_RING(sel, size): return ((sel & 1) << 13) | ((size & 0xF) << 14)
CTRL_RING_READ  = 0  # ring on read address
CTRL_RING_WRITE = 1  # ring on write address


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
# Tests — reset and register behavior
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset_state(dut):
    """After reset, all channel registers and IRQ_STATUS are 0.

    Pass: CTRL, TRANS_COUNT, IRQ_STATUS all read 0 for every channel.
    """
    await reset(dut)

    for ch in range(4):
        ctrl = await ahb_read(dut, CH_CTRL(ch))
        assert ctrl == 0, f"ch{ch} CTRL should be 0, got 0x{ctrl:08x}"
        tc = await ahb_read(dut, CH_TRANS_COUNT(ch))
        assert tc == 0, f"ch{ch} TRANS_COUNT should be 0, got {tc}"

    irq = await ahb_read(dut, IRQ_STATUS)
    assert irq == 0, f"IRQ_STATUS should be 0, got 0x{irq:x}"


@cocotb.test()
async def test_channel_isolation(dut):
    """Writing one channel's registers doesn't affect another channel.

    Pass: ch0 registers unchanged after writing ch1.
    """
    await reset(dut)

    await ahb_write(dut, CH_READ_ADDR(0),  0xAAAAAAAA)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0xBBBBBBBB)
    await ahb_write(dut, CH_TRANS_COUNT(0), 100)
    await ahb_write(dut, CH_CTRL(0), 0x1FF)

    # Write ch1 with different values
    await ahb_write(dut, CH_READ_ADDR(1),  0x11111111)
    await ahb_write(dut, CH_WRITE_ADDR(1), 0x22222222)
    await ahb_write(dut, CH_TRANS_COUNT(1), 200)
    await ahb_write(dut, CH_CTRL(1), 0x00)

    # Verify ch0 unchanged
    ra = await ahb_read(dut, CH_READ_ADDR(0))
    wa = await ahb_read(dut, CH_WRITE_ADDR(0))
    tc = await ahb_read(dut, CH_TRANS_COUNT(0))
    ct = await ahb_read(dut, CH_CTRL(0))

    assert ra == 0xAAAAAAAA, f"ch0 READ_ADDR: got 0x{ra:08x}"
    assert wa == 0xBBBBBBBB, f"ch0 WRITE_ADDR: got 0x{wa:08x}"
    assert tc == 100, f"ch0 TRANS_COUNT: got {tc}"
    assert ct == 0x1FF, f"ch0 CTRL: got 0x{ct:08x}"


@cocotb.test()
async def test_irq_requires_irq_en(dut):
    """IRQ does not fire when IRQ_EN is not set in CTRL.

    Pass: dma_irq stays low and IRQ_STATUS stays 0 after completion.
    """
    await reset(dut)

    await mem_write(dut, 0, 0xCAFE)
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 1)
    # EN but NO IRQ_EN
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD)

    await ClockCycles(dut.clk, 20)

    assert int(dut.dma_irq.value) == 0, "IRQ should not fire without IRQ_EN"
    irq = await ahb_read(dut, IRQ_STATUS)
    assert irq == 0, f"IRQ_STATUS should be 0, got 0x{irq:x}"


@cocotb.test()
async def test_irq_w1c_selective(dut):
    """Write-1-to-clear on IRQ_STATUS only clears targeted bits.

    Pass: clearing ch0 bit preserves ch1 bit.
    """
    await reset(dut)

    # Complete ch0 and ch1 with IRQ_EN
    for ch in range(2):
        await mem_write(dut, ch, 0x1000 + ch)
        await ahb_write(dut, CH_READ_ADDR(ch),  ch * 4)
        await ahb_write(dut, CH_WRITE_ADDR(ch), 0x100 + ch * 4)
        await ahb_write(dut, CH_TRANS_COUNT(ch), 1)
        await ahb_write(dut, CH_CTRL(ch), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD | CTRL_IRQ_EN)

    await ClockCycles(dut.clk, 40)

    irq = await ahb_read(dut, IRQ_STATUS)
    assert irq & 0x3, f"both ch0 and ch1 IRQ should be set, got 0x{irq:x}"

    # Clear only ch0
    await ahb_write(dut, IRQ_STATUS, 0x1)
    irq = await ahb_read(dut, IRQ_STATUS)
    assert irq == 0x2, f"only ch1 should remain, got 0x{irq:x}"


@cocotb.test()
async def test_no_incr_write(dut):
    """Fixed write address (fill peripheral FIFO pattern): writes same address repeatedly.

    Pass: destination word contains the last value written (all source words went to same place).
    """
    await reset(dut)

    for i in range(4):
        await mem_write(dut, i, 0x100 + i)

    # Ch0: 4 transfers, incr_read only (write address fixed at word 64)
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)  # word 64
    await ahb_write(dut, CH_TRANS_COUNT(0), 4)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_SIZE_WORD)

    await ClockCycles(dut.clk, 40)

    # Word 64 should have the last value written (0x103)
    val = await mem_read(dut, 64)
    assert val == 0x103, f"expected last value 0x103, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Tests — chain trigger
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_chain_trigger(dut):
    """Channel 0 completion triggers channel 1 via CHAIN_TO.

    Pass: ch1 auto-starts and completes its transfer after ch0 finishes.
    """
    await reset(dut)

    # Seed source for ch0 and ch1
    for i in range(2):
        await mem_write(dut, i, 0xAA00 + i)
    for i in range(2):
        await mem_write(dut, 4 + i, 0xBB00 + i)

    # Ch1: pre-configured but NOT enabled — ch0 will enable it
    await ahb_write(dut, CH_READ_ADDR(1),  0x010)   # word 4
    await ahb_write(dut, CH_WRITE_ADDR(1), 0x140)   # word 80
    await ahb_write(dut, CH_TRANS_COUNT(1), 2)
    await ahb_write(dut, CH_CTRL(1), CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD | CTRL_IRQ_EN)
    # Note: EN=0, ch0's chain trigger will set it

    # Ch0: 2 transfers, chain to ch1
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)   # word 64
    await ahb_write(dut, CH_TRANS_COUNT(0), 2)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD | CTRL_CHAIN_TO(1))

    # Wait for both to complete
    await ClockCycles(dut.clk, 60)

    # Verify ch0 output
    for i in range(2):
        val = await mem_read(dut, 64 + i)
        assert val == 0xAA00 + i, f"ch0 word {i}: expected 0x{0xAA00+i:04x}, got 0x{val:08x}"

    # Verify ch1 was triggered and completed
    for i in range(2):
        val = await mem_read(dut, 80 + i)
        assert val == 0xBB00 + i, f"ch1 word {i}: expected 0x{0xBB00+i:04x}, got 0x{val:08x}"

    # Ch1 should have fired IRQ
    irq = await ahb_read(dut, IRQ_STATUS)
    assert irq & 0x2, f"ch1 IRQ should be set, got 0x{irq:x}"


@cocotb.test()
async def test_chain_to_self_disabled(dut):
    """CHAIN_TO >= NUM_CH means no chaining (disabled).

    Pass: channel completes without triggering anything.
    """
    await reset(dut)

    await mem_write(dut, 0, 0x42)

    # Ch0: chain_to = 0xF (>= 4, disabled)
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 1)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD | CTRL_CHAIN_TO(0xF))

    await ClockCycles(dut.clk, 20)

    # Ch0 should be done and auto-disabled
    ctrl = await ahb_read(dut, CH_CTRL(0))
    assert (ctrl & CTRL_EN) == 0, f"ch0 should auto-disable, CTRL=0x{ctrl:08x}"

    # No other channel should have been enabled
    for ch in range(1, 4):
        c = await ahb_read(dut, CH_CTRL(ch))
        assert (c & CTRL_EN) == 0, f"ch{ch} should not be enabled, CTRL=0x{c:08x}"


# ---------------------------------------------------------------------------
# Tests — ring buffer
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_ring_read(dut):
    """Ring on read address: source wraps within a power-of-2 window.

    Pass: 4-word ring read copies the same 2-word pattern twice to dest.
    """
    await reset(dut)

    # Seed 2 words at address 0 (8-byte ring: ring_size=3, 2^3=8 bytes)
    await mem_write(dut, 0, 0xAAAA)
    await mem_write(dut, 1, 0xBBBB)

    # Ch0: 4 transfers, ring on read, ring_size=3 (8 bytes = 2 words)
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)  # word 64
    await ahb_write(dut, CH_TRANS_COUNT(0), 4)
    await ahb_write(dut, CH_CTRL(0),
        CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD |
        CTRL_RING(CTRL_RING_READ, 3))

    await ClockCycles(dut.clk, 40)

    # Dest should be: AAAA, BBBB, AAAA, BBBB
    expected = [0xAAAA, 0xBBBB, 0xAAAA, 0xBBBB]
    for i in range(4):
        val = await mem_read(dut, 64 + i)
        assert val == expected[i], f"word {i}: expected 0x{expected[i]:04x}, got 0x{val:08x}"


@cocotb.test()
async def test_ring_write(dut):
    """Ring on write address: dest wraps within a power-of-2 window.

    Pass: 4 source words write to a 2-word circular dest, last 2 values win.
    """
    await reset(dut)

    for i in range(4):
        await mem_write(dut, i, 0x1000 + i)

    # Ch0: 4 transfers, ring on write, ring_size=3 (8 bytes = 2 words)
    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)  # word 64
    await ahb_write(dut, CH_TRANS_COUNT(0), 4)
    await ahb_write(dut, CH_CTRL(0),
        CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD |
        CTRL_RING(CTRL_RING_WRITE, 3))

    await ClockCycles(dut.clk, 40)

    # Dest ring wraps: words 64,65,64,65 → last writes are 0x1002, 0x1003
    val0 = await mem_read(dut, 64)
    val1 = await mem_read(dut, 65)
    assert val0 == 0x1002, f"word 64: expected 0x1002 (overwritten), got 0x{val0:08x}"
    assert val1 == 0x1003, f"word 65: expected 0x1003 (overwritten), got 0x{val1:08x}"


# ---------------------------------------------------------------------------
# Tests — address increment for different DATA_SIZE
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_addr_incr_word(dut):
    """Word transfers increment addresses by 4.

    Pass: READ_ADDR advances by 4 per transfer.
    """
    await reset(dut)

    await mem_write(dut, 0, 0x11)
    await mem_write(dut, 1, 0x22)

    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 2)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD)

    await ClockCycles(dut.clk, 30)

    ra = await ahb_read(dut, CH_READ_ADDR(0))
    wa = await ahb_read(dut, CH_WRITE_ADDR(0))
    assert ra == 0x008, f"READ_ADDR should be 0x008 (2*4), got 0x{ra:03x}"
    assert wa == 0x108, f"WRITE_ADDR should be 0x108 (0x100+2*4), got 0x{wa:03x}"


@cocotb.test()
async def test_addr_incr_half(dut):
    """Halfword transfers increment addresses by 2.

    Pass: READ_ADDR advances by 2 per transfer.
    """
    await reset(dut)

    await mem_write(dut, 0, 0xAABBCCDD)

    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 2)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_HALF)

    await ClockCycles(dut.clk, 30)

    ra = await ahb_read(dut, CH_READ_ADDR(0))
    assert ra == 0x004, f"READ_ADDR should be 0x004 (2*2), got 0x{ra:03x}"


@cocotb.test()
async def test_addr_incr_byte(dut):
    """Byte transfers increment addresses by 1.

    Pass: READ_ADDR advances by 1 per transfer.
    """
    await reset(dut)

    await mem_write(dut, 0, 0xAABBCCDD)

    await ahb_write(dut, CH_READ_ADDR(0),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(0), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(0), 3)
    await ahb_write(dut, CH_CTRL(0), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_BYTE)

    await ClockCycles(dut.clk, 30)

    ra = await ahb_read(dut, CH_READ_ADDR(0))
    assert ra == 0x003, f"READ_ADDR should be 0x003 (3*1), got 0x{ra:03x}"


# ---------------------------------------------------------------------------
# Tests — DREQ on ch1
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_dreq_ch1(dut):
    """DREQ pacing works on channel 1 using dreq[1].

    Pass: transfer only proceeds after dreq[1] is asserted.
    """
    await reset(dut)

    await mem_write(dut, 0, 0xFEED)

    await ahb_write(dut, CH_READ_ADDR(1),  0x000)
    await ahb_write(dut, CH_WRITE_ADDR(1), 0x100)
    await ahb_write(dut, CH_TRANS_COUNT(1), 1)
    await ahb_write(dut, CH_CTRL(1), CTRL_EN | CTRL_INCR_RD | CTRL_INCR_WR | CTRL_SIZE_WORD | CTRL_DREQ_1)

    # No DREQ — should not transfer
    await ClockCycles(dut.clk, 20)
    val = await mem_read(dut, 64)
    assert val != 0xFEED, "should not transfer without DREQ"

    # Assert dreq[1]
    dut.dreq.value = 0b0010
    await ClockCycles(dut.clk, 15)
    dut.dreq.value = 0

    await ClockCycles(dut.clk, 10)
    val = await mem_read(dut, 64)
    assert val == 0xFEED, f"expected 0xFEED, got 0x{val:08x}"


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
        build_args=["--trace-fst", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="dma_test_wrapper", test_module="test_dma")
