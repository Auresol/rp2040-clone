"""CocoTB testbench for gpio.sv — SIO-style GPIO with SET/CLR/XOR and OE."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

# Register offsets
GPIO_IN      = 0x00
GPIO_OUT     = 0x04
GPIO_OUT_SET = 0x08
GPIO_OUT_CLR = 0x0C
GPIO_OUT_XOR = 0x10
GPIO_OE      = 0x14
GPIO_OE_SET  = 0x18
GPIO_OE_CLR  = 0x1C
GPIO_OE_XOR  = 0x20


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
    dut.htrans.value = 0
    dut.hwrite.value = 0
    dut.haddr.value = 0
    dut.hwdata.value = 0
    dut.hsize.value = 2
    dut.gpio_in.value = 0

    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


# ---------------------------------------------------------------------------
# Tests — reset state
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_reset_state(dut):
    """After reset, GPIO_OUT and GPIO_OE are both 0.

    Pass: reading GPIO_OUT and GPIO_OE returns 0x00000000.
    """
    await reset(dut)

    out = await ahb_read(dut, GPIO_OUT)
    assert out == 0, f"GPIO_OUT should be 0 after reset, got 0x{out:08x}"

    oe = await ahb_read(dut, GPIO_OE)
    assert oe == 0, f"GPIO_OE should be 0 after reset, got 0x{oe:08x}"


@cocotb.test()
async def test_gpio_out_write_read(dut):
    """GPIO_OUT is read/write.

    Pass: value written to GPIO_OUT reads back correctly.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xDEADBEEF)
    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0xDEADBEEF, f"expected 0xDEADBEEF, got 0x{val:08x}"


@cocotb.test()
async def test_gpio_out_drives_pin(dut):
    """gpio_out output port tracks the GPIO_OUT register.

    Pass: gpio_out matches written value after register update propagates.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0x12345678)
    await RisingEdge(dut.clk)  # register update propagates

    pin = int(dut.gpio_out.value)
    assert pin == 0x12345678, f"gpio_out pin should be 0x12345678, got 0x{pin:08x}"


# ---------------------------------------------------------------------------
# Tests — GPIO_IN
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_gpio_in_reads_pads(dut):
    """GPIO_IN reads the current gpio_in input value.

    Pass: GPIO_IN returns the value driven on gpio_in pins.
    """
    await reset(dut)

    dut.gpio_in.value = 0xCAFEBABE
    await RisingEdge(dut.clk)

    val = await ahb_read(dut, GPIO_IN)
    assert val == 0xCAFEBABE, f"expected 0xCAFEBABE, got 0x{val:08x}"


@cocotb.test()
async def test_gpio_in_changes(dut):
    """GPIO_IN tracks changes on gpio_in pins.

    Pass: two successive reads return different values when gpio_in changes.
    """
    await reset(dut)

    dut.gpio_in.value = 0x11111111
    await RisingEdge(dut.clk)
    val1 = await ahb_read(dut, GPIO_IN)

    dut.gpio_in.value = 0x22222222
    await RisingEdge(dut.clk)
    val2 = await ahb_read(dut, GPIO_IN)

    assert val1 == 0x11111111, f"first read expected 0x11111111, got 0x{val1:08x}"
    assert val2 == 0x22222222, f"second read expected 0x22222222, got 0x{val2:08x}"


# ---------------------------------------------------------------------------
# Tests — SET/CLR/XOR on GPIO_OUT
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_out_set(dut):
    """GPIO_OUT_SET atomically sets bits in GPIO_OUT.

    Pass: only targeted bits are set; other bits unchanged.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0x0000FF00)
    await ahb_write(dut, GPIO_OUT_SET, 0x000000FF)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0x0000FFFF, f"expected 0x0000FFFF, got 0x{val:08x}"


@cocotb.test()
async def test_out_clr(dut):
    """GPIO_OUT_CLR atomically clears bits in GPIO_OUT.

    Pass: only targeted bits are cleared; other bits unchanged.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0x0000FFFF)
    await ahb_write(dut, GPIO_OUT_CLR, 0x000000FF)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0x0000FF00, f"expected 0x0000FF00, got 0x{val:08x}"


@cocotb.test()
async def test_out_xor(dut):
    """GPIO_OUT_XOR atomically toggles bits in GPIO_OUT.

    Pass: targeted bits are inverted; other bits unchanged.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0x0000FFFF)
    await ahb_write(dut, GPIO_OUT_XOR, 0x00FF00FF)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0x00FFFF00, f"expected 0x00FFFF00, got 0x{val:08x}"


