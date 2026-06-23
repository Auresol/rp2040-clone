// Unit test for ahb_decoder
// Checks: address routing (sel mux), response routing (sel_r mux),
// and that non-selected slaves see htrans=IDLE.

#include "Vahb_decoder.h"
#include "verilated.h"
#include <cstdio>

static Vahb_decoder *dut;
static int passes = 0, failures = 0;

static void tick() {
    dut->clk = 1; dut->eval();
    dut->clk = 0; dut->eval();
}

static void reset() {
    dut->rst_n    = 0;
    dut->clk      = 0;
    dut->m_htrans = 0; dut->m_haddr = 0; dut->m_hwrite = 0;
    dut->m_hsize  = 2; dut->m_hwdata = 0;
    dut->s0_hrdata = 0; dut->s0_hready = 1; dut->s0_hresp = 0;
    dut->s1_hrdata = 0; dut->s1_hready = 1; dut->s1_hresp = 0;
    tick(); tick();
    dut->rst_n = 1;
    dut->eval();
}

static void check(const char *name, bool pass) {
    printf("  [%s] %s\n", pass ? "PASS" : "FAIL", name);
    if (pass) passes++; else failures++;
}

static const uint8_t IDLE   = 0b00;
static const uint8_t NONSEQ = 0b10;

// -----------------------------------------------------------------------
// Test 1: SRAM address → slave 0 gets transaction, slave 1 idle
// -----------------------------------------------------------------------
static void test_sram_routing() {
    printf("\nTest 1: SRAM address routing\n");
    reset();

    dut->m_htrans = NONSEQ;
    dut->m_haddr  = 0x00000100;  // SRAM range
    dut->eval();

    check("s0_htrans = NONSEQ (SRAM selected)", dut->s0_htrans == NONSEQ);
    check("s1_htrans = IDLE (GPIO not selected)", dut->s1_htrans == IDLE);
    check("s0_haddr forwarded", dut->s0_haddr == 0x00000100u);

    tick();
    dut->m_htrans = IDLE;
    tick();
}

// -----------------------------------------------------------------------
// Test 2: GPIO address → slave 1 gets transaction, slave 0 idle
// -----------------------------------------------------------------------
static void test_gpio_routing() {
    printf("\nTest 2: GPIO address routing\n");
    reset();

    dut->m_htrans = NONSEQ;
    dut->m_haddr  = 0x40000000;  // GPIO range
    dut->eval();

    check("s1_htrans = NONSEQ (GPIO selected)", dut->s1_htrans == NONSEQ);
    check("s0_htrans = IDLE (SRAM not selected)", dut->s0_htrans == IDLE);
    check("s1_haddr forwarded", dut->s1_haddr == 0x40000000u);

    tick();
    dut->m_htrans = IDLE;
    tick();
}

// -----------------------------------------------------------------------
// Test 3: response comes from SRAM slave (sel_r)
// -----------------------------------------------------------------------
static void test_sram_response() {
    printf("\nTest 3: SRAM response (sel_r)\n");
    reset();

    // Address phase: select SRAM
    dut->m_htrans  = NONSEQ;
    dut->m_haddr   = 0x00000100;
    dut->s0_hrdata = 0xCAFEBABE;
    dut->s1_hrdata = 0xDEADDEAD;  // should NOT appear
    dut->eval();

    tick();  // posedge: sel_r = SRAM

    // Data phase: master reads hrdata — should come from s0
    dut->m_htrans = IDLE;
    dut->eval();
    check("m_hrdata = s0_hrdata (SRAM)",    dut->m_hrdata == 0xCAFEBABEu);
    check("m_hready = s0_hready",           dut->m_hready == dut->s0_hready);

    tick();
}

// -----------------------------------------------------------------------
// Test 4: response comes from GPIO slave (sel_r)
// -----------------------------------------------------------------------
static void test_gpio_response() {
    printf("\nTest 4: GPIO response (sel_r)\n");
    reset();

    // Address phase: select GPIO
    dut->m_htrans  = NONSEQ;
    dut->m_haddr   = 0x40000000;
    dut->s0_hrdata = 0xDEADDEAD;  // should NOT appear
    dut->s1_hrdata = 0x12345678;
    dut->eval();

    tick();  // posedge: sel_r = GPIO

    dut->m_htrans = IDLE;
    dut->eval();
    check("m_hrdata = s1_hrdata (GPIO)",    dut->m_hrdata == 0x12345678u);
    check("m_hready = s1_hready",           dut->m_hready == dut->s1_hready);

    tick();
}

// -----------------------------------------------------------------------
// Test 5: back-to-back SRAM → GPIO — sel_r tracks correctly
// -----------------------------------------------------------------------
static void test_switch_slaves() {
    printf("\nTest 5: back-to-back SRAM then GPIO\n");
    reset();

    // Transaction 1: SRAM
    dut->m_htrans  = NONSEQ;
    dut->m_haddr   = 0x00000100;
    dut->s0_hrdata = 0xAAAAAAAA;
    dut->s1_hrdata = 0xBBBBBBBB;
    dut->eval();

    check("tx1 addr: s0_htrans=NONSEQ", dut->s0_htrans == NONSEQ);
    check("tx1 addr: s1_htrans=IDLE",   dut->s1_htrans == IDLE);

    tick();  // sel_r = SRAM

    // Transaction 2 address phase starts, while tx1 data phase completes
    dut->m_haddr  = 0x40000000;  // GPIO
    dut->m_htrans = NONSEQ;
    dut->eval();

    // sel_r still SRAM (tx1 data phase)
    check("tx1 data: m_hrdata from SRAM", dut->m_hrdata == 0xAAAAAAAAu);
    // sel is now GPIO (tx2 address phase)
    check("tx2 addr: s1_htrans=NONSEQ",  dut->s1_htrans == NONSEQ);
    check("tx2 addr: s0_htrans=IDLE",    dut->s0_htrans == IDLE);

    tick();  // sel_r = GPIO

    dut->m_htrans = IDLE;
    dut->eval();
    check("tx2 data: m_hrdata from GPIO", dut->m_hrdata == 0xBBBBBBBBu);

    tick();
}

// -----------------------------------------------------------------------

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vahb_decoder;

    test_sram_routing();
    test_gpio_routing();
    test_sram_response();
    test_gpio_response();
    test_switch_slaves();

    printf("\n%d/%d tests passed\n", passes, passes + failures);
    delete dut;
    return failures ? 1 : 0;
}
