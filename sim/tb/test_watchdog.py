"""CocoTB testbench for watchdog.sv — watchdog timer with 1 MHz tick."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Register offsets
CTRL   = 0x00
LOAD   = 0x04
COUNT  = 0x08
KICK   = 0x0C
REASON = 0x10

KICK_MAGIC = 0x6B696B6B

# Use CLK_HZ=10 for fast tests (tick every 10 clocks)


# ---------------------------------------------------------------------------
# AHB helpers
# ---------------------------------------------------------------------------

async def ahb_write(dut, addr, data):
    dut.htrans.value = 0b10
    dut.hwrite.value = 1
    dut.haddr.value = addr
    await RisingEdge(dut.clk)
    dut.htrans.value = 0b00
    dut.hwdata.value = data
    await RisingEdge(dut.clk)


async def ahb_read(dut, addr):
    dut.htrans.value = 0b10
    dut.hwrite.value = 0
    dut.haddr.value = addr
    await RisingEdge(dut.clk)
    dut.htrans.value = 0b00
    await RisingEdge(dut.clk)
    return int(dut.hrdata.value)


# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------

async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.dbg_halt.value = 0
    dut.htrans.value = 0
    dut.hwrite.value = 0
    dut.haddr.value = 0
    dut.hwdata.value = 0
    dut.hsize.value = 2

    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_disabled_by_default(dut):
    """Watchdog is disabled after reset — counter doesn't move."""
    await reset(dut)

    await ahb_write(dut, LOAD, 5)
    await ahb_write(dut, KICK, KICK_MAGIC)
    await ClockCycles(dut.clk, 200)

    count = await ahb_read(dut, COUNT)
    assert count == 5, f"counter should not decrement when disabled, got {count}"


@cocotb.test()
async def test_countdown(dut):
    """Enabled watchdog counts down."""
    await reset(dut)

    await ahb_write(dut, LOAD, 100)
    await ahb_write(dut, KICK, KICK_MAGIC)
    await ahb_write(dut, CTRL, 1)  # enable

    # CLK_HZ=10 → tick every 10 clocks. Wait 50 clocks = 5 ticks.
    await ClockCycles(dut.clk, 50)

    count = await ahb_read(dut, COUNT)
    # Should have decremented ~5 times (±1 for alignment)
    assert 93 <= count <= 97, f"expected ~95, got {count}"


@cocotb.test()
async def test_kick_reloads(dut):
    """Kicking reloads counter from LOAD value."""
    await reset(dut)

    await ahb_write(dut, LOAD, 50)
    await ahb_write(dut, KICK, KICK_MAGIC)
    await ahb_write(dut, CTRL, 1)

    # Let it count down a bit
    await ClockCycles(dut.clk, 200)  # ~20 ticks

    # Kick — should reload to 50
    await ahb_write(dut, KICK, KICK_MAGIC)
    await ClockCycles(dut.clk, 5)

    count = await ahb_read(dut, COUNT)
    assert count >= 48, f"counter should have reloaded to ~50, got {count}"


@cocotb.test()
async def test_wrong_magic_ignored(dut):
    """Writing wrong magic to KICK does nothing."""
    await reset(dut)

    await ahb_write(dut, LOAD, 50)
    await ahb_write(dut, KICK, KICK_MAGIC)
    await ahb_write(dut, CTRL, 1)

    # Let it count down
    await ClockCycles(dut.clk, 100)  # ~10 ticks

    count_before = await ahb_read(dut, COUNT)

    # Wrong magic
    await ahb_write(dut, KICK, 0xDEADBEEF)
    await ClockCycles(dut.clk, 5)

    count_after = await ahb_read(dut, COUNT)
    assert count_after <= count_before, f"wrong magic should not reload: {count_before} → {count_after}"


@cocotb.test()
async def test_timeout_reset(dut):
    """Counter reaching zero asserts wdog_reset."""
    await reset(dut)

    await ahb_write(dut, LOAD, 3)
    await ahb_write(dut, KICK, KICK_MAGIC)
    await ahb_write(dut, CTRL, 1)

    # Wait for timeout: 3 ticks × 10 clocks + margin
    saw_reset = False
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.wdog_reset.value) == 1:
            saw_reset = True
            break

    assert saw_reset, "wdog_reset should pulse on timeout"


@cocotb.test()
async def test_timeout_sets_reason(dut):
    """Timeout sets REASON[0]."""
    await reset(dut)

    await ahb_write(dut, LOAD, 2)
    await ahb_write(dut, KICK, KICK_MAGIC)
    await ahb_write(dut, CTRL, 1)

    await ClockCycles(dut.clk, 100)

    reason = await ahb_read(dut, REASON)
    assert reason & 1, f"REASON[0] should be set after timeout, got 0x{reason:x}"

    # Write-1-to-clear
    await ahb_write(dut, REASON, 1)
    reason = await ahb_read(dut, REASON)
    assert (reason & 1) == 0, f"REASON[0] should clear after W1C, got 0x{reason:x}"


@cocotb.test()
async def test_force_reset(dut):
    """Writing CTRL[31] forces immediate reset."""
    await reset(dut)

    assert int(dut.wdog_reset.value) == 0

    await ahb_write(dut, CTRL, (1 << 31))

    # Check wdog_reset pulsed
    # The write happens on the data phase, so check immediately
    saw_reset = False
    for _ in range(5):
        await RisingEdge(dut.clk)
        if int(dut.wdog_reset.value) == 1:
            saw_reset = True
            break

    assert saw_reset, "force reset should pulse wdog_reset"

    reason = await ahb_read(dut, REASON)
    assert reason & 2, f"REASON[1] should be set after force reset, got 0x{reason:x}"


@cocotb.test()
async def test_dbg_halt_pauses(dut):
    """dbg_halt pauses the counter when pause_on_debug is set."""
    await reset(dut)

    await ahb_write(dut, LOAD, 100)
    await ahb_write(dut, KICK, KICK_MAGIC)
    await ahb_write(dut, CTRL, 0b11)  # enable + pause_on_debug

    await ClockCycles(dut.clk, 50)  # ~5 ticks

    # Freeze
    dut.dbg_halt.value = 1
    count_before = await ahb_read(dut, COUNT)
    await ClockCycles(dut.clk, 200)
    count_after = await ahb_read(dut, COUNT)

    assert count_after == count_before, f"should be frozen: {count_before} → {count_after}"

    # Unfreeze
    dut.dbg_halt.value = 0
    await ClockCycles(dut.clk, 50)
    count_resumed = await ahb_read(dut, COUNT)

    assert count_resumed < count_before, f"should resume: {count_before} → {count_resumed}"


@cocotb.test()
async def test_tick_output(dut):
    """tick_1mhz pulses at the expected rate."""
    await reset(dut)

    # CLK_HZ=10 → tick every 10 clocks
    tick_count = 0
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.tick_1mhz.value) == 1:
            tick_count += 1

    # 100 clocks / 10 = 10 ticks (±1)
    assert 9 <= tick_count <= 11, f"expected ~10 ticks in 100 clocks, got {tick_count}"


# ---------------------------------------------------------------------------
# Standalone runner
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import pathlib
    from cocotb_tools.runner import get_runner

    repo = pathlib.Path(__file__).resolve().parents[2]
    runner = get_runner("verilator")
    runner.build(
        sources=[str(repo / "rtl/soc/peripheral/watchdog.sv")],
        hdl_toplevel="watchdog",
        build_args=["--trace", "-Wno-fatal"],
        parameters={"CLK_HZ": 10_000_000},
    )
    runner.test(hdl_toplevel="watchdog", test_module="test_watchdog")
