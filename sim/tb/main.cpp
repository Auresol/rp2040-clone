#include "Vrxpsm32.h"
#include "Vrxpsm32_rxpsm32.h"
#include "Vrxpsm32_sram_top.h"
#include "Vrxpsm32_sram_bank__D1000.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdio>
#include <cstdint>

static const uint32_t SENTINEL_ADDR  = 0x00003ffc;
static const uint32_t SENTINEL_VALUE = 0xdeadbeef;
static const int      MAX_CYCLES     = 2000;

static const int BANK_DEPTH = 4096;  // words per bank

static void write_sram(Vrxpsm32 *dut, int idx, uint32_t val) {
    int bank = idx / BANK_DEPTH;
    int off  = idx % BANK_DEPTH;
    switch (bank) {
        case 0: dut->rxpsm32->mem->gen_banks__BRA__0__KET____DOT__bank->sram[off] = val; break;
        case 1: dut->rxpsm32->mem->gen_banks__BRA__1__KET____DOT__bank->sram[off] = val; break;
    }
}

static uint32_t read_sram(Vrxpsm32 *dut, int idx) {
    int bank = idx / BANK_DEPTH;
    int off  = idx % BANK_DEPTH;
    switch (bank) {
        case 0: return dut->rxpsm32->mem->gen_banks__BRA__0__KET____DOT__bank->sram[off];
        case 1: return dut->rxpsm32->mem->gen_banks__BRA__1__KET____DOT__bank->sram[off];
        default: return 0;
    }
}

static void load_firmware(Vrxpsm32 *dut, const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "FATAL: cannot open firmware '%s'\n", path);
        exit(1);
    }
    uint8_t buf[4];
    int idx = 0;
    while (fread(buf, 1, 4, f) == 4) {
        uint32_t word = (uint32_t)buf[0]         |
                        ((uint32_t)buf[1] <<  8) |
                        ((uint32_t)buf[2] << 16) |
                        ((uint32_t)buf[3] << 24);
        write_sram(dut, idx++, word);
    }
    fclose(f);
}

int main(int argc, char **argv) {
    const char *firmware = argc > 1 ? argv[1] : "sim/sw/hello.bin";
    const char *vcd_path = argc > 2 ? argv[2] : "dump.vcd";

    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    Vrxpsm32 *dut = new Vrxpsm32;

    load_firmware(dut, firmware);

    VerilatedVcdC *tfp = new VerilatedVcdC;
    dut->trace(tfp, 99);
    tfp->open(vcd_path);

    // Tie off PIO GPIO inputs (no external GPIO driven in simulation)
    dut->pio_gpio_in = 0;

    // UART RX idle-high (no incoming data in simulation)
    dut->uart_rx = 1;

    // JTAG idle (no debugger attached in simulation)
    dut->tck    = 0;
    dut->trst_n = 1;
    dut->tms    = 1;  // TMS=1 keeps TAP in Test-Logic-Reset
    dut->tdi    = 0;

    // SPI flash — no flash attached in simulation
    dut->spi_miso = 0;

    // SPI0 — no slave attached in simulation
    dut->spi0_miso = 0;

    // Reset
    dut->rst_n = 0;
    dut->clk   = 0;
    for (int i = 0; i < 4; i++) {
        dut->clk = !dut->clk; dut->eval(); tfp->dump(i);
    }
    dut->rst_n = 1;

    for (int cycle = 0; cycle < MAX_CYCLES; cycle++) {
        dut->pio_gpio_in = (uint32_t)cycle;  // fast counter — new value every clock
        dut->clk = 1; dut->eval(); tfp->dump(cycle * 2 + 4);
        dut->clk = 0; dut->eval(); tfp->dump(cycle * 2 + 5);
    }

    uint32_t val = read_sram(dut, 0xfff);
    bool pass = (val == SENTINEL_VALUE);
    printf("%s: %s\n", firmware, pass ? "PASS" : "FAIL");
    if (!pass)
        printf("  SRAM[0xfff] = 0x%08x, expected 0x%08x\n", val, SENTINEL_VALUE);

    tfp->close();
    delete tfp;
    delete dut;
    return pass ? 0 : 1;
}
