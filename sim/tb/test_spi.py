"""CocoTB testbench for spi.sv — PL022-compatible SPI master peripheral."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles

# Register offsets (byte addresses)
SSPCR0  = 0x000
SSPCR1  = 0x004
SSPDR   = 0x008
SSPSR   = 0x00C
SSPCPSR = 0x010
SSPIMSC = 0x014
SSPRIS  = 0x018
SSPMIS  = 0x01C
SSPICR  = 0x020

# SSPSR bits
BSY = 1 << 4
RFF = 1 << 3
RNE = 1 << 2
TNF = 1 << 1
TFE = 1 << 0

# SSPCR1 bits
SSE = 1 << 1
LBM = 1 << 0


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


async def wait_idle(dut, timeout=2000):
    """Wait until BSY clears in SSPSR."""
    for _ in range(timeout):
        sr = await ahb_read(dut, SSPSR)
        if not (sr & BSY):
            return sr
        await RisingEdge(dut.clk)
    raise TimeoutError("SPI still busy after timeout")


# ---------------------------------------------------------------------------
# Reset + init
# ---------------------------------------------------------------------------

async def reset_and_init(dut, dss=7, cpol=0, cpha=0, scr=0, cpsr=2, loopback=True):
    """Start clock, reset, configure SPI."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.spi_miso.value = 0
    dut.htrans.value = 0
    dut.hwrite.value = 0
    dut.haddr.value = 0
    dut.hwdata.value = 0
    dut.hsize.value = 2

    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    cr0 = (scr << 8) | (cpha << 7) | (cpol << 6) | dss
    await ahb_write(dut, SSPCR0, cr0)
    await ahb_write(dut, SSPCPSR, cpsr)
    cr1 = SSE | (LBM if loopback else 0)
    await ahb_write(dut, SSPCR1, cr1)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_loopback_8bit(dut):
    """8-bit loopback: send 0xA5, verify RX gets 0xA5."""
    await reset_and_init(dut, dss=7)

    await ahb_write(dut, SSPDR, 0xA5)
    await wait_idle(dut)

    sr = await ahb_read(dut, SSPSR)
    assert sr & RNE, f"RNE should be set, SSPSR=0x{sr:02x}"

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == 0xA5, f"expected 0xA5, got 0x{got:04x}"


@cocotb.test()
async def test_loopback_16bit(dut):
    """16-bit loopback: send 0xBEEF, verify RX."""
    await reset_and_init(dut, dss=15)

    await ahb_write(dut, SSPDR, 0xBEEF)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFFFF) == 0xBEEF, f"expected 0xBEEF, got 0x{got:04x}"


@cocotb.test()
async def test_loopback_5bit(dut):
    """5-bit frame (DSS=4): send 0x15, verify only 5 bits loop back."""
    await reset_and_init(dut, dss=4)

    await ahb_write(dut, SSPDR, 0x15)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0x1F) == 0x15, f"expected 0x15, got 0x{got:02x}"


@cocotb.test()
async def test_back_to_back(dut):
    """Push two 8-bit values, verify both arrive in order."""
    await reset_and_init(dut, dss=7)

    await ahb_write(dut, SSPDR, 0x11)
    await ahb_write(dut, SSPDR, 0x22)
    await wait_idle(dut)

    v1 = await ahb_read(dut, SSPDR)
    v2 = await ahb_read(dut, SSPDR)
    assert (v1 & 0xFF) == 0x11, f"first: expected 0x11, got 0x{v1:02x}"
    assert (v2 & 0xFF) == 0x22, f"second: expected 0x22, got 0x{v2:02x}"


@cocotb.test()
async def test_status_flags(dut):
    """Verify TFE, TNF, RNE, BSY flag transitions."""
    await reset_and_init(dut, dss=7)

    # Initially: TFE=1, TNF=1, RNE=0, BSY=0
    sr = await ahb_read(dut, SSPSR)
    assert sr & TFE, f"TFE should be set on empty FIFO, SSPSR=0x{sr:02x}"
    assert sr & TNF, f"TNF should be set, SSPSR=0x{sr:02x}"
    assert not (sr & RNE), f"RNE should be clear, SSPSR=0x{sr:02x}"
    assert not (sr & BSY), f"BSY should be clear, SSPSR=0x{sr:02x}"

    # After send + complete: RNE=1, TFE=1
    await ahb_write(dut, SSPDR, 0x42)
    await wait_idle(dut)

    sr = await ahb_read(dut, SSPSR)
    assert sr & TFE, f"TFE should be set after drain, SSPSR=0x{sr:02x}"
    assert sr & RNE, f"RNE should be set with data in RX, SSPSR=0x{sr:02x}"


@cocotb.test()
async def test_cpol1_cpha0(dut):
    """CPOL=1, CPHA=0 loopback."""
    await reset_and_init(dut, dss=7, cpol=1, cpha=0)

    await ahb_write(dut, SSPDR, 0x7E)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == 0x7E, f"CPOL1/CPHA0: expected 0x7E, got 0x{got:02x}"


@cocotb.test()
async def test_cpol0_cpha1(dut):
    """CPOL=0, CPHA=1 loopback."""
    await reset_and_init(dut, dss=7, cpol=0, cpha=1)

    await ahb_write(dut, SSPDR, 0xC3)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == 0xC3, f"CPOL0/CPHA1: expected 0xC3, got 0x{got:02x}"


@cocotb.test()
async def test_cpol1_cpha1(dut):
    """CPOL=1, CPHA=1 loopback."""
    await reset_and_init(dut, dss=7, cpol=1, cpha=1)

    await ahb_write(dut, SSPDR, 0x5A)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == 0x5A, f"CPOL1/CPHA1: expected 0x5A, got 0x{got:02x}"


@cocotb.test()
async def test_cs_n_behavior(dut):
    """CS_N should be high when idle, low during transfer."""
    await reset_and_init(dut, dss=7)

    # Idle — CS should be high
    assert int(dut.spi_cs_n.value) == 1, "CS_N should be high when idle"

    # Start a transfer
    await ahb_write(dut, SSPDR, 0x00)
    # Give a few cycles for the engine to start
    await ClockCycles(dut.clk, 6)

    sr = await ahb_read(dut, SSPSR)
    if sr & BSY:
        assert int(dut.spi_cs_n.value) == 0, "CS_N should be low during transfer"

    await wait_idle(dut)


@cocotb.test()
async def test_sck_idle_level(dut):
    """SCK idle level should match CPOL."""
    # CPOL=0 → SCK idle low
    await reset_and_init(dut, dss=7, cpol=0)
    assert int(dut.spi_sclk.value) == 0, "SCK should idle low when CPOL=0"

    # CPOL=1 → SCK idle high
    await reset_and_init(dut, dss=7, cpol=1)
    assert int(dut.spi_sclk.value) == 1, "SCK should idle high when CPOL=1"


# ---------------------------------------------------------------------------
# Standalone runner
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import pathlib
    from cocotb_tools.runner import get_runner

    repo = pathlib.Path(__file__).resolve().parents[2]
    runner = get_runner("verilator")
    runner.build(
        verilog_sources=[str(repo / "rtl/soc/peripheral/spi.sv")],
        hdl_toplevel="spi",
        build_args=["--trace", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="spi", test_module="test_spi")
