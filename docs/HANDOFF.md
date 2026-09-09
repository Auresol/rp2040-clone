# Project Handoff

## What This Is

A ground-up RISC-V SoC modelled after the RP2040 microcontroller. The CPU is
[Hazard3](https://github.com/Wren6991/Hazard3), a 3-stage RV32IMC core (the
same core used in the RP2350). The SoC wraps it with an AHB-Lite bus fabric,
64 KB SRAM, a GPIO peripheral, and a PIO subsystem that replicates the RP2040's
programmable I/O — two independent state machines with TX/RX FIFOs, all 9 PIO
instructions, side-set, autopush/pull, FJOIN, IRQ, and wrap.

The FPGA target is the **AMD Kria KR260** (XCK26 UltraScale+ MPSoC, ~117K
LUTs). The Zynq PS provides the clock, reset, and USB/serial access; the PL
runs the SoC. The RPi 40-pin header on the KR260 is the GPIO output (3.3V,
bank 45).

---

## Repository Layout

```
rtl/
  core/hazard3/          # Hazard3 CPU (git submodule)
  soc/
    rvsoc_top.sv         # SoC top — CPU, decoders, SRAM, GPIO, PIO0, PIO1
    fabric/
      ahb_decoder.sv     # 2-slave AHB address decoder
      ahb_decoder_4s.sv  # 4-slave variant (data port)
      ahb_arbiter.sv     # 2-master round-robin arbiter (see Known Issues)
    memory/
      sram_top.sv        # Dual-port SRAM controller (I+D ports)
      sram_bank.sv       # Single SRAM bank (BRAM/LUTRAM target)
    peripheral/
      gpio.sv
      pio/
        pio_top.sv       # 2 state machines + shared instruction memory
        pio_sm.sv        # State machine execute stage
        pio_fifo.sv      # TX/RX FIFOs (LUTRAM-backed, FJOIN support)

fpga/
  kr260_top.sv           # Synthesis top — wires PS block design to SoC wrapper
  fpga_top_kr260.sv      # SoC wrapper: reset sync, GPIO/PIO output mux
  ps_bd_wrapper.sv       # Auto-generated stub (Vivado block design)
  create_project_kr260.tcl  # Vivado project script (headless)
  kr260.xdc              # Pin constraints (RPi header → rpi_gpio[7:0])
  kr260.bif              # bootgen image descriptor

fw/
  crt0.S                 # Reset handler, stack setup, optional core-1 wake
  link.ld                # Linker script: firmware at 0x0000_0000, stack top 0x3FF0
  soc.h                  # All peripheral base addresses and register macros
  blink.c                # GPIO software blink (confirmed on KR260)
  multi_blink.c          # Ripple-counter multi-pin blink (confirmed on KR260)
  pio_blink.c            # PIO timer → CPU toggles GPIO ~1 Hz (confirmed on KR260)
  pio_pwm.c              # PIO autonomous PWM, CPU varies duty cycle (built, not yet loaded)
  test_c_*.c             # Simulation test suite

sim/
  main.cpp               # Verilator harness — loads .bin, exits on sentinel write
  sw/                    # Assembly + C firmware binaries for simulation
  sw/waveform/           # Per-test VCD output

scripts/
  bin2mem.py             # .bin → $readmemh .mem (for SRAM init in bitstream)
  bin2coe.py             # .bin → Xilinx .coe (alternative BRAM init format)
```

---

## Address Map

| Range | Peripheral |
|---|---|
| `0x0000_0000 – 0x0000_FFFF` | SRAM (64 KB) |
| `0x4000_0000 – 0x4000_FFFF` | GPIO (32-bit output register at base) |
| `0x5020_0000 – 0x5020_FFFF` | PIO0 |
| `0x5030_0000 – 0x5030_FFFF` | PIO1 |

PIO register layout is identical to the RP2040 datasheet. See `fw/soc.h` for
all macros.

---

## Architecture Decision Records

