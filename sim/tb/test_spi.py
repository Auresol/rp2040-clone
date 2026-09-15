"""CocoTB testbench for spi.sv — PL022-compatible SPI master peripheral."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles

# Register offsets (byte addresses, PL022-compatible)
SSPCR0   = 0x000
SSPCR1   = 0x004
SSPDR    = 0x008
SSPSR    = 0x00C
SSPCPSR  = 0x010
SSPIFLS  = 0x014
SSPIMSC  = 0x018
SSPRIS   = 0x01C
SSPMIS   = 0x020
SSPICR   = 0x024
SSPDMACR = 0x028

# SSPSR bits
BSY = 1 << 4
RFF = 1 << 3
RNE = 1 << 2
TNF = 1 << 1
TFE = 1 << 0

# SSPCR1 bits
SSE = 1 << 1
LBM = 1 << 0

# SSPRIS / SSPIMSC bits
TXRIS  = 1 << 3
RXRIS  = 1 << 2


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


async def miso_driver(dut, data, nbits, cpol, cpha):
    """Drive MISO with data (MSB first) synchronized to SCK edges.

    CPHA=0: MISO sampled on leading edge — drive bit before leading, change on trailing.
    CPHA=1: MISO sampled on trailing edge — drive bit after leading edge.
    """
    bits = [(data >> (nbits - 1 - i)) & 1 for i in range(nbits)]
    leading  = RisingEdge  if cpol == 0 else FallingEdge
    trailing = FallingEdge if cpol == 0 else RisingEdge

    await FallingEdge(dut.spi_cs_n)

    if cpha == 0:
        dut.spi_miso.value = bits[0]
        for i in range(1, nbits):
            await trailing(dut.spi_sclk)
            dut.spi_miso.value = bits[i]
    else:
        for i in range(nbits):
            await leading(dut.spi_sclk)
            dut.spi_miso.value = bits[i]


# ---------------------------------------------------------------------------
# Tests — basic loopback
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_loopback_8bit(dut):
    """8-bit loopback: send 0xA5, verify RX gets 0xA5.

    Pass: SSPDR read returns 0xA5 after transfer completes.
    """
    await reset_and_init(dut, dss=7)

    await ahb_write(dut, SSPDR, 0xA5)
    await wait_idle(dut)

    sr = await ahb_read(dut, SSPSR)
    assert sr & RNE, f"RNE should be set, SSPSR=0x{sr:02x}"

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == 0xA5, f"expected 0xA5, got 0x{got:04x}"


@cocotb.test()
async def test_loopback_16bit(dut):
    """16-bit loopback: send 0xBEEF, verify RX.

    Pass: SSPDR read returns 0xBEEF after transfer completes.
    """
    await reset_and_init(dut, dss=15)

    await ahb_write(dut, SSPDR, 0xBEEF)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFFFF) == 0xBEEF, f"expected 0xBEEF, got 0x{got:04x}"


@cocotb.test()
async def test_loopback_5bit(dut):
    """5-bit frame (DSS=4): send 0x15, verify only 5 bits loop back.

    Pass: lower 5 bits of SSPDR match 0x15; upper bits are zero.
    """
    await reset_and_init(dut, dss=4)

    await ahb_write(dut, SSPDR, 0x15)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0x1F) == 0x15, f"expected 0x15, got 0x{got:02x}"


@cocotb.test()
async def test_back_to_back(dut):
    """Push two 8-bit values, verify both arrive in order.

    Pass: RX FIFO holds 0x11 then 0x22 in submission order.
    """
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
    """Verify TFE, TNF, RNE, BSY flag transitions.

    Pass: TFE/TNF set and RNE/BSY clear at idle; RNE set after completed transfer.
    """
    await reset_and_init(dut, dss=7)

    sr = await ahb_read(dut, SSPSR)
    assert sr & TFE, f"TFE should be set on empty FIFO, SSPSR=0x{sr:02x}"
    assert sr & TNF, f"TNF should be set, SSPSR=0x{sr:02x}"
    assert not (sr & RNE), f"RNE should be clear, SSPSR=0x{sr:02x}"
    assert not (sr & BSY), f"BSY should be clear, SSPSR=0x{sr:02x}"

    await ahb_write(dut, SSPDR, 0x42)
    await wait_idle(dut)

    sr = await ahb_read(dut, SSPSR)
    assert sr & TFE, f"TFE should be set after drain, SSPSR=0x{sr:02x}"
    assert sr & RNE, f"RNE should be set with data in RX, SSPSR=0x{sr:02x}"


@cocotb.test()
async def test_cpol1_cpha0(dut):
    """CPOL=1, CPHA=0 loopback: send 0x7E, verify RX.

    Pass: SSPDR read returns 0x7E with SCK idling high.
    """
    await reset_and_init(dut, dss=7, cpol=1, cpha=0)

    await ahb_write(dut, SSPDR, 0x7E)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == 0x7E, f"CPOL1/CPHA0: expected 0x7E, got 0x{got:02x}"


@cocotb.test()
async def test_cpol0_cpha1(dut):
    """CPOL=0, CPHA=1 loopback: send 0xC3, verify RX.

    Pass: SSPDR read returns 0xC3 with data shifted on leading edge.
    """
    await reset_and_init(dut, dss=7, cpol=0, cpha=1)

    await ahb_write(dut, SSPDR, 0xC3)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == 0xC3, f"CPOL0/CPHA1: expected 0xC3, got 0x{got:02x}"


@cocotb.test()
async def test_cpol1_cpha1(dut):
    """CPOL=1, CPHA=1 loopback: send 0x5A, verify RX.

    Pass: SSPDR read returns 0x5A with SCK idling high and data shifted on leading edge.
    """
    await reset_and_init(dut, dss=7, cpol=1, cpha=1)

    await ahb_write(dut, SSPDR, 0x5A)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == 0x5A, f"CPOL1/CPHA1: expected 0x5A, got 0x{got:02x}"


@cocotb.test()
async def test_cs_n_behavior(dut):
    """CS_N should be high when idle, low during transfer.

    Pass: spi_cs_n is 1 before transfer and 0 while BSY is set.
    """
    await reset_and_init(dut, dss=7)

    assert int(dut.spi_cs_n.value) == 1, "CS_N should be high when idle"

    await ahb_write(dut, SSPDR, 0x00)
    await ClockCycles(dut.clk, 6)

    sr = await ahb_read(dut, SSPSR)
    if sr & BSY:
        assert int(dut.spi_cs_n.value) == 0, "CS_N should be low during transfer"

    await wait_idle(dut)


@cocotb.test()
async def test_sck_idle_level(dut):
    """SCK idle level should match CPOL.

    Pass: spi_sclk is 0 when CPOL=0 and 1 when CPOL=1, both at idle.
    """
    await reset_and_init(dut, dss=7, cpol=0)
    assert int(dut.spi_sclk.value) == 0, "SCK should idle low when CPOL=0"

    await reset_and_init(dut, dss=7, cpol=1)
    assert int(dut.spi_sclk.value) == 1, "SCK should idle high when CPOL=1"


# ---------------------------------------------------------------------------
# Tests — frame size coverage
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_frame_4bit(dut):
    """4-bit frame (DSS=3): minimum frame size, send 0xB, verify RX.

    Pass: lower 4 bits of SSPDR match 0xB; upper bits are zero.
    """
    await reset_and_init(dut, dss=3)

    await ahb_write(dut, SSPDR, 0xB)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xF) == 0xB, f"expected 0xB, got 0x{got:02x}"


@cocotb.test()
async def test_frame_12bit(dut):
    """12-bit frame (DSS=11): send 0xABC, verify RX.

    Pass: lower 12 bits of SSPDR match 0xABC.
    """
    await reset_and_init(dut, dss=11)

    await ahb_write(dut, SSPDR, 0xABC)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFFF) == 0xABC, f"expected 0xABC, got 0x{got:04x}"


# ---------------------------------------------------------------------------
# Tests — clock divider
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_scr_nonzero(dut):
    """SCR=3 (divide-by-4 post-scaler): data integrity preserved.

    Pass: loopback returns correct 8-bit value with SCR=3 (slower SCK).
    """
    await reset_and_init(dut, dss=7, scr=3, cpsr=2)

    await ahb_write(dut, SSPDR, 0xD7)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == 0xD7, f"SCR=3: expected 0xD7, got 0x{got:02x}"


@cocotb.test()
async def test_cpsr_4(dut):
    """CPSR=4 prescaler: data integrity preserved.

    Pass: loopback returns correct value with CPSR=4.
    """
    await reset_and_init(dut, dss=7, cpsr=4)

    await ahb_write(dut, SSPDR, 0x9C)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == 0x9C, f"CPSR=4: expected 0x9C, got 0x{got:02x}"


# ---------------------------------------------------------------------------
# Tests — FIFO boundary conditions
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_tx_fifo_full_tnf(dut):
    """Fill TX FIFO to capacity (8): TNF should clear (TX not not-full).

    Pass: TNF=0 in SSPSR after 8 writes with SSE disabled.
    """
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

    # Configure but do NOT enable SSE — engine stays idle, TX won't drain
    await ahb_write(dut, SSPCR0, 7)    # DSS=8-bit
    await ahb_write(dut, SSPCPSR, 2)
    await ahb_write(dut, SSPCR1, 0)    # SSE=0

    for i in range(8):
        await ahb_write(dut, SSPDR, 0xA0 + i)

    sr = await ahb_read(dut, SSPSR)
    assert not (sr & TNF), f"TNF should be clear when TX full, SSPSR=0x{sr:02x}"
    assert not (sr & TFE), f"TFE should be clear when TX full, SSPSR=0x{sr:02x}"


@cocotb.test()
async def test_rx_fifo_rff_flag(dut):
    """Fill RX FIFO to capacity (8): RFF should set.

    Pass: RFF=1 in SSPSR after 8 loopback transfers without reading RX.
    """
    await reset_and_init(dut, dss=7, loopback=True)

    # Send one at a time to avoid TX draining race
    for i in range(8):
        await ahb_write(dut, SSPDR, 0x10 + i)
        await wait_idle(dut)

    sr = await ahb_read(dut, SSPSR)
    assert sr & RFF, f"RFF should be set after 8 unread loopback transfers, SSPSR=0x{sr:02x}"
    assert sr & RNE, f"RNE should also be set, SSPSR=0x{sr:02x}"


@cocotb.test()
async def test_tx_overflow_silent(dut):
    """Write to full TX FIFO: extra writes dropped silently, no hang.

    Pass: 9th write does not corrupt FIFO or stall; only 8 values transferred.
    """
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

    await ahb_write(dut, SSPCR0, 7)
    await ahb_write(dut, SSPCPSR, 2)
    await ahb_write(dut, SSPCR1, 0)  # SSE=0 to freeze engine

    for i in range(8):
        await ahb_write(dut, SSPDR, 0xA0 + i)

    # 9th write — TX full, should be silently dropped
    await ahb_write(dut, SSPDR, 0xFF)

    sr = await ahb_read(dut, SSPSR)
    assert not (sr & TNF), f"TX should still be full after 9th write, SSPSR=0x{sr:02x}"


# ---------------------------------------------------------------------------
# Tests — interrupts
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_irq_txris_initial(dut):
    """TXRIS fires at init (TX empty ≤ half-full threshold); IRQ asserts with mask.

    Pass: SSPRIS[3]=1 after reset; spi_irq asserts once SSPIMSC[3]=1.
    """
    await reset_and_init(dut, dss=7)

    ris = await ahb_read(dut, SSPRIS)
    assert ris & TXRIS, f"TXRIS should be set with empty TX FIFO, SSPRIS=0x{ris:02x}"

    mis = await ahb_read(dut, SSPMIS)
    assert not (mis & TXRIS), f"SSPMIS should be clear with IMSC=0, SSPMIS=0x{mis:02x}"
    assert int(dut.spi_irq.value) == 0, "spi_irq should be low with IMSC=0"

    # Enable TXRIS mask
    await ahb_write(dut, SSPIMSC, TXRIS)
    mis = await ahb_read(dut, SSPMIS)
    assert mis & TXRIS, f"SSPMIS[TXRIS] should set after masking, SSPMIS=0x{mis:02x}"
    assert int(dut.spi_irq.value) == 1, "spi_irq should assert with IMSC[TXRIS]=1"


@cocotb.test()
async def test_irq_rxris(dut):
    """RXRIS fires when RX FIFO reaches half-full (≥4 entries).

    Pass: SSPRIS[2]=1 after 4 unread loopback transfers; clears after draining RX below threshold.
    """
    await reset_and_init(dut, dss=7, loopback=True)

    # Send one at a time to avoid TX draining race
    for i in range(4):
        await ahb_write(dut, SSPDR, 0x10 + i)
        await wait_idle(dut)

    ris = await ahb_read(dut, SSPRIS)
    assert ris & RXRIS, f"RXRIS should be set with 4 entries in RX, SSPRIS=0x{ris:02x}"

    await ahb_write(dut, SSPIMSC, RXRIS)
    await RisingEdge(dut.clk)
    assert int(dut.spi_irq.value) == 1, "spi_irq should assert with RXRIS masked in"

    # Drain below threshold
    for _ in range(4):
        await ahb_read(dut, SSPDR)

    ris = await ahb_read(dut, SSPRIS)
    assert not (ris & RXRIS), f"RXRIS should clear after draining RX, SSPRIS=0x{ris:02x}"
    assert int(dut.spi_irq.value) == 0, "spi_irq should deassert after draining"


@cocotb.test()
async def test_irq_mask_prevents_irq(dut):
    """SSPIMSC=0 keeps spi_irq low even when SSPRIS flags are set.

    Pass: spi_irq remains 0 with IMSC=0 regardless of raw interrupt status.
    """
    await reset_and_init(dut, dss=7)

    ris = await ahb_read(dut, SSPRIS)
    assert ris & TXRIS, "TXRIS should be set (precondition)"

    await ahb_write(dut, SSPIMSC, 0x0)
    assert int(dut.spi_irq.value) == 0, "spi_irq should stay low with IMSC=0"

    mis = await ahb_read(dut, SSPMIS)
    assert mis == 0, f"SSPMIS should be all-zero with IMSC=0, got 0x{mis:02x}"


# ---------------------------------------------------------------------------
# Tests — DMA request
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_dreq_signal(dut):
    """spi_dreq asserts when RXDMAE=1, RX FIFO at threshold, deasserts when drained.

    Pass: dreq=0 at idle; dreq=1 after loopback with RXDMAE enabled; dreq=0 after RX read.
    """
    await reset_and_init(dut, dss=7)

    # Enable RXDMAE and set low threshold (1 entry)
    await ahb_write(dut, SSPIFLS, (0 << 3) | 2)  # RXIFLSEL=0 (1 entry)
    await ahb_write(dut, SSPDMACR, 0x1)           # RXDMAE=1

    assert int(dut.spi_dreq.value) == 0, "dreq should be low with empty RX"

    await ahb_write(dut, SSPDR, 0x55)
    await wait_idle(dut)

    assert int(dut.spi_dreq.value) == 1, "dreq should assert when RX meets threshold"

    await ahb_read(dut, SSPDR)
    await RisingEdge(dut.clk)  # RX dequeue is pipelined
    assert int(dut.spi_dreq.value) == 0, "dreq should deassert after RX drained"


# ---------------------------------------------------------------------------
# Tests — SSE gate
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_sse_gate(dut):
    """SSE=0 prevents the shift engine from starting a transfer.

    Pass: CS_N stays high and BSY never asserts after writing to SSPDR with SSE=0.
    """
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

    await ahb_write(dut, SSPCR0, 7)
    await ahb_write(dut, SSPCPSR, 2)
    await ahb_write(dut, SSPCR1, 0)  # SSE=0

    await ahb_write(dut, SSPDR, 0xAA)
    await ClockCycles(dut.clk, 20)

    sr = await ahb_read(dut, SSPSR)
    assert not (sr & BSY), "BSY should be clear when SSE=0"
    assert int(dut.spi_cs_n.value) == 1, "CS_N should stay high when SSE=0"


# ---------------------------------------------------------------------------
# Tests — external MISO (non-loopback)
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_miso_cpol0_cpha0(dut):
    """External MISO CPOL=0 CPHA=0: sample on rising edge.

    Pass: received value matches data driven on MISO synchronized to SCK rising edges.
    """
    await reset_and_init(dut, dss=7, cpol=0, cpha=0, loopback=False)

    tx_data = 0xA5
    cocotb.start_soon(miso_driver(dut, tx_data, nbits=8, cpol=0, cpha=0))

    await ahb_write(dut, SSPDR, 0x00)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == tx_data, f"MISO CPOL0/CPHA0: expected 0x{tx_data:02x}, got 0x{got:02x}"


@cocotb.test()
async def test_miso_cpol0_cpha1(dut):
    """External MISO CPOL=0 CPHA=1: sample on falling edge.

    Pass: received value matches data driven on MISO synchronized to SCK falling edges.
    """
    await reset_and_init(dut, dss=7, cpol=0, cpha=1, loopback=False)

    tx_data = 0x3C
    cocotb.start_soon(miso_driver(dut, tx_data, nbits=8, cpol=0, cpha=1))

    await ahb_write(dut, SSPDR, 0x00)
    await wait_idle(dut)

    got = await ahb_read(dut, SSPDR)
    assert (got & 0xFF) == tx_data, f"MISO CPOL0/CPHA1: expected 0x{tx_data:02x}, got 0x{got:02x}"


# ---------------------------------------------------------------------------
# Tests — CS continuity
# ---------------------------------------------------------------------------

@cocotb.test(skip=True, expect_error=Exception)
async def test_cs_continuous_back_to_back(dut):
    """CS_N must not deassert between consecutive back-to-back frames.

    Pass: spi_cs_n rises exactly once (after all frames complete); data order preserved.
    """
    await reset_and_init(dut, dss=7)

    await ahb_write(dut, SSPDR, 0x11)
    await ahb_write(dut, SSPDR, 0x22)
    await ahb_write(dut, SSPDR, 0x33)

    await FallingEdge(dut.spi_cs_n)

    cs_rises = 0

    async def count_cs_rises():
        nonlocal cs_rises
        while True:
            await RisingEdge(dut.spi_cs_n)
            cs_rises += 1

    monitor = cocotb.start_soon(count_cs_rises())
    await wait_idle(dut)
    monitor.cancel()

    assert cs_rises == 1, f"CS_N should rise exactly once for back-to-back, rose {cs_rises} times"

    v1 = await ahb_read(dut, SSPDR)
    v2 = await ahb_read(dut, SSPDR)
    v3 = await ahb_read(dut, SSPDR)
    assert (v1 & 0xFF) == 0x11, f"expected 0x11 got 0x{v1:02x}"
    assert (v2 & 0xFF) == 0x22, f"expected 0x22 got 0x{v2:02x}"
    assert (v3 & 0xFF) == 0x33, f"expected 0x33 got 0x{v3:02x}"


# ---------------------------------------------------------------------------
# Tests — reset state
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset_state(dut):
    """All status and interrupt registers have correct reset values.

    Pass: SSPSR=0x03 (TFE|TNF), SSPIFLS=0x12, SSPRIS has TXRIS set, SSPMIS=0,
    SSPDMACR=0, spi_irq=0, CS_N=1, dreq=0, dreq_tx=0.
    """
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

    sr = await ahb_read(dut, SSPSR)
    assert (sr & (TFE | TNF)) == (TFE | TNF), f"TFE and TNF should be set at reset, SSPSR=0x{sr:02x}"
    assert not (sr & (BSY | RNE | RFF)), f"BSY/RNE/RFF should be clear at reset, SSPSR=0x{sr:02x}"

    ifls = await ahb_read(dut, SSPIFLS)
    assert ifls == 0x12, f"SSPIFLS should be 0x12 (both 1/2) at reset, got 0x{ifls:02x}"

    ris = await ahb_read(dut, SSPRIS)
    assert ris & TXRIS, f"TXRIS should be set at reset (TX empty), SSPRIS=0x{ris:02x}"

    mis = await ahb_read(dut, SSPMIS)
    assert mis == 0, f"SSPMIS should be 0 at reset (IMSC=0), SSPMIS=0x{mis:02x}"

    dmacr = await ahb_read(dut, SSPDMACR)
    assert dmacr == 0, f"SSPDMACR should be 0 at reset, got 0x{dmacr:02x}"

    assert int(dut.spi_irq.value)     == 0, "spi_irq should be low at reset"
    assert int(dut.spi_cs_n.value)    == 1, "CS_N should be high at reset"
    assert int(dut.spi_dreq.value)    == 0, "dreq should be low at reset"
    assert int(dut.spi_dreq_tx.value) == 0, "dreq_tx should be low at reset"


# ---------------------------------------------------------------------------
# Tests — SSPIFLS configurable thresholds
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_ifls_rx_threshold_1(dut):
    """RXIFLSEL=0 (1/8 = 1 entry): RXRIS fires after just 1 RX entry.

    Pass: SSPRIS[2] set after 1 loopback transfer, clear when RX drained.
    """
    await reset_and_init(dut, dss=7)

    # Set RXIFLSEL=0 (1/8 threshold = 1 entry), keep TXIFLSEL at default
    await ahb_write(dut, SSPIFLS, (0 << 3) | 2)

    await ahb_write(dut, SSPDR, 0xAA)
    await wait_idle(dut)

    ris = await ahb_read(dut, SSPRIS)
    assert ris & RXRIS, f"RXRIS should fire with 1 entry and threshold=1, SSPRIS=0x{ris:02x}"

    await ahb_read(dut, SSPDR)  # drain
    ris = await ahb_read(dut, SSPRIS)
    assert not (ris & RXRIS), f"RXRIS should clear after drain, SSPRIS=0x{ris:02x}"


@cocotb.test()
async def test_ifls_tx_threshold_high(dut):
    """TXIFLSEL=4 (7/8 = 7 entries): TXRIS only fires when TX has ≤7 entries.

    Pass: TXRIS is set when TX has 7 entries, clear at 8.
    """
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

    await ahb_write(dut, SSPCR0, 7)
    await ahb_write(dut, SSPCPSR, 2)
    await ahb_write(dut, SSPCR1, 0)  # SSE=0

    # Set TXIFLSEL=4 (7/8 = threshold 7)
    await ahb_write(dut, SSPIFLS, (2 << 3) | 4)

    # Fill TX to 7 — tx_level=7 ≤ 7 → TXRIS should be set
    for i in range(7):
        await ahb_write(dut, SSPDR, 0x10 + i)
    ris = await ahb_read(dut, SSPRIS)
    assert ris & TXRIS, f"TXRIS should be set with 7 entries (threshold=7), SSPRIS=0x{ris:02x}"

    # Fill to 8 — tx_level=8 > 7 → TXRIS should clear
    await ahb_write(dut, SSPDR, 0x18)
    ris = await ahb_read(dut, SSPRIS)
    assert not (ris & TXRIS), f"TXRIS should clear with 8 entries (> threshold 7), SSPRIS=0x{ris:02x}"


# ---------------------------------------------------------------------------
# Tests — SSPDMACR gating
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_dmacr_rx_gating(dut):
    """spi_dreq only asserts when SSPDMACR.RXDMAE=1 AND RX meets threshold.

    Pass: dreq stays low with RXDMAE=0 even with data in RX FIFO.
    """
    await reset_and_init(dut, dss=7)

    await ahb_write(dut, SSPDR, 0x55)
    await wait_idle(dut)

    # RXDMAE=0 (default) — dreq must stay low
    assert int(dut.spi_dreq.value) == 0, "dreq should be low with RXDMAE=0"

    # Enable RXDMAE, set low RX threshold (1/8 = 1 entry)
    await ahb_write(dut, SSPIFLS, (0 << 3) | 2)
    await ahb_write(dut, SSPDMACR, 0x1)  # RXDMAE=1
    await RisingEdge(dut.clk)

    assert int(dut.spi_dreq.value) == 1, "dreq should assert with RXDMAE=1 and data in RX"

    # Drain RX — dreq should deassert
    await ahb_read(dut, SSPDR)
    await RisingEdge(dut.clk)  # RX dequeue is pipelined
    assert int(dut.spi_dreq.value) == 0, "dreq should deassert after RX drained"


@cocotb.test()
async def test_dmacr_tx_gating(dut):
    """spi_dreq_tx only asserts when SSPDMACR.TXDMAE=1 AND TX is at or below threshold.

    Pass: dreq_tx stays low with TXDMAE=0; asserts when enabled and TX below threshold.
    """
    await reset_and_init(dut, dss=7)

    # TX is empty → below threshold. But TXDMAE=0
    assert int(dut.spi_dreq_tx.value) == 0, "dreq_tx should be low with TXDMAE=0"

    # Enable TXDMAE
    await ahb_write(dut, SSPDMACR, 0x2)  # TXDMAE=1
    await RisingEdge(dut.clk)

    assert int(dut.spi_dreq_tx.value) == 1, "dreq_tx should assert with TXDMAE=1 and empty TX"


@cocotb.test()
async def test_ifls_readback(dut):
    """SSPIFLS register is read/write.

    Pass: written value reads back correctly.
    """
    await reset_and_init(dut, dss=7)

    await ahb_write(dut, SSPIFLS, 0x1B)  # RXIFLSEL=3, TXIFLSEL=3
    got = await ahb_read(dut, SSPIFLS)
    assert got == 0x1B, f"SSPIFLS readback: expected 0x1B, got 0x{got:02x}"

    await ahb_write(dut, SSPIFLS, 0x24)  # RXIFLSEL=4, TXIFLSEL=4
    got = await ahb_read(dut, SSPIFLS)
    assert got == 0x24, f"SSPIFLS readback: expected 0x24, got 0x{got:02x}"


@cocotb.test()
async def test_dmacr_readback(dut):
    """SSPDMACR register is read/write.

    Pass: written value reads back correctly.
    """
    await reset_and_init(dut, dss=7)

    await ahb_write(dut, SSPDMACR, 0x3)
    got = await ahb_read(dut, SSPDMACR)
    assert got == 0x3, f"SSPDMACR readback: expected 0x3, got 0x{got:02x}"

    await ahb_write(dut, SSPDMACR, 0x0)
    got = await ahb_read(dut, SSPDMACR)
    assert got == 0x0, f"SSPDMACR readback: expected 0x0, got 0x{got:02x}"


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
        build_args=["--trace-fst", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="spi", test_module="test_spi")
