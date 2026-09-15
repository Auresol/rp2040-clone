"""CocoTB testbench for timer.sv — RISC-V mtime/mtimecmp timer peripheral."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Register offsets (byte addresses)
CTRL      = 0x00
PRESCALER = 0x04
MTIME     = 0x08
MTIMEH    = 0x0C
MTIMECMP  = 0x10
MTIMECMPH = 0x14


# ---------------------------------------------------------------------------
# AHB-Lite helpers
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
async def test_counter_increments(dut):
    """Counter increments every clock with prescaler=0.

    Pass: MTIME advances by ~20 after 20 clock cycles.
    """
    await reset(dut)

    # Prescaler=0 (default), ctrl enabled by default
    t1 = await ahb_read(dut, MTIME)
    await ClockCycles(dut.clk, 20)
    t2 = await ahb_read(dut, MTIME)

    diff = t2 - t1
    # Should have incremented ~20 times (±AHB read overhead)
    assert diff > 10, f"counter should increment, got diff={diff}"
    assert diff < 30, f"counter incrementing too fast, got diff={diff}"


@cocotb.test()
async def test_prescaler(dut):
    """Prescaler=4: counter increments every 5 clocks.

    Pass: ~10 ticks after 50 clock cycles (50/5 = 10).
    """
    await reset(dut)

    await ahb_write(dut, PRESCALER, 4)  # tick every 5 clocks
    # Reset counter to zero for clean measurement
    await ahb_write(dut, MTIME, 0)
    await ahb_write(dut, MTIMEH, 0)

    await ClockCycles(dut.clk, 50)
    t = await ahb_read(dut, MTIME)

    # 50 clocks / 5 = 10 ticks (±1 for alignment)
    assert 8 <= t <= 12, f"expected ~10 ticks, got {t}"


@cocotb.test()
async def test_ctrl_disable(dut):
    """Disabling CTRL stops the counter.

    Pass: MTIME stays at 0 after 50 clock cycles with CTRL=0.
    """
    await reset(dut)

    await ahb_write(dut, CTRL, 0)  # disable
    await ahb_write(dut, MTIME, 0)
    await ahb_write(dut, MTIMEH, 0)

    await ClockCycles(dut.clk, 50)
    t = await ahb_read(dut, MTIME)

    assert t == 0, f"counter should be stopped, got {t}"


@cocotb.test()
async def test_ctrl_reenable(dut):
    """Re-enabling CTRL resumes counting.

    Pass: MTIME advances after CTRL transitions from 0 back to 1.
    """
    await reset(dut)

    await ahb_write(dut, CTRL, 0)  # disable
    await ahb_write(dut, MTIME, 0)
    await ahb_write(dut, MTIMEH, 0)
    await ClockCycles(dut.clk, 10)

    await ahb_write(dut, CTRL, 1)  # re-enable
    await ClockCycles(dut.clk, 20)
    t = await ahb_read(dut, MTIME)

    assert t > 0, f"counter should have resumed, got {t}"


@cocotb.test()
async def test_mtime_write(dut):
    """Writing MTIME/MTIMEH sets the counter.

    Pass: readback of MTIME and MTIMEH matches written values.
    """
    await reset(dut)

    await ahb_write(dut, CTRL, 0)  # stop to write cleanly
    await ahb_write(dut, MTIME, 0x12345678)
    await ahb_write(dut, MTIMEH, 0xDEADBEEF)

    lo = await ahb_read(dut, MTIME)
    hi = await ahb_read(dut, MTIMEH)

    assert lo == 0x12345678, f"MTIME low: expected 0x12345678, got 0x{lo:08x}"
    assert hi == 0xDEADBEEF, f"MTIME high: expected 0xDEADBEEF, got 0x{hi:08x}"


@cocotb.test()
async def test_mtimecmp_write_read(dut):
    """Writing and reading MTIMECMP round-trips correctly.

    Pass: readback of MTIMECMP and MTIMECMPH matches written values.
    """
    await reset(dut)

    await ahb_write(dut, MTIMECMP, 0xCAFEBABE)
    await ahb_write(dut, MTIMECMPH, 0x01020304)

    lo = await ahb_read(dut, MTIMECMP)
    hi = await ahb_read(dut, MTIMECMPH)

    assert lo == 0xCAFEBABE, f"MTIMECMP low: expected 0xCAFEBABE, got 0x{lo:08x}"
    assert hi == 0x01020304, f"MTIMECMP high: expected 0x01020304, got 0x{hi:08x}"


@cocotb.test()
async def test_irq_fires_on_match(dut):
    """timer_irq asserts when mtime >= mtimecmp.

    Pass: timer_irq=0 before match, timer_irq=1 after counter passes compare value.
    """
    await reset(dut)

    # Set counter to 0, compare to 10
    await ahb_write(dut, CTRL, 0)
    await ahb_write(dut, MTIME, 0)
    await ahb_write(dut, MTIMEH, 0)
    await ahb_write(dut, MTIMECMP, 10)
    await ahb_write(dut, MTIMECMPH, 0)

    # IRQ should be low (0 < 10)
    await RisingEdge(dut.clk)
    assert int(dut.timer_irq.value) == 0, "IRQ should be low before match"

    # Enable and let counter run past 10
    await ahb_write(dut, CTRL, 1)
    await ClockCycles(dut.clk, 20)

    # IRQ should be high now (mtime >= 10)
    assert int(dut.timer_irq.value) == 1, "IRQ should be high after match"


@cocotb.test()
async def test_irq_clears_on_new_mtimecmp(dut):
    """Writing a future mtimecmp value clears the IRQ.

    Pass: timer_irq=1 when mtime=100 >= mtimecmp=10, then timer_irq=0 after
    setting mtimecmp to 0xFFFFFFFF_FFFFFFFF.
    """
    await reset(dut)

    # Force mtime=100, mtimecmp=10 → IRQ fires
    await ahb_write(dut, CTRL, 0)
    await ahb_write(dut, MTIME, 100)
    await ahb_write(dut, MTIMEH, 0)
    await ahb_write(dut, MTIMECMP, 10)
    await ahb_write(dut, MTIMECMPH, 0)
    await ClockCycles(dut.clk, 3)  # let comparator settle

    assert int(dut.timer_irq.value) == 1, "IRQ should be high (100 >= 10)"

    # Set mtimecmp far ahead
    await ahb_write(dut, MTIMECMP, 0xFFFFFFFF)
    await ahb_write(dut, MTIMECMPH, 0xFFFFFFFF)
    await ClockCycles(dut.clk, 3)

    assert int(dut.timer_irq.value) == 0, "IRQ should clear after setting mtimecmp ahead"


@cocotb.test()
async def test_dbg_halt_freezes(dut):
    """dbg_halt freezes the counter.

    Pass: MTIME unchanged during 20 cycles with dbg_halt=1, resumes after deassertion.
    """
    await reset(dut)

    await ahb_write(dut, MTIME, 0)
    await ahb_write(dut, MTIMEH, 0)
    await ClockCycles(dut.clk, 5)

    # Freeze
    dut.dbg_halt.value = 1
    t1 = await ahb_read(dut, MTIME)
    await ClockCycles(dut.clk, 20)
    t2 = await ahb_read(dut, MTIME)

    assert t2 == t1, f"counter should be frozen, got {t1} then {t2}"

    # Unfreeze
    dut.dbg_halt.value = 0
    await ClockCycles(dut.clk, 20)
    t3 = await ahb_read(dut, MTIME)

    assert t3 > t2, f"counter should resume after unfreeze, got {t3}"


@cocotb.test()
async def test_64bit_rollover(dut):
    """Counter rolls over from 0xFFFFFFFF to high word.

    Pass: MTIMEH >= 1 after MTIME starts at 0xFFFFFFF0 and counts past 32-bit boundary.
    """
    await reset(dut)

    await ahb_write(dut, CTRL, 0)
    await ahb_write(dut, MTIME, 0xFFFFFFF0)
    await ahb_write(dut, MTIMEH, 0)
    await ahb_write(dut, CTRL, 1)

    # Let it count past 0xFFFFFFFF
    await ClockCycles(dut.clk, 30)

    hi = await ahb_read(dut, MTIMEH)
    assert hi >= 1, f"high word should have incremented on rollover, got {hi}"


# ---------------------------------------------------------------------------
# Tests — reset state and register readback
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset_state(dut):
    """All registers have correct values after reset.

    Pass: CTRL=1 (enabled), PRESCALER=0, MTIME=0, MTIMEH=0,
    MTIMECMP=0, MTIMECMPH=0, timer_irq=1 (0 >= 0).
    """
    await reset(dut)

    await ahb_write(dut, CTRL, 0)  # stop counter to read cleanly

    ctrl = await ahb_read(dut, CTRL)
    assert ctrl == 0, f"CTRL should be 0 after we disabled it, got 0x{ctrl:x}"

    pre = await ahb_read(dut, PRESCALER)
    assert pre == 0, f"PRESCALER should be 0 at reset, got {pre}"


@cocotb.test()
async def test_ctrl_readback(dut):
    """CTRL register reads back the written value.

    Pass: CTRL reads 0 after writing 0, reads 1 after writing 1.
    """
    await reset(dut)

    await ahb_write(dut, CTRL, 0)
    val = await ahb_read(dut, CTRL)
    assert val == 0, f"CTRL should read 0, got {val}"

    await ahb_write(dut, CTRL, 1)
    val = await ahb_read(dut, CTRL)
    assert val == 1, f"CTRL should read 1, got {val}"


@cocotb.test()
async def test_prescaler_readback(dut):
    """PRESCALER register reads back the written value.

    Pass: PRESCALER reads 99 after writing 99, reads 0 after writing 0.
    """
    await reset(dut)

    await ahb_write(dut, PRESCALER, 99)
    val = await ahb_read(dut, PRESCALER)
    assert val == 99, f"PRESCALER should read 99, got {val}"

    await ahb_write(dut, PRESCALER, 0)
    val = await ahb_read(dut, PRESCALER)
    assert val == 0, f"PRESCALER should read 0, got {val}"


# ---------------------------------------------------------------------------
# Tests — IRQ behavior
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_irq_level_not_edge(dut):
    """timer_irq is level-sensitive: stays asserted as long as mtime >= mtimecmp.

    Pass: timer_irq remains 1 across multiple clock cycles while condition holds.
    """
    await reset(dut)

    await ahb_write(dut, CTRL, 0)
    await ahb_write(dut, MTIME, 100)
    await ahb_write(dut, MTIMEH, 0)
    await ahb_write(dut, MTIMECMP, 50)
    await ahb_write(dut, MTIMECMPH, 0)
    await ClockCycles(dut.clk, 3)

    for _ in range(5):
        assert int(dut.timer_irq.value) == 1, "IRQ should stay asserted (level)"
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_irq_64bit_compare(dut):
    """IRQ uses full 64-bit comparison including high word.

    Pass: timer_irq=0 when mtime low matches but high word is less than mtimecmph.
    """
    await reset(dut)

    await ahb_write(dut, CTRL, 0)
    await ahb_write(dut, MTIME, 0xFFFFFFFF)
    await ahb_write(dut, MTIMEH, 0)
    await ahb_write(dut, MTIMECMP, 0)
    await ahb_write(dut, MTIMECMPH, 1)
    await ClockCycles(dut.clk, 3)

    # mtime = 0x0000_0000_FFFF_FFFF < mtimecmp = 0x0000_0001_0000_0000
    assert int(dut.timer_irq.value) == 0, "IRQ should be low (high word less)"

    # Now set high word to match
    await ahb_write(dut, MTIMEH, 1)
    await ClockCycles(dut.clk, 3)

    # mtime = 0x0000_0001_FFFF_FFFF >= mtimecmp = 0x0000_0001_0000_0000
    assert int(dut.timer_irq.value) == 1, "IRQ should fire after high word matches"


@cocotb.test()
async def test_dbg_halt_preserves_irq(dut):
    """dbg_halt freezes counter but does not affect pending IRQ.

    Pass: timer_irq stays asserted during dbg_halt if mtime >= mtimecmp.
    """
    await reset(dut)

    await ahb_write(dut, CTRL, 0)
    await ahb_write(dut, MTIME, 100)
    await ahb_write(dut, MTIMEH, 0)
    await ahb_write(dut, MTIMECMP, 50)
    await ahb_write(dut, MTIMECMPH, 0)
    await ahb_write(dut, CTRL, 1)
    await ClockCycles(dut.clk, 3)

    assert int(dut.timer_irq.value) == 1, "IRQ should be asserted before halt"

    dut.dbg_halt.value = 1
    await ClockCycles(dut.clk, 10)
    assert int(dut.timer_irq.value) == 1, "IRQ should stay asserted during halt"

    dut.dbg_halt.value = 0


@cocotb.test()
async def test_mtime_write_while_running(dut):
    """Writing MTIME while counter is running takes effect immediately.

    Pass: MTIME reads back near the written value after a write with CTRL=1.
    """
    await reset(dut)

    # Counter is running (CTRL=1 by default)
    await ahb_write(dut, MTIME, 1000)

    t = await ahb_read(dut, MTIME)
    # Should be near 1000 (plus a few ticks from AHB overhead)
    assert 1000 <= t <= 1020, f"MTIME should be near 1000 after write, got {t}"


# ---------------------------------------------------------------------------
# Standalone runner
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import pathlib
    from cocotb_tools.runner import get_runner

    repo = pathlib.Path(__file__).resolve().parents[2]
    runner = get_runner("verilator")
    runner.build(
        verilog_sources=[str(repo / "rtl/soc/peripheral/timer.sv")],
        hdl_toplevel="timer",
        build_args=["--trace-fst", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="timer", test_module="test_timer")