@cocotb.test()
async def test_out_set_read_returns_out(dut):
    """Reading GPIO_OUT_SET returns GPIO_OUT value (not the SET mask).

    Pass: read from SET alias matches GPIO_OUT.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xAAAAAAAA)
    val = await ahb_read(dut, GPIO_OUT_SET)
    assert val == 0xAAAAAAAA, f"SET alias should read GPIO_OUT, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Tests — GPIO_OE
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_oe_write_read(dut):
    """GPIO_OE is read/write.

    Pass: value written to GPIO_OE reads back correctly.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE, 0xFF00FF00)
    val = await ahb_read(dut, GPIO_OE)
    assert val == 0xFF00FF00, f"expected 0xFF00FF00, got 0x{val:08x}"


@cocotb.test()
async def test_oe_drives_pin(dut):
    """gpio_oe output port tracks the GPIO_OE register.

    Pass: gpio_oe matches written value after register update propagates.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE, 0x0F0F0F0F)
    await RisingEdge(dut.clk)

    pin = int(dut.gpio_oe.value)
    assert pin == 0x0F0F0F0F, f"gpio_oe pin should be 0x0F0F0F0F, got 0x{pin:08x}"


@cocotb.test()
async def test_oe_set(dut):
    """GPIO_OE_SET atomically sets bits in GPIO_OE.

    Pass: only targeted bits are set.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE, 0x00FF0000)
    await ahb_write(dut, GPIO_OE_SET, 0x0000FF00)

    val = await ahb_read(dut, GPIO_OE)
    assert val == 0x00FFFF00, f"expected 0x00FFFF00, got 0x{val:08x}"


@cocotb.test()
async def test_oe_clr(dut):
    """GPIO_OE_CLR atomically clears bits in GPIO_OE.

    Pass: only targeted bits are cleared.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE, 0x00FFFF00)
    await ahb_write(dut, GPIO_OE_CLR, 0x0000FF00)

    val = await ahb_read(dut, GPIO_OE)
    assert val == 0x00FF0000, f"expected 0x00FF0000, got 0x{val:08x}"


@cocotb.test()
async def test_oe_xor(dut):
    """GPIO_OE_XOR atomically toggles bits in GPIO_OE.

    Pass: targeted bits are inverted.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE, 0xFFFF0000)
    await ahb_write(dut, GPIO_OE_XOR, 0xFF00FF00)

    val = await ahb_read(dut, GPIO_OE)
    assert val == 0x00FFFF00, f"expected 0x00FFFF00, got 0x{val:08x}"


@cocotb.test()
async def test_oe_set_read_returns_oe(dut):
    """Reading GPIO_OE_SET returns GPIO_OE value.

    Pass: read from OE_SET alias matches GPIO_OE.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE, 0x55555555)
    val = await ahb_read(dut, GPIO_OE_SET)
    assert val == 0x55555555, f"OE_SET alias should read GPIO_OE, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Tests — isolation and independence
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_out_and_oe_independent(dut):
    """Writing GPIO_OUT does not affect GPIO_OE and vice versa.

    Pass: each register retains its value after the other is written.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xAAAAAAAA)
    await ahb_write(dut, GPIO_OE, 0x55555555)

    out = await ahb_read(dut, GPIO_OUT)
    oe = await ahb_read(dut, GPIO_OE)

    assert out == 0xAAAAAAAA, f"GPIO_OUT should be 0xAAAAAAAA, got 0x{out:08x}"
    assert oe == 0x55555555, f"GPIO_OE should be 0x55555555, got 0x{oe:08x}"


@cocotb.test()
async def test_set_clr_sequence(dut):
    """SET then CLR on the same bits cancels out.

    Pass: GPIO_OUT returns to original value after SET then CLR of same mask.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0x00000000)
    await ahb_write(dut, GPIO_OUT_SET, 0xFF)
    await ahb_write(dut, GPIO_OUT_CLR, 0xFF)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0x00000000, f"expected 0x00000000 after SET+CLR, got 0x{val:08x}"


@cocotb.test()
async def test_xor_twice_restores(dut):
    """XOR applied twice restores the original value.

    Pass: GPIO_OUT unchanged after two identical XOR writes.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0x12345678)
    await ahb_write(dut, GPIO_OUT_XOR, 0xFFFFFFFF)
    await ahb_write(dut, GPIO_OUT_XOR, 0xFFFFFFFF)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0x12345678, f"expected 0x12345678 after double XOR, got 0x{val:08x}"


