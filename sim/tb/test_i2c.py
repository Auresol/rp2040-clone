"""CocoTB testbench for i2c.sv — I2C master peripheral.

I2C is open-drain: scl_oe/sda_oe=1 pulls low, 0 releases (pull-up → high).
The testbench simulates pull-ups and a simple I2C slave that ACKs all bytes
and returns canned data on reads.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer

# Register offsets (byte addresses)
CON      = 0x00
TAR      = 0x04
DATA_CMD = 0x08
SCL_HCNT = 0x0C
SCL_LCNT = 0x10
STATUS   = 0x14
IMSC     = 0x18
RIS      = 0x1C
MIS      = 0x20

# STATUS bits
MST_ACTIVE = 1 << 5
RFF        = 1 << 4
RFNE       = 1 << 3
TFE        = 1 << 2
TFNF       = 1 << 1
NACK_ERR   = 1 << 0

# DATA_CMD field helpers
CMD_WRITE   = 0 << 8
CMD_READ    = 1 << 8
CMD_STOP    = 1 << 9
CMD_RESTART = 1 << 10

# Fast SCL timing for simulation
SCL_H = 4
SCL_L = 4


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


async def wait_idle(dut, timeout=5000):
    """Wait until MST_ACTIVE clears."""
    for _ in range(timeout):
        st = await ahb_read(dut, STATUS)
        if not (st & MST_ACTIVE):
            return st
        await RisingEdge(dut.clk)
    raise TimeoutError("I2C master still active after timeout")


# ---------------------------------------------------------------------------
# Open-drain pull-up simulation + I2C slave model
# ---------------------------------------------------------------------------

class I2CSlave:
    """Simple I2C slave that ACKs all bytes and returns canned read data.

    Simulates open-drain pull-ups: when neither master nor slave drives
    a line low (oe=0), the pin reads high.
    """

    def __init__(self, dut, addr=0x50, read_data=None):
        self.dut = dut
        self.addr = addr
        self.read_data = read_data or [0xDE, 0xAD]
        self.read_idx = 0
        self.written = []          # bytes received from master
        self._slave_sda_low = False
        self._task = None

    def start(self):
        self._task = cocotb.start_soon(self._run())

    def _scl_val(self):
        """Effective SCL: low if master pulls low."""
        return 0 if int(self.dut.scl_oe.value) else 1

    def _sda_master_low(self):
        return int(self.dut.sda_oe.value) == 1

    def _update_pins(self):
        """Drive scl_i/sda_i based on open-drain logic."""
        self.dut.scl_i.value = 0 if int(self.dut.scl_oe.value) else 1
        sda_low = self._sda_master_low() or self._slave_sda_low
        self.dut.sda_i.value = 0 if sda_low else 1

    async def _wait_scl_rise(self):
        """Wait for SCL to go high (master releases it)."""
        while True:
            await RisingEdge(self.dut.clk)
            self._update_pins()
            if self._scl_val() == 1:
                return

    async def _wait_scl_fall(self):
        """Wait for SCL to go low (master pulls it)."""
        while True:
            await RisingEdge(self.dut.clk)
            self._update_pins()
            if self._scl_val() == 0:
                return

    async def _wait_start(self):
        """Detect START: SDA falls while SCL is high."""
        prev_sda = 1
        while True:
            await RisingEdge(self.dut.clk)
            self._update_pins()
            cur_sda = 0 if (self._sda_master_low() or self._slave_sda_low) else 1
            scl = self._scl_val()
            if scl == 1 and prev_sda == 1 and cur_sda == 0:
                return
            prev_sda = cur_sda

    async def _recv_bit(self):
        """Receive one bit: wait for SCL rise, sample SDA, wait for SCL fall."""
        await self._wait_scl_rise()
        bit = 0 if self._sda_master_low() else 1
        await self._wait_scl_fall()
        return bit

    async def _send_bit(self, bit):
        """Send one bit: drive SDA on SCL low, hold through SCL high."""
        self._slave_sda_low = (bit == 0)
        self._update_pins()
        await self._wait_scl_rise()
        await self._wait_scl_fall()
        self._slave_sda_low = False
        self._update_pins()

    async def _recv_byte(self):
        byte = 0
        for i in range(8):
            bit = await self._recv_bit()
            byte = (byte << 1) | bit
        return byte

    async def _send_byte(self, byte):
        for i in range(7, -1, -1):
            await self._send_bit((byte >> i) & 1)

    async def _run(self):
        """Main slave loop: wait for START, handle address, data."""
        while True:
            self._slave_sda_low = False
            self._update_pins()
            await self._wait_start()

            # Receive address byte
            addr_byte = await self._recv_byte()
            target_addr = addr_byte >> 1
            rw = addr_byte & 1  # 0=write, 1=read

            if target_addr != self.addr:
                # NACK — not our address
                await self._send_bit(1)
                continue

            # ACK the address
            await self._send_bit(0)

            if rw == 0:
                # Write mode: receive data bytes
                while True:
                    byte = await self._recv_byte()
                    self.written.append(byte)
                    await self._send_bit(0)  # ACK
            else:
                # Read mode: send data bytes
                self.read_idx = 0
                while True:
                    data = self.read_data[self.read_idx % len(self.read_data)]
                    self.read_idx += 1
                    await self._send_byte(data)
                    # Check master ACK/NACK
                    ack = await self._recv_bit()
                    if ack == 1:
                        # NACK — master done reading
                        break


# ---------------------------------------------------------------------------
# Reset + init
# ---------------------------------------------------------------------------

async def reset_and_init(dut, target=0x50):
    """Start clock, reset, configure I2C master."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst_n.value = 0
    dut.scl_i.value = 1
    dut.sda_i.value = 1
    dut.htrans.value = 0
    dut.hwrite.value = 0
    dut.haddr.value = 0
    dut.hwdata.value = 0
    dut.hsize.value = 2

    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    await ahb_write(dut, SCL_HCNT, SCL_H)
    await ahb_write(dut, SCL_LCNT, SCL_L)
    await ahb_write(dut, TAR, target)
    await ahb_write(dut, CON, 1)  # enable


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_write_single_byte(dut):
    """Write one byte to slave 0x50, verify slave receives it."""
    await reset_and_init(dut, target=0x50)

    slave = I2CSlave(dut, addr=0x50)
    slave.start()

    await ahb_write(dut, DATA_CMD, CMD_WRITE | CMD_STOP | 0xAB)
    await wait_idle(dut)

    # Check no NACK error
    st = await ahb_read(dut, STATUS)
    assert not (st & NACK_ERR), f"unexpected NACK, STATUS=0x{st:02x}"
    assert 0xAB in slave.written, f"slave should have received 0xAB, got {slave.written}"


