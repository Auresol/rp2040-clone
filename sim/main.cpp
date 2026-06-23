#include "Vrvsoc_top.h"
#include "Vrvsoc_top_rvsoc_top.h"
#include "Vrvsoc_top_sram_top.h"
#include "Vrvsoc_top_sram_bank.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdint>

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
        dut->rvsoc_top->mem->bank->sram[idx++] =
            (uint32_t)buf[0]         |
            ((uint32_t)buf[1] <<  8) |
            ((uint32_t)buf[2] << 16) |
            ((uint32_t)buf[3] << 24);
    }
    fclose(f);
}

int main(int argc, char **argv) {
    const char *firmware = argc > 1 ? argv[1] : "sim/sw/hello.bin";

    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vrvsoc_top *dut = new Vrvsoc_top;

    load_firmware(dut, firmware);

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

    for (int cycle = 0; cycle < MAX_CYCLES; cycle++) {
        dut->clk = 1; dut->eval(); tfp->dump(cycle * 2 + 4);
        dut->clk = 0; dut->eval(); tfp->dump(cycle * 2 + 5);
    }

    uint32_t val = dut->rvsoc_top->mem->bank->sram[0xfff];
    bool pass = (val == SENTINEL_VALUE);
    printf("%s: %s\n", firmware, pass ? "PASS" : "FAIL");
    if (!pass)
        printf("  SRAM[0xfff] = 0x%08x, expected 0x%08x\n", val, SENTINEL_VALUE);

    tfp->close();
    delete tfp;
    delete dut;
    return pass ? 0 : 1;
}
