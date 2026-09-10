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
    """After POR, all peripherals are in reset, reason=POR."""
    await reset(dut)

    reset_reg = await ahb_read(dut, RESET)
    assert reset_reg == 0xFF, f"all peripherals should be in reset, got 0x{reset_reg:02x}"

    done = await ahb_read(dut, RESET_DONE)
    assert done == 0x00, f"no peripheral should be running, got 0x{done:02x}"

    reason = await ahb_read(dut, REASON)
    assert reason & 1, f"POR reason bit should be set, got 0x{reason:x}"


@cocotb.test()
async def test_release_single_peripheral(dut):
    """Releasing one peripheral from reset."""
    await reset(dut)

    # Release bit 3 (UART0)
    await ahb_write(dut, RESET, 0xF7)  # clear bit 3

    reset_reg = await ahb_read(dut, RESET)
    assert reset_reg == 0xF7, f"expected 0xF7, got 0x{reset_reg:02x}"

    done = await ahb_read(dut, RESET_DONE)
    assert done == 0x08, f"only bit 3 should be done, got 0x{done:02x}"

    # Check output pin
    periph = int(dut.periph_rst_n.value)
    assert periph & (1 << 3), f"periph_rst_n[3] should be deasserted, got 0x{periph:02x}"


@cocotb.test()
async def test_release_all_peripherals(dut):
    """Releasing all peripherals from reset."""
    await reset(dut)

    await ahb_write(dut, RESET, 0x00)

    done = await ahb_read(dut, RESET_DONE)
    assert done == 0xFF, f"all should be running, got 0x{done:02x}"

    periph = int(dut.periph_rst_n.value)
    assert periph == 0xFF, f"all periph_rst_n should be high, got 0x{periph:02x}"


@cocotb.test()
async def test_reassert_reset(dut):
    """Can re-assert reset on a running peripheral."""
    await reset(dut)

    # Release all
    await ahb_write(dut, RESET, 0x00)
    await ClockCycles(dut.clk, 2)

    # Re-assert reset on SPI (bit 4)
    await ahb_write(dut, RESET, 0x10)

    reset_reg = await ahb_read(dut, RESET)
    assert reset_reg == 0x10, f"expected 0x10, got 0x{reset_reg:02x}"

    periph = int(dut.periph_rst_n.value)
    assert not (periph & (1 << 4)), f"periph_rst_n[4] should be asserted, got 0x{periph:02x}"


@cocotb.test()
async def test_watchdog_resets_all(dut):
    """Watchdog timeout re-asserts all peripheral resets."""
    await reset(dut)

    # Release all peripherals
    await ahb_write(dut, RESET, 0x00)
    await ClockCycles(dut.clk, 2)

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

    # Release all
    await ahb_write(dut, RESET, 0x00)
    await ClockCycles(dut.clk, 2)

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
        build_args=["--trace", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="reset_controller", test_module="test_reset_controller")