@cocotb.test()
async def test_write_two_bytes(dut):
    """Write two bytes in one transaction (STOP on second)."""
    await reset_and_init(dut, target=0x50)

    slave = I2CSlave(dut, addr=0x50)
    slave.start()

    await ahb_write(dut, DATA_CMD, CMD_WRITE | 0x12)
    await ahb_write(dut, DATA_CMD, CMD_WRITE | CMD_STOP | 0x34)
    await wait_idle(dut)

    st = await ahb_read(dut, STATUS)
    assert not (st & NACK_ERR), f"unexpected NACK, STATUS=0x{st:02x}"
    assert slave.written == [0x12, 0x34], f"expected [0x12, 0x34], got {slave.written}"


@cocotb.test()
async def test_read_single_byte(dut):
    """Read one byte from slave, verify data arrives in RX FIFO."""
    await reset_and_init(dut, target=0x50)

    slave = I2CSlave(dut, addr=0x50, read_data=[0xDE])
    slave.start()

    await ahb_write(dut, DATA_CMD, CMD_READ | CMD_STOP)
    await wait_idle(dut)

    st = await ahb_read(dut, STATUS)
    assert not (st & NACK_ERR), f"unexpected NACK, STATUS=0x{st:02x}"
    assert st & RFNE, f"RX FIFO should have data, STATUS=0x{st:02x}"

    got = await ahb_read(dut, DATA_CMD)
    assert (got & 0xFF) == 0xDE, f"expected 0xDE, got 0x{got:02x}"


@cocotb.test()
async def test_read_two_bytes(dut):
    """Read two bytes from slave in one transaction."""
    await reset_and_init(dut, target=0x50)

    slave = I2CSlave(dut, addr=0x50, read_data=[0xCA, 0xFE])
    slave.start()

    await ahb_write(dut, DATA_CMD, CMD_READ)
    await ahb_write(dut, DATA_CMD, CMD_READ | CMD_STOP)
    await wait_idle(dut)

    v1 = await ahb_read(dut, DATA_CMD)
    v2 = await ahb_read(dut, DATA_CMD)
    assert (v1 & 0xFF) == 0xCA, f"first: expected 0xCA, got 0x{v1:02x}"
    assert (v2 & 0xFF) == 0xFE, f"second: expected 0xFE, got 0x{v2:02x}"