### ADR-1 — CPU: Hazard3 over Ibex

**Decision:** Use Hazard3 as the CPU core.

**Rationale:** Hazard3 is purpose-built as a Cortex-M0+ replacement and is
smaller than Ibex (which targets M3). It is used in the RP2350, making it a
direct architectural peer. Ibex has a larger footprint and more complex pipeline
than needed.

---

### ADR-2 — Bus fabric: AHB-Lite

**Decision:** Use AHB-Lite as the internal bus.

**Rationale:** Hazard3 exposes native AHB-Lite ports (separate instruction and
data). Using AHB-Lite avoids any bridge logic between the CPU and memory, keeps
the fabric simple, and is compatible with the RP2040's own internal bus.

---

### ADR-3 — Single-core on working branch

**Decision:** The active branch (`feat/single-core`) removes the arbiter and
wires CPU0 directly to the decoders.

**Rationale:** The round-robin arbiter on `main` has a timing bug where it
asserts grants for two cycles per core instead of one, causing core 1 to read
stale or misaligned data. Rather than block all other work on this, the arbiter
was removed on a dedicated branch. All simulation tests pass here. The arbiter
bug is documented in `rtl/soc/fabric/ahb_arbiter.sv` and must be fixed before
restoring dual-core support.

---

### ADR-4 — Firmware baked into bitstream

**Decision:** Firmware is loaded into SRAM at synthesis time via `$readmemh`
and a `.mem` file, not over a runtime bus.

**Rationale:** The Zynq PS is not yet wired to the PL SRAM via AXI. Baking
firmware into the bitstream lets the SoC run standalone immediately after
`fpgautil` loads the bitstream, with no runtime loader. The flow is:
`scripts/bin2mem.py` → `fpga/firmware.mem` → `sram_bank.sv` reads it at init.
A runtime AXI-to-AHB bridge path is planned for later (avoids bitstream rebuilds
on every firmware change).

---

### ADR-5 — PIO GPIO mux in FPGA wrapper

**Decision:** The FPGA wrapper (`fpga_top_kr260.sv`) implements a per-bit output
mux: PIO output-enable (`pio_gpio_oe`) takes priority over the GPIO peripheral.

**Rationale:** The GPIO peripheral and PIO both drive the same physical RPi
header pins. A per-bit OE mux lets PIO state machines claim individual pins with
`SET PINDIRS` while leaving remaining pins under CPU software control. This is
equivalent to how the RP2040 handles pin ownership without requiring software
arbitration.

---

### ADR-6 — Clock source: PS FCLK0, not a PL MMCM

**Decision:** The KR260 SoC clock comes from `FCLK0` (PS clock output),
configured at 100 MHz in the Vivado block design.

**Rationale:** Initial bringup used an MMCM driven from a PL oscillator on pin
H4, which is not connected on the KR260 (that pin is from the KD240 schematic).
Switching to FCLK0 eliminated a USB over-current fault that appeared when the
bitstream loaded with the wrong clock source. The PS also holds the PL in reset
(`FCLK_RESET0_N`) until it has booted, giving a clean power-on sequence.

---

## Current State (as of 2026-08-23)

### Simulation

All tests pass on `feat/single-core` via Verilator:

| Test | Type | Status |
|---|---|---|
| hello | assembly | PASS |
| test_alu | assembly | PASS |
| test_mem | assembly | PASS |
| test_branch | assembly | PASS |
| test_gpio | assembly | PASS |
| test_pio | assembly | PASS |
| gpio_on | assembly | PASS |
| test_c_hello | C | PASS |
| test_c_pio | C | PASS |
| test_c_pio_gpio | C | PASS |
| blink | C | PASS |
| multi_blink | C | PASS |
| pio_blink | C | PASS |
| pio_pwm | C | PASS |

### FPGA — KR260 synthesis results

Synthesised and implemented with Vivado 2025.2, 100 MHz target:

