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
    """Counter increments every clock with prescaler=0."""
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
    """Prescaler=4 → counter increments every 5 clocks."""
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
    """Disabling CTRL stops the counter."""
    await reset(dut)

    await ahb_write(dut, CTRL, 0)  # disable
    await ahb_write(dut, MTIME, 0)
    await ahb_write(dut, MTIMEH, 0)

    await ClockCycles(dut.clk, 50)
    t = await ahb_read(dut, MTIME)

    assert t == 0, f"counter should be stopped, got {t}"


@cocotb.test()
async def test_ctrl_reenable(dut):
    """Re-enabling CTRL resumes counting."""
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
    """Writing MTIME/MTIMEH sets the counter."""
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
    """Writing and reading MTIMECMP round-trips correctly."""
    await reset(dut)

    await ahb_write(dut, MTIMECMP, 0xCAFEBABE)
    await ahb_write(dut, MTIMECMPH, 0x01020304)

    lo = await ahb_read(dut, MTIMECMP)
    hi = await ahb_read(dut, MTIMECMPH)

    assert lo == 0xCAFEBABE, f"MTIMECMP low: expected 0xCAFEBABE, got 0x{lo:08x}"
    assert hi == 0x01020304, f"MTIMECMP high: expected 0x01020304, got 0x{hi:08x}"


@cocotb.test()
async def test_irq_fires_on_match(dut):
    """timer_irq asserts when mtime >= mtimecmp."""
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
    """Writing a future mtimecmp value clears the IRQ."""
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
    """dbg_halt freezes the counter."""
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
    """Counter rolls over from 0xFFFFFFFF to high word."""
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
        build_args=["--trace", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="timer", test_module="test_timer")
