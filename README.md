# rp2040-clone

A ground-up RISC-V SoC modelled after the RP2040 microcontroller, targeting both FPGA prototyping and 130nm ASIC tapeout.

The CPU is [Hazard3](https://github.com/Wren6991/Hazard3), a 3-stage RV32IMC core. The SoC wraps it with an AHB-Lite fabric, SRAM, GPIO, and a PIO subsystem (two state machines with FIFOs) that mimics the RP2040's programmable I/O.

## Status

| Milestone | Status |
|-----------|--------|
| Single-core SoC (AHB fabric, SRAM, GPIO) | Done |
| PIO peripheral (2 SMs, TX/RX FIFOs) | Done |
| Simulation (Verilator) | Done |
| C firmware test suite | Done |
| FPGA synthesis — Basys3 | Done (~22K LUTs) |
| VLSI — OpenLane + sky130 (DRC/LVS/IR clean) | Done (corner timing broken, fix in progress) |
| DMA controller | Next |

## Structure

```
rtl/
  core/hazard3/          # Hazard3 RV32IMC CPU (submodule)
  soc/
    rvsoc_top.sv         # Top-level SoC
    fabric/
      ahb_decoder.sv     # AHB address decoder
      ahb_arbiter.sv     # AHB multi-master arbiter
    memory/
      sram_top.sv        # SRAM controller
      sram_bank.sv       # Single SRAM bank (BRAM/LUTRAM)
    peripheral/
      gpio.sv            # GPIO peripheral
      pio/
        pio_top.sv       # PIO top (2 state machines)
        pio_sm.sv        # PIO state machine
        pio_fifo.sv      # TX/RX FIFOs (LUTRAM-backed)

fpga/
  fpga_top.sv            # Basys3 FPGA wrapper
  create_project.tcl     # Vivado project script
  basys3.xdc             # Constraints

fw/
  crt0.S                 # Startup / reset handler
  link.ld                # Linker script
  soc.h                  # Register map header
  test_c_*.c             # C firmware tests (hello, PIO, GPIO)

sim/
  main.cpp               # Verilator simulation harness
  sw/                    # Assembly test programs

openlane/
  fix/                   # RTL patches applied for OpenLane compatibility

scripts/
  explore.py             # Parallel OpenLane grid search (area × timing sweep)
```

## Building

```sh
# Run Verilator simulation
make sim

# Synthesise for Basys3 in Vivado (headless)
make fpga
```
