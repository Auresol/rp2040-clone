#include "soc.h"

// PIO GPIO input streaming test.
//
// The simulation drives pio_gpio_in with an incrementing counter every clock
// cycle — faster than the CPU can drain the FIFO.
//
// PIO0 SM0 program (2-instruction loop):
//   addr 0: IN PINS, 32    — sample all 32 GPIO bits into ISR each cycle
//   addr 1: PUSH NOBLOCK   — push to RX FIFO; silently drop if full
//
// The CPU reads two values with a deliberate busy-wait between them to let
// the FIFO fill and overflow. Gaps between consecutive reads confirm drops.
// If values are consecutive (gap == 2) no overflow happened → FAIL.

#define IN_PINS_32    0x4000u  // IN PINS, 32
#define PUSH_NOBLOCK  0x8020u  // PUSH NOBLOCK

// Burn ~N cycles doing nothing (volatile prevents the compiler from deleting it).
static void busy_wait(volatile int n) {
    while (n-- > 0);
}

static uint32_t rx_wait_pop(uint32_t base, int sm) {
    while (PIO_FSTAT(base) & PIO_FSTAT_RXEMPTY(sm));
    return PIO_RXF(base, sm);
}

void main(void) {
    const uint32_t base = PIO0_BASE;
    const int sm = 0;

    // Write instruction memory
    PIO_INSTR_MEM(base, 0) = IN_PINS_32;
    PIO_INSTR_MEM(base, 1) = PUSH_NOBLOCK;

    // Configure SM0
    PIO_SM_CLKDIV(base, sm)    = PIO_CLKDIV(1, 0);
    // WRAP_TOP=1, WRAP_BOTTOM=0: loop between addr 0 and addr 1
    PIO_SM_EXECCTRL(base, sm)  = PIO_EXECCTRL_WRAP_TOP(1) | PIO_EXECCTRL_WRAP_BOTTOM(0);
    PIO_SM_SHIFTCTRL(base, sm) = 0;
    PIO_SM_PINCTRL(base, sm)   = 0;

    // Enable SM0 — immediately starts sampling GPIO
    PIO_CTRL(base) = PIO_CTRL_SM_ENABLE(sm);

    // Read first value
    uint32_t first = rx_wait_pop(base, sm);

    // Wait long enough for the FIFO (depth 4) to fill and overflow multiple times.
    // Each PIO loop takes 2 cycles; FIFO fills in ~8 cycles. 100 iterations >> 8.
    busy_wait(100);

    // Read second value
    uint32_t second = rx_wait_pop(base, sm);

    // Gap > 2 means at least one sample was dropped between the two reads.
    // (Gap of exactly 2 would mean perfectly consecutive — no drops at all.)
    if (second <= first)       goto fail;  // counter wrapped or went backwards
    if (second - first <= 2)   goto fail;  // no drops detected

    TEST_PASS();
    while (1);

fail:
    while (1);
}
