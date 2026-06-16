#include "Vrvsoc_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdint>

// Address to watch for the sentinel value (must match hello.S)
static const uint32_t SENTINEL_ADDR  = 0x00003ffc;
static const uint32_t SENTINEL_VALUE = 0xdeadbeef;
static const int      MAX_CYCLES     = 100000;

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vrvsoc_top *dut = new Vrvsoc_top;

    VerilatedVcdC *tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open("dump.vcd");

    // Reset
    dut->rst_n = 0;
    dut->clk   = 0;
    for (int i = 0; i < 4; i++) {
        dut->clk = !dut->clk; dut->eval(); tfp->dump(i);
    }
    dut->rst_n = 1;

    bool pass = false;
    for (int cycle = 0; cycle < MAX_CYCLES; cycle++) {
        // Rising edge
        dut->clk = 1;
        dut->eval();
        tfp->dump(cycle * 2 + 4);

        // Check sentinel by peeking at the DUT's SRAM array
        // Verilator exposes sram as a public member when --public is used.
        // For now we check via the data bus address and read data.
        // Simple heuristic: watch d_haddr + d_hrdata one cycle after write.
        // A cleaner approach is done after --public-flat-rw is added to Makefile.

        // Falling edge
        dut->clk = 0;
        dut->eval();
        tfp->dump(cycle * 2 + 5);
    }

    // Peek SRAM directly via Verilator's generated array
    // sram is word-addressed; sentinel is at byte 0x3ffc → word index 0xfff
    uint32_t val = dut->rvsoc_top__DOT__sram[0xfff];
    if (val == SENTINEL_VALUE) {
        printf("PASS: sentinel 0x%08x found at SRAM[0xfff]\n", val);
        pass = true;
    } else {
        printf("FAIL: SRAM[0xfff] = 0x%08x, expected 0x%08x\n", val, SENTINEL_VALUE);
    }

    tfp->close();
    delete tfp;
    delete dut;
    return pass ? 0 : 1;
}
