#include "soc.h"

// PIO LED blink — PIO0 SM0 acts as a hardware timer; CPU toggles GPIO on each tick.
//
// PIO program (5 instructions, wraps addr 4 → addr 2):
//   addr 0: PULL NOBLOCK    — one-shot: load delay count from TX FIFO into OSR
//   addr 1: MOV Y, OSR      — one-shot: save count in Y (permanent copy)
//   addr 2: MOV X, Y        — reload X from Y each period    [wrap_bottom]
//   addr 3: JMP X--, 3      — count down (1 cycle per iteration)
//   addr 4: PUSH NOBLOCK    — tick: push to RX FIFO; drop if full  [wrap_top]
//
// Why Y is needed: JMP X-- always post-decrements, so after counting down from
// BLINK_COUNT the X register ends up 0xFFFFFFFF.  PULL NOBLOCK with an empty
// TX FIFO copies X (not OSR) into OSR, which would give a ~43-second period.
// Saving the count in Y and reloading X from Y each period avoids this.
//
// CPU pushes one delay count to TX FIFO before enabling the SM, then spins
// polling RX FIFO. Each tick → toggle all 8 GPIO bits.
//
// Timing at 100 MHz system clock, clkdiv = 1:
//   Each JMP X-- = 1 PIO clock = 1 system clock cycle
//   BLINK_COUNT = 50,000,000 → 0.5 s half-period → ~1 Hz visible blink

#define PULL_NOBLOCK        0x80A0u            // PULL, IfEmpty=0, Noblock=1
#define MOV_Y_OSR           0xA047u            // MOV Y, OSR
#define MOV_X_Y             0xA022u            // MOV X, Y
#define JMP_X_DEC(addr)     (0x0040u | (addr)) // JMP X--, addr (condition 010)
#define PUSH_NOBLOCK        0x8020u            // PUSH, IfFull=0, Noblock=1

#define BLINK_COUNT         50000000u          // 0.5 s at 100 MHz

void main(void) {
    const uint32_t base = PIO0_BASE;
    const int sm = 0;

    // --- Load PIO program ---
    PIO_INSTR_MEM(base, 0) = PULL_NOBLOCK;   // one-shot init
    PIO_INSTR_MEM(base, 1) = MOV_Y_OSR;      // one-shot init
    PIO_INSTR_MEM(base, 2) = MOV_X_Y;        // [wrap_bottom] reload X
    PIO_INSTR_MEM(base, 3) = JMP_X_DEC(3);   // countdown
    PIO_INSTR_MEM(base, 4) = PUSH_NOBLOCK;   // [wrap_top]  tick

    // --- Configure SM0 ---
    PIO_SM_CLKDIV(base, sm)    = PIO_CLKDIV(1, 0);   // full 100 MHz
    PIO_SM_EXECCTRL(base, sm)  = PIO_EXECCTRL_WRAP_TOP(4)
                                | PIO_EXECCTRL_WRAP_BOTTOM(2); // loop over addr 2-4
    PIO_SM_SHIFTCTRL(base, sm) = 0;
    PIO_SM_PINCTRL(base, sm)   = 0;                   // no PIO GPIO pins used

    // --- Prime TX FIFO before enabling (PULL NOBLOCK reads it on first pass) ---
    PIO_TXF(base, sm) = BLINK_COUNT;

    // --- Enable SM ---
    GPIO_OUT = 0x00;
    PIO_CTRL(base) = PIO_CTRL_SM_ENABLE(sm);

    // --- CPU loop: drain RX tick, toggle GPIO ---
    uint32_t state = 0;
    while (1) {
        while (PIO_FSTAT(base) & PIO_FSTAT_RXEMPTY(sm));
        (void)PIO_RXF(base, sm);   // drain tick word (value unused)

        state ^= 0xFF;
        GPIO_OUT = state;
    }
}
