// Unit test for ahb_arbiter
// Drives the arbiter directly without a full SoC, checking grant mux,
// priority, handoff, back-to-back transactions, and slave stall behaviour.

#include "Vahb_arbiter.h"
#include "verilated.h"
#include <cstdio>

static Vahb_arbiter *dut;
static int passes = 0, failures = 0;

static void tick() {
    dut->clk = 1; dut->eval();
    dut->clk = 0; dut->eval();
}

static void reset() {
    dut->rst_n       = 0;
    dut->clk         = 0;
    dut->m0_htrans   = 0; dut->m0_haddr = 0; dut->m0_hwrite = 0;
    dut->m0_hsize    = 2; dut->m0_hburst = 0; dut->m0_hprot = 0;
    dut->m0_hmastlock = 0; dut->m0_hmaster = 0; dut->m0_hwdata = 0;
    dut->m1_htrans   = 0; dut->m1_haddr = 0; dut->m1_hwrite = 0;
    dut->m1_hsize    = 2; dut->m1_hburst = 0; dut->m1_hprot = 0;
    dut->m1_hmastlock = 0; dut->m1_hmaster = 0; dut->m1_hwdata = 0;
    dut->s_hrdata    = 0; dut->s_hready = 1; dut->s_hresp = 0;
    tick(); tick();
    dut->rst_n = 1;
    dut->eval();
}

static void check(const char *name, bool pass) {
    printf("  [%s] %s\n", pass ? "PASS" : "FAIL", name);
    if (pass) passes++; else failures++;
}

// htrans encoding
static const uint8_t IDLE   = 0b00;
static const uint8_t NONSEQ = 0b10;

// -----------------------------------------------------------------------
// Test 1: only M0 requests
// -----------------------------------------------------------------------
static void test_m0_only() {
    printf("\nTest 1: M0 only\n");
    reset();

    dut->m0_htrans = NONSEQ;
    dut->m0_haddr  = 0x100;
    dut->eval();

    // Combinational: M0 granted immediately (arb_grant=0 since busy=0 and m0 requests)
    check("s_htrans forwarded",       dut->s_htrans == NONSEQ);
    check("s_haddr = M0 addr",        dut->s_haddr  == 0x100u);
    check("m0_hready = s_hready",     dut->m0_hready == dut->s_hready);
    check("m1_hready = 0 (stalled)",  dut->m1_hready == 0);

    // Data phase
    tick();                  // posedge: busy=1, grant=M0
    dut->m0_htrans = IDLE;   // M0 done after this transaction
    dut->eval();
    check("m0_hready = 1 (data phase)", dut->m0_hready == 1);

    tick();                  // posedge: busy=0
}

// -----------------------------------------------------------------------
// Test 2: only M1 requests
// -----------------------------------------------------------------------
static void test_m1_only() {
    printf("\nTest 2: M1 only\n");
    reset();

    dut->m1_htrans = NONSEQ;
    dut->m1_haddr  = 0x200;
    dut->eval();

    check("s_htrans forwarded",       dut->s_htrans == NONSEQ);
    check("s_haddr = M1 addr",        dut->s_haddr  == 0x200u);
    check("m1_hready = s_hready",     dut->m1_hready == dut->s_hready);
    check("m0_hready = 0 (stalled)",  dut->m0_hready == 0);

    tick();
    dut->m1_htrans = IDLE;
    dut->eval();
    check("m1_hready = 1 (data phase)", dut->m1_hready == 1);
    tick();
}

// -----------------------------------------------------------------------
// Test 3: simultaneous request — M0 has priority, then M1 gets handoff
// -----------------------------------------------------------------------
static void test_simultaneous() {
    printf("\nTest 3: simultaneous — M0 priority, then handoff to M1\n");
    reset();

    dut->m0_htrans = NONSEQ; dut->m0_haddr = 0x100;
    dut->m1_htrans = NONSEQ; dut->m1_haddr = 0x200;
    dut->eval();

    check("s_haddr = M0 (priority)",   dut->s_haddr == 0x100u);
    check("m0_hready = s_hready",      dut->m0_hready == dut->s_hready);
    check("m1_hready = 0 (stalled)",   dut->m1_hready == 0);

    // M0 finishes, M1 is still waiting
    tick();                  // posedge: busy=1, grant=M0
    dut->m0_htrans = IDLE;   // M0 has no more transactions
    dut->eval();

    check("m0_hready = 1 (M0 data phase)", dut->m0_hready == 1);
    check("m1_hready = 0 (still stalled)", dut->m1_hready == 0);

    tick();                  // posedge: busy=0 (cur_req=m0_req=0)
    dut->eval();             // now arb_grant picks M1 combinationally

    check("s_haddr = M1 (handoff)",   dut->s_haddr == 0x200u);
    check("m1_hready = 1 (granted)",  dut->m1_hready == 1);
    check("m0_hready = 0 (stalled)",  dut->m0_hready == 0);

    tick();
    dut->m1_htrans = IDLE;
    dut->eval();
    tick();
}

// -----------------------------------------------------------------------
// Test 4: back-to-back transactions from M0 — busy must stay high
// -----------------------------------------------------------------------
static void test_back_to_back() {
    printf("\nTest 4: back-to-back from M0\n");
    reset();

    // First transaction
    dut->m0_htrans = NONSEQ; dut->m0_haddr = 0x100;
    dut->eval();
    tick();                  // posedge: busy=1, grant=M0

    // Second transaction starts immediately (back-to-back)
    dut->m0_haddr = 0x104;
    dut->m0_htrans = NONSEQ;
    dut->eval();

    // In data phase of first, address phase of second is already live
    check("m0_hready = 1 (completing first)",      dut->m0_hready == 1);
    check("s_haddr = 0x104 (second addr forwarded)", dut->s_haddr == 0x104u);

    tick();                  // posedge: s_hready=1, cur_req=m0_req=1 → busy stays 1
    dut->m0_htrans = IDLE;
    dut->eval();
    check("m0_hready = 1 (completing second)", dut->m0_hready == 1);

    tick();                  // posedge: busy=0
}

// -----------------------------------------------------------------------
// Test 5: slave stall — master must wait when s_hready=0
// -----------------------------------------------------------------------
static void test_slave_stall() {
    printf("\nTest 5: slave stall\n");
    reset();

    dut->m0_htrans = NONSEQ; dut->m0_haddr = 0x100;
    dut->s_hready  = 0;      // slave not ready
    dut->eval();

    check("m0_hready = 0 when slave stalls", dut->m0_hready == 0);

    tick();                  // posedge: busy=1, s_hready=0
    dut->eval();
    check("m0_hready still 0 (slave stalling)", dut->m0_hready == 0);

    dut->s_hready = 1;       // slave now ready
    dut->eval();
    check("m0_hready = 1 when slave ready",  dut->m0_hready == 1);

    tick();
    dut->m0_htrans = IDLE;
    tick();
}

// -----------------------------------------------------------------------

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vahb_arbiter;

    test_m0_only();
    test_m1_only();
    test_simultaneous();
    test_back_to_back();
    test_slave_stall();

    printf("\n%d/%d tests passed\n", passes, passes + failures);
    delete dut;
    return failures ? 1 : 0;
}
