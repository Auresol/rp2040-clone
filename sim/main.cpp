#include "Vrvsoc_top.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdint>

// Address to watch for the sentinel value (must match hello.S)
static const uint32_t SENTINEL_ADDR  = 0x00003ffc;
static const uint32_t SENTINEL_VALUE = 0xdeadbeef;
static const int      MAX_CYCLES     = 100000;

static void load_firmware(Vrvsoc_top *dut, const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "FATAL: cannot open firmware '%s'\n", path);
        exit(1);
    }
    uint8_t buf[4];
    int idx = 0;
    while (fread(buf, 1, 4, f) == 4) {
        // Little-endian byte packing — explicit, no format ambiguity
        dut->rvsoc_top__DOT__sram[idx++] =
            (uint32_t)buf[0]        |
            ((uint32_t)buf[1] << 8) |
            ((uint32_t)buf[2] << 16)|
            ((uint32_t)buf[3] << 24);
    }
    fclose(f);
    printf("Loaded %d words from '%s'\n", idx, path);
    printf("  sram[0] = 0x%08x (expect 0xDEADC537 for lui a0,0xdeadc)\n",
           dut->rvsoc_top__DOT__sram[0]);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vrvsoc_top *dut = new Vrvsoc_top;

    // Load firmware before simulation starts (SRAM is zeroed by constructor)
    load_firmware(dut, "sim/sw/hello.bin");

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