@cocotb.test()
async def test_gpio_in_readonly(dut):
    """Writing to GPIO_IN has no effect (read-only register).

    Pass: gpio_out unchanged after writing to GPIO_IN address.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0x11111111)
    await ahb_write(dut, GPIO_IN, 0xFFFFFFFF)  # should be ignored

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0x11111111, f"GPIO_OUT should be unchanged, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Tests — alias reads (CLR, XOR, OE_CLR, OE_XOR)
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_out_clr_read_returns_out(dut):
    """Reading GPIO_OUT_CLR returns GPIO_OUT value.

    Pass: read from CLR alias matches GPIO_OUT.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xBBBBBBBB)
    val = await ahb_read(dut, GPIO_OUT_CLR)
    assert val == 0xBBBBBBBB, f"CLR alias should read GPIO_OUT, got 0x{val:08x}"


@cocotb.test()
async def test_out_xor_read_returns_out(dut):
    """Reading GPIO_OUT_XOR returns GPIO_OUT value.

    Pass: read from XOR alias matches GPIO_OUT.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xCCCCCCCC)
    val = await ahb_read(dut, GPIO_OUT_XOR)
    assert val == 0xCCCCCCCC, f"XOR alias should read GPIO_OUT, got 0x{val:08x}"


@cocotb.test()
async def test_oe_clr_read_returns_oe(dut):
    """Reading GPIO_OE_CLR returns GPIO_OE value.

    Pass: read from OE_CLR alias matches GPIO_OE.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE, 0xDDDDDDDD)
    val = await ahb_read(dut, GPIO_OE_CLR)
    assert val == 0xDDDDDDDD, f"OE_CLR alias should read GPIO_OE, got 0x{val:08x}"


@cocotb.test()
async def test_oe_xor_read_returns_oe(dut):
    """Reading GPIO_OE_XOR returns GPIO_OE value.

    Pass: read from OE_XOR alias matches GPIO_OE.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE, 0xEEEEEEEE)
    val = await ahb_read(dut, GPIO_OE_XOR)
    assert val == 0xEEEEEEEE, f"OE_XOR alias should read GPIO_OE, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Tests — single-bit isolation
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_single_bit_set(dut):
    """SET on a single bit does not affect adjacent bits.

    Pass: only bit 16 is set; all others remain 0.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT_SET, 1 << 16)
    val = await ahb_read(dut, GPIO_OUT)
    assert val == (1 << 16), f"expected only bit 16, got 0x{val:08x}"


@cocotb.test()
async def test_single_bit_clr(dut):
    """CLR on a single bit does not affect adjacent bits.

    Pass: only bit 0 is cleared from all-ones.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xFFFFFFFF)
    await ahb_write(dut, GPIO_OUT_CLR, 1 << 0)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0xFFFFFFFE, f"expected 0xFFFFFFFE, got 0x{val:08x}"


@cocotb.test()
async def test_single_bit_xor(dut):
    """XOR on a single bit toggles only that bit.

    Pass: only bit 31 is toggled.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0x00000000)
    await ahb_write(dut, GPIO_OUT_XOR, 1 << 31)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0x80000000, f"expected 0x80000000, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Tests — idempotent and no-op cases
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_set_already_set(dut):
    """SET on bits that are already 1 is a no-op.

    Pass: GPIO_OUT unchanged after setting bits that are already set.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xFF00FF00)
    await ahb_write(dut, GPIO_OUT_SET, 0xFF00FF00)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0xFF00FF00, f"expected 0xFF00FF00, got 0x{val:08x}"


@cocotb.test()
async def test_clr_already_clear(dut):
    """CLR on bits that are already 0 is a no-op.

    Pass: GPIO_OUT unchanged after clearing bits that are already clear.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xFF00FF00)
    await ahb_write(dut, GPIO_OUT_CLR, 0x00FF00FF)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0xFF00FF00, f"expected 0xFF00FF00, got 0x{val:08x}"


@cocotb.test()
async def test_set_zero_is_noop(dut):
    """SET with value 0 does not change GPIO_OUT.

    Pass: GPIO_OUT unchanged after SET with 0x00000000.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xABCD1234)
    await ahb_write(dut, GPIO_OUT_SET, 0x00000000)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0xABCD1234, f"expected 0xABCD1234, got 0x{val:08x}"


@cocotb.test()
async def test_clr_zero_is_noop(dut):
    """CLR with value 0 does not change GPIO_OUT.

    Pass: GPIO_OUT unchanged after CLR with 0x00000000.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xABCD1234)
    await ahb_write(dut, GPIO_OUT_CLR, 0x00000000)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0xABCD1234, f"expected 0xABCD1234, got 0x{val:08x}"