| Resource | Used | Total | % |
|---|---|---|---|
| CLB LUTs | 22,466 | 117,120 | 19.2% |
| Registers | 5,420 | 234,240 | 2.3% |
| RAMB36 | 32 | 144 | 22.2% |
| LUTRAM | 360 | 57,600 | 0.6% |

Timing: setup WNS = +1.231 ns, hold WHS = +0.028 ns. Zero failing endpoints.

### FPGA — KR260 hardware bringup

Board OS: Ubuntu Server 24.04 LTS. Board clock: PS FCLK0 at 100 MHz (confirmed
via `/sys/kernel/debug/clk/pl0_ref/clk_rate`).

| Firmware | Result |
|---|---|
| `gpio_on.S` | LED on — CPU executing, GPIO write reaching RPi header |
| `blink.c` | Confirmed blinking on hardware |
| `multi_blink.c` | Confirmed ripple-counter pattern on hardware |
| `pio_blink.c` | Confirmed ~1 Hz blink via PIO timer |
| `pio_pwm.c` | Built and simulated — **not yet loaded to hardware** |

### Known Issues

**Arbiter bug (`main` branch):** `ahb_arbiter.sv` holds the grant for two cycles
per master instead of one. Core 1 receives misaligned read data. Tracked on
`main`; `feat/single-core` works around it by removing the arbiter.

**SRAM write-first semantics:** `sram_bank.sv` uses blocking assignment for the
write path to ensure write-first (read-during-write returns new data). This is
intentional. Changing to non-blocking breaks back-to-back `sw`/`lw` to the same
address.

**PIO clkdiv width:** `pio_sm.sv` uses an 8-bit clock divider on FPGA (narrowed
from the 16-bit RP2040 spec) to avoid wide counter inference. Restore to 16-bit
before any ASIC work.

**PIO INPUT_SYNC_BYPASS stub:** `pio_top.sv` accepts writes to `INPUT_SYNC_BYPASS`
(offset `0x038`) but ignores them. GPIO inputs are passed directly to the state
machines without the RP2040's 2-stage flip-flop synchronizer. Asynchronous
inputs may cause metastability on real silicon.

**PIO FDEBUG TXOVER / RXUNDER never set:** The `FDEBUG` register tracks four
sticky error flags. TXSTALL and RXSTALL are set correctly by the state machine.
TXOVER (CPU wrote to a full TX FIFO) and RXUNDER (CPU read from an empty RX
FIFO) are wired up in `pio_top.sv` but the SM never asserts them — silent
data loss occurs with no flag. Software cannot rely on these two bits for
overflow/underflow detection.

---

## Build and Deploy

### Run simulation (all tests)

```sh
# On remote machine (faster build):
make remote-test
```

### Build and load a bitstream to KR260

```sh
# 1. Build .mem from firmware binary
make remote-fpga-kr260 FW=sim/sw/pio_blink.bin

# 2. Convert .bit → .bit.bin
make remote-bitstream-kr260

# 3. Copy to board and load
scp fpga/bitstream/fpga_top.bit.bin ubuntu@<board-ip>:/lib/firmware/
ssh ubuntu@<board-ip> 'sudo fpgautil -b ~/fpga_top.bit.bin -f Full'
```

### Firmware compilation

Assembly tests in `sim/sw/` — compiled by make targets.
C firmware in `fw/` — uses `crt0.S` + `link.ld`. Build with:

```sh
make sim/sw/blink.bin
```

Toolchain: `riscv64-none-elf-gcc`, flags: `-march=rv32imc_zicsr -mabi=ilp32`.

---

## Next Work

**DMA controller** — no design started. Should attach to the AHB data fabric as
a new slave (with read/write master capability), controlled via MMIO registers.
Suggested address: `0x5000_0000`.

**pio_pwm.c hardware test** — load current bitstream with this firmware and
verify breathing LED pattern on RPi header.

**Arbiter fix** — diagnose the two-cycle grant hold in `ahb_arbiter.sv` and
restore dual-core support on `main`.
