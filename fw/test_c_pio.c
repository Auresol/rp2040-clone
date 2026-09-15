#include "soc.h"

// PIO loopback test — mirrors test_pio.S but written in C.
//
// Programs PIO0 SM0 with a 3-instruction loop:
//   addr 0: PULL blocking   (TX FIFO → OSR)
//   addr 1: MOV ISR, OSR   (copy OSR to ISR)
//   addr 2: PUSH blocking   (ISR → RX FIFO, wraps back to addr 0)
//
// Pushes 3 known words into TXF0, reads them back from RXF0, checks order.

#define PULL_BLOCKING   0x8080u  // opcode=100, NOBLOCK=0, IFEMPTY=0
#define MOV_ISR_OSR     0xA0C7u  // opcode=101, dst=ISR, src=OSR
#define PUSH_BLOCKING   0x8000u  // opcode=100, NOBLOCK=0, IFFULL=0

static void tx_wait_push(uint32_t base, int sm, uint32_t val) {
    while (PIO_FSTAT(base) & PIO_FSTAT_TXFULL(sm));
    PIO_TXF(base, sm) = val;
}

static uint32_t rx_wait_pop(uint32_t base, int sm) {
    while (PIO_FSTAT(base) & PIO_FSTAT_RXEMPTY(sm));
    return PIO_RXF(base, sm);
}

void main(void) {
    const uint32_t base = PIO0_BASE;
    const int sm = 0;

    // Write instruction memory
    PIO_INSTR_MEM(base, 0) = PULL_BLOCKING;
    PIO_INSTR_MEM(base, 1) = MOV_ISR_OSR;
    PIO_INSTR_MEM(base, 2) = PUSH_BLOCKING;

    // Configure SM0
    PIO_SM_CLKDIV(base, sm)    = PIO_CLKDIV(1, 0);
    PIO_SM_EXECCTRL(base, sm)  = PIO_EXECCTRL_WRAP_TOP(2) | PIO_EXECCTRL_WRAP_BOTTOM(0);
    PIO_SM_SHIFTCTRL(base, sm) = 0;
    PIO_SM_PINCTRL(base, sm)   = 0;

    // Enable SM0 — immediately stalls on PULL, waiting for TX data
    PIO_CTRL(base) = PIO_CTRL_SM_ENABLE(sm);

    // Push 3 words
    tx_wait_push(base, sm, 0xDEAD1234u);
    tx_wait_push(base, sm, 0xCAFEBABEu);
    tx_wait_push(base, sm, 0x12345678u);

    // Pop and verify (must come back in the same order)
    if (rx_wait_pop(base, sm) != 0xDEAD1234u) goto fail;
    if (rx_wait_pop(base, sm) != 0xCAFEBABEu) goto fail;
    if (rx_wait_pop(base, sm) != 0x12345678u) goto fail;

    TEST_PASS();
    while (1);

fail:
    while (1);
}