@cocotb.test()
async def test_nack_wrong_address(dut):
    """Target a slave that doesn't exist — should get NACK error."""
    await reset_and_init(dut, target=0x50)

    # Slave only responds to 0x60, not 0x50
    slave = I2CSlave(dut, addr=0x60)
    slave.start()

    await ahb_write(dut, DATA_CMD, CMD_WRITE | CMD_STOP | 0x00)
    await wait_idle(dut)

    st = await ahb_read(dut, STATUS)
    assert st & NACK_ERR, f"expected NACK error, STATUS=0x{st:02x}"


@cocotb.test()
async def test_write_then_read_restart(dut):
    """Write a register address, restart, read data back (typical sensor pattern)."""
    await reset_and_init(dut, target=0x50)

    slave = I2CSlave(dut, addr=0x50, read_data=[0xBE, 0xEF])
    slave.start()

    # Write phase: send register address 0x01
    await ahb_write(dut, DATA_CMD, CMD_WRITE | 0x01)
    # Restart into read mode
    await ahb_write(dut, DATA_CMD, CMD_READ | CMD_RESTART)
    await ahb_write(dut, DATA_CMD, CMD_READ | CMD_STOP)
    await wait_idle(dut)

    st = await ahb_read(dut, STATUS)
    assert not (st & NACK_ERR), f"unexpected NACK, STATUS=0x{st:02x}"

    # Verify write data reached slave
    assert 0x01 in slave.written, f"slave should have received 0x01, got {slave.written}"

    # Verify read data
    v1 = await ahb_read(dut, DATA_CMD)
    v2 = await ahb_read(dut, DATA_CMD)
    assert (v1 & 0xFF) == 0xBE, f"read1: expected 0xBE, got 0x{v1:02x}"
    assert (v2 & 0xFF) == 0xEF, f"read2: expected 0xEF, got 0x{v2:02x}"


@cocotb.test()
async def test_status_idle(dut):
    """STATUS flags in idle state."""
    await reset_and_init(dut, target=0x50)

    # Need pull-up simulation even with no slave
    slave = I2CSlave(dut, addr=0x50)
    slave.start()
    await ClockCycles(dut.clk, 4)

    st = await ahb_read(dut, STATUS)
    assert not (st & MST_ACTIVE), f"should be idle, STATUS=0x{st:02x}"
    assert st & TFE, f"TX FIFO should be empty, STATUS=0x{st:02x}"
    assert st & TFNF, f"TX FIFO should not be full, STATUS=0x{st:02x}"
    assert not (st & RFNE), f"RX FIFO should be empty, STATUS=0x{st:02x}"


@cocotb.test()
async def test_interrupt_tx_empty(dut):
    """TX-empty interrupt fires when command FIFO drains."""
    await reset_and_init(dut, target=0x50)

    slave = I2CSlave(dut, addr=0x50)
    slave.start()

    # Enable TX empty interrupt (bit 0)
    await ahb_write(dut, IMSC, 0x1)

    # IRQ should be set immediately (FIFO is empty)
    ris = await ahb_read(dut, RIS)
    assert ris & 0x1, f"TX empty RIS should be set, RIS=0x{ris:02x}"

    assert int(dut.i2c_irq.value) == 1, "i2c_irq should be asserted"

    # Mask it off
    await ahb_write(dut, IMSC, 0x0)
    assert int(dut.i2c_irq.value) == 0, "i2c_irq should be deasserted when masked"


# ---------------------------------------------------------------------------
# Standalone runner
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import pathlib
    from cocotb_tools.runner import get_runner

    repo = pathlib.Path(__file__).resolve().parents[2]
    runner = get_runner("verilator")
    runner.build(
        verilog_sources=[str(repo / "rtl/soc/peripheral/i2c.sv")],
        hdl_toplevel="i2c",
        build_args=["--trace", "-Wno-fatal"],
    )
    runner.test(hdl_toplevel="i2c", test_module="test_i2c")