@cocotb.test()
async def test_xor_zero_is_noop(dut):
    """XOR with value 0 does not change GPIO_OUT.

    Pass: GPIO_OUT unchanged after XOR with 0x00000000.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xABCD1234)
    await ahb_write(dut, GPIO_OUT_XOR, 0x00000000)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0xABCD1234, f"expected 0xABCD1234, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Tests — direct overwrite after atomic ops
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_out_direct_overwrite(dut):
    """Direct write to GPIO_OUT replaces the value regardless of prior atomic ops.

    Pass: GPIO_OUT matches last direct write, not accumulated atomic result.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT_SET, 0x000000FF)
    await ahb_write(dut, GPIO_OUT_SET, 0x0000FF00)
    await ahb_write(dut, GPIO_OUT, 0x42)  # direct overwrite

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0x42, f"expected 0x00000042, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Tests — OE atomic sequences
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_oe_set_clr_sequence(dut):
    """OE SET then CLR on the same bits cancels out.

    Pass: GPIO_OE returns to 0 after SET then CLR of same mask.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE_SET, 0x0F0F0F0F)
    await ahb_write(dut, GPIO_OE_CLR, 0x0F0F0F0F)

    val = await ahb_read(dut, GPIO_OE)
    assert val == 0x00000000, f"expected 0x00000000 after SET+CLR, got 0x{val:08x}"


@cocotb.test()
async def test_oe_xor_twice_restores(dut):
    """OE XOR applied twice restores the original value.

    Pass: GPIO_OE unchanged after two identical XOR writes.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE, 0xF0F0F0F0)
    await ahb_write(dut, GPIO_OE_XOR, 0xFFFFFFFF)
    await ahb_write(dut, GPIO_OE_XOR, 0xFFFFFFFF)

    val = await ahb_read(dut, GPIO_OE)
    assert val == 0xF0F0F0F0, f"expected 0xF0F0F0F0 after double XOR, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Tests — boundary values
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_out_all_ones(dut):
    """GPIO_OUT can hold 0xFFFFFFFF.

    Pass: all 32 bits read back as 1.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xFFFFFFFF)
    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0xFFFFFFFF, f"expected 0xFFFFFFFF, got 0x{val:08x}"


@cocotb.test()
async def test_oe_all_ones(dut):
    """GPIO_OE can hold 0xFFFFFFFF.

    Pass: all 32 bits read back as 1.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OE, 0xFFFFFFFF)
    val = await ahb_read(dut, GPIO_OE)
    assert val == 0xFFFFFFFF, f"expected 0xFFFFFFFF, got 0x{val:08x}"


@cocotb.test()
async def test_gpio_in_all_ones(dut):
    """GPIO_IN reads 0xFFFFFFFF when all input pins are high.

    Pass: GPIO_IN returns 0xFFFFFFFF.
    """
    await reset(dut)

    dut.gpio_in.value = 0xFFFFFFFF
    await RisingEdge(dut.clk)
    val = await ahb_read(dut, GPIO_IN)
    assert val == 0xFFFFFFFF, f"expected 0xFFFFFFFF, got 0x{val:08x}"


@cocotb.test()
async def test_walking_ones_out(dut):
    """Walking-ones pattern on GPIO_OUT using SET: each bit individually settable.

    Pass: after setting each bit one at a time, GPIO_OUT == 0xFFFFFFFF.
    """
    await reset(dut)

    for i in range(32):
        await ahb_write(dut, GPIO_OUT_SET, 1 << i)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0xFFFFFFFF, f"expected 0xFFFFFFFF after walking ones, got 0x{val:08x}"


@cocotb.test()
async def test_walking_zeros_out(dut):
    """Walking-zeros pattern on GPIO_OUT using CLR: each bit individually clearable.

    Pass: after clearing each bit one at a time from 0xFFFFFFFF, GPIO_OUT == 0.
    """
    await reset(dut)

    await ahb_write(dut, GPIO_OUT, 0xFFFFFFFF)
    for i in range(32):
        await ahb_write(dut, GPIO_OUT_CLR, 1 << i)

    val = await ahb_read(dut, GPIO_OUT)
    assert val == 0x00000000, f"expected 0x00000000 after walking zeros, got 0x{val:08x}"


# ---------------------------------------------------------------------------
# Standalone runner
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import pathlib
    from cocotb_tools.runner import get_runner

    repo = pathlib.Path(__file__).resolve().parents[2]
    runner = get_runner("verilator")
    runner.build(
        sources=[str(repo / "rtl/soc/peripheral/gpio.sv")],
        hdl_toplevel="gpio",
        build_args=["--trace-fst", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="gpio", test_module="test_gpio")
