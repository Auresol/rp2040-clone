"""CocoTB testbench for reset_controller.sv."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Register offsets
RESET      = 0x00
RESET_DONE = 0x04
REASON     = 0x08
CHIP_RESET = 0x0C


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

    dut.por_n.value = 0
    dut.wdog_reset.value = 0
    dut.htrans.value = 0
    dut.hwrite.value = 0
    dut.haddr.value = 0
    dut.hwdata.value = 0
    dut.hsize.value = 2

    await ClockCycles(dut.clk, 3)
    dut.por_n.value = 1
    await RisingEdge(dut.clk)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_por_defaults(dut):
    """After POR, all peripherals are released (FPGA default), reason=POR."""
    await reset(dut)

    reset_reg = await ahb_read(dut, RESET)
    assert reset_reg == 0x00, f"all peripherals should be released (FPGA default), got 0x{reset_reg:02x}"

    done = await ahb_read(dut, RESET_DONE)
    assert done == 0xFF, f"all peripherals should be running, got 0x{done:02x}"

    reason = await ahb_read(dut, REASON)
    assert reason & 1, f"POR reason bit should be set, got 0x{reason:x}"


@cocotb.test()
async def test_assert_single_peripheral(dut):
    """Asserting reset on one peripheral."""
    await reset(dut)

    # Assert reset on bit 3 (UART0)
    await ahb_write(dut, RESET, 0x08)

    reset_reg = await ahb_read(dut, RESET)
    assert reset_reg == 0x08, f"expected 0x08, got 0x{reset_reg:02x}"

    done = await ahb_read(dut, RESET_DONE)
    assert done == 0xF7, f"all but bit 3 should be done, got 0x{done:02x}"

    # Check output pin
    periph = int(dut.periph_rst_n.value)
    assert not (periph & (1 << 3)), f"periph_rst_n[3] should be asserted, got 0x{periph:02x}"


@cocotb.test()
async def test_assert_then_release_all(dut):
    """Assert reset on all, then release."""
    await reset(dut)

    # Assert all
    await ahb_write(dut, RESET, 0xFF)
    done = await ahb_read(dut, RESET_DONE)
    assert done == 0x00, f"none should be running, got 0x{done:02x}"

    # Release all
    await ahb_write(dut, RESET, 0x00)
    done = await ahb_read(dut, RESET_DONE)
    assert done == 0xFF, f"all should be running, got 0x{done:02x}"

    periph = int(dut.periph_rst_n.value)
    assert periph == 0xFF, f"all periph_rst_n should be high, got 0x{periph:02x}"


@cocotb.test()
async def test_reassert_reset(dut):
    """Can assert reset on a running peripheral."""
    await reset(dut)

    # All running by default, assert reset on SPI (bit 4)
    await ahb_write(dut, RESET, 0x10)

    reset_reg = await ahb_read(dut, RESET)
    assert reset_reg == 0x10, f"expected 0x10, got 0x{reset_reg:02x}"

    periph = int(dut.periph_rst_n.value)
    assert not (periph & (1 << 4)), f"periph_rst_n[4] should be asserted, got 0x{periph:02x}"


@cocotb.test()
async def test_watchdog_resets_all(dut):
    """Watchdog timeout re-asserts all peripheral resets."""
    await reset(dut)

    # All running by default
    done = await ahb_read(dut, RESET_DONE)
    assert done == 0xFF, f"all should be running before wdog, got 0x{done:02x}"

    # Watchdog fires
    dut.wdog_reset.value = 1
    await RisingEdge(dut.clk)
    dut.wdog_reset.value = 0
    await ClockCycles(dut.clk, 2)

    reset_reg = await ahb_read(dut, RESET)
    assert reset_reg == 0xFF, f"all should be back in reset after wdog, got 0x{reset_reg:02x}"

    reason = await ahb_read(dut, REASON)
    assert reason & 2, f"watchdog reason bit should be set, got 0x{reason:x}"


@cocotb.test()
async def test_watchdog_resets_cpu(dut):
    """Watchdog timeout asserts cpu_rst_n."""
    await reset(dut)
    await ClockCycles(dut.clk, 3)

    # CPU should be running
    assert int(dut.cpu_rst_n.value) == 1, "CPU should be out of reset"

    # Watchdog fires
    dut.wdog_reset.value = 1
    await RisingEdge(dut.clk)
    dut.wdog_reset.value = 0

    # CPU should be reset for at least one cycle
    await RisingEdge(dut.clk)
    assert int(dut.cpu_rst_n.value) == 0, "CPU should be in reset after wdog"

    # Auto-releases
    await ClockCycles(dut.clk, 2)
    assert int(dut.cpu_rst_n.value) == 1, "CPU should auto-release from reset"


@cocotb.test()
async def test_software_chip_reset(dut):
    """Writing CHIP_RESET re-asserts all resets."""
    await reset(dut)

    # Software chip reset
    await ahb_write(dut, CHIP_RESET, 1)
    await ClockCycles(dut.clk, 3)

    reset_reg = await ahb_read(dut, RESET)
    assert reset_reg == 0xFF, f"all should be in reset after chip reset, got 0x{reset_reg:02x}"

    reason = await ahb_read(dut, REASON)
    assert reason & 4, f"software reset reason should be set, got 0x{reason:x}"


@cocotb.test()
async def test_reason_w1c(dut):
    """Reason bits are write-1-to-clear."""
    await reset(dut)

    reason = await ahb_read(dut, REASON)
    assert reason & 1, f"POR bit should be set, got 0x{reason:x}"

    # Clear POR bit
    await ahb_write(dut, REASON, 1)
    reason = await ahb_read(dut, REASON)
    assert (reason & 1) == 0, f"POR bit should be cleared, got 0x{reason:x}"


@cocotb.test()
async def test_reason_sticky(dut):
    """Reason bits accumulate across multiple reset events."""
    await reset(dut)

    # POR reason should be set
    reason = await ahb_read(dut, REASON)
    assert reason == 1, f"expected POR only, got 0x{reason:x}"

    # Trigger watchdog
    dut.wdog_reset.value = 1
    await RisingEdge(dut.clk)
    dut.wdog_reset.value = 0
    await ClockCycles(dut.clk, 3)

    reason = await ahb_read(dut, REASON)
    assert reason == 3, f"expected POR+wdog (0x3), got 0x{reason:x}"


# ---------------------------------------------------------------------------
# Tests — register behavior
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_chip_reset_reads_zero(dut):
    """CHIP_RESET register always reads as 0 (write-only, self-clearing).

    Pass: reading CHIP_RESET returns 0 before and after writing 1 to it.
    """
    await reset(dut)

    val = await ahb_read(dut, CHIP_RESET)
    assert val == 0, f"CHIP_RESET should read 0 before write, got 0x{val:x}"

    await ahb_write(dut, CHIP_RESET, 1)
    await ClockCycles(dut.clk, 3)

    val = await ahb_read(dut, CHIP_RESET)
    assert val == 0, f"CHIP_RESET should read 0 after write, got 0x{val:x}"


@cocotb.test()
async def test_chip_reset_zero_is_noop(dut):
    """Writing 0 to CHIP_RESET does not trigger a reset.

    Pass: RESET register and periph_rst_n unchanged after writing 0 to CHIP_RESET.
    """
    await reset(dut)

    reset_before = await ahb_read(dut, RESET)
    await ahb_write(dut, CHIP_RESET, 0)
    await ClockCycles(dut.clk, 3)

    reset_after = await ahb_read(dut, RESET)
    assert reset_after == reset_before, f"RESET should be unchanged, was 0x{reset_before:02x} now 0x{reset_after:02x}"


@cocotb.test()
async def test_bit_isolation(dut):
    """Resetting one peripheral does not affect others.

    Pass: only the targeted bit changes in RESET and periph_rst_n; all other bits stay 0.
    """
    await reset(dut)

    # Assert reset on bit 5 only
    await ahb_write(dut, RESET, 0x20)

    reset_reg = await ahb_read(dut, RESET)
    assert reset_reg == 0x20, f"expected only bit 5 set, got 0x{reset_reg:02x}"

    periph = int(dut.periph_rst_n.value)
    # bit 5 should be 0 (in reset), all others 1 (running)
    assert periph == 0xDF, f"periph_rst_n should be 0xDF, got 0x{periph:02x}"


@cocotb.test()
async def test_cpu_auto_release_timing(dut):
    """CPU reset auto-releases exactly 1 cycle after watchdog pulse ends.

    Pass: cpu_rst_n goes low for exactly 1 cycle, then returns high.
    """
    await reset(dut)
    await ClockCycles(dut.clk, 3)
    assert int(dut.cpu_rst_n.value) == 1, "CPU should be running"

    # Fire watchdog
    dut.wdog_reset.value = 1
    await RisingEdge(dut.clk)
    dut.wdog_reset.value = 0

    # Should be in reset now
    await RisingEdge(dut.clk)
    assert int(dut.cpu_rst_n.value) == 0, "CPU should be in reset"

    # Should auto-release next cycle
    await RisingEdge(dut.clk)
    assert int(dut.cpu_rst_n.value) == 1, "CPU should auto-release after 1 cycle"


@cocotb.test()
async def test_reason_w1c_selective(dut):
    """Write-1-to-clear on REASON only clears targeted bits, not others.

    Pass: clearing bit 0 (POR) preserves bit 1 (WDOG) if both are set.
    """
    await reset(dut)

    # Set both POR and WDOG reason
    dut.wdog_reset.value = 1
    await RisingEdge(dut.clk)
    dut.wdog_reset.value = 0
    await ClockCycles(dut.clk, 3)

    reason = await ahb_read(dut, REASON)
    assert reason == 0x3, f"expected POR+WDOG (0x3), got 0x{reason:x}"

    # Clear only POR bit
    await ahb_write(dut, REASON, 0x1)
    reason = await ahb_read(dut, REASON)
    assert reason == 0x2, f"expected WDOG only (0x2) after clearing POR, got 0x{reason:x}"


@cocotb.test()
async def test_periph_rst_n_tracks_reset_reg(dut):
    """periph_rst_n output is the combinational inverse of the RESET register.

    Pass: periph_rst_n == ~RESET for several different RESET values.
    """
    await reset(dut)

    for pattern in [0x00, 0xFF, 0xAA, 0x55, 0x01, 0x80]:
        await ahb_write(dut, RESET, pattern)
        await RisingEdge(dut.clk)  # wait for register update to propagate
        periph = int(dut.periph_rst_n.value)
        expected = (~pattern) & 0xFF
        assert periph == expected, f"RESET=0x{pattern:02x}: periph_rst_n=0x{periph:02x}, expected 0x{expected:02x}"


@cocotb.test()
async def test_reset_done_mirrors_running(dut):
    """RESET_DONE reads as ~RESET (all bits inverted).

    Pass: RESET_DONE == ~RESET for several patterns.
    """
    await reset(dut)

    for pattern in [0x00, 0xFF, 0x0F, 0xF0]:
        await ahb_write(dut, RESET, pattern)
        done = await ahb_read(dut, RESET_DONE)
        expected = (~pattern) & 0xFF
        assert done == expected, f"RESET=0x{pattern:02x}: RESET_DONE=0x{done:02x}, expected 0x{expected:02x}"


# ---------------------------------------------------------------------------
# Standalone runner
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import pathlib
    from cocotb_tools.runner import get_runner

    repo = pathlib.Path(__file__).resolve().parents[2]
    runner = get_runner("verilator")
    runner.build(
        sources=[str(repo / "rtl/soc/peripheral/reset_controller.sv")],
        hdl_toplevel="reset_controller",
        build_args=["--trace-fst", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="reset_controller", test_module="test_reset_controller")
