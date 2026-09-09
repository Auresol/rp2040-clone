#include "soc.h"

// PIO PWM breathing LED — PIO0 SM0 generates autonomous PWM on GPIO bit 0
// (RPi header pin 1 via PIO SET PINS).  CPU varies duty cycle to create a
// smooth in/out breathing effect.
//
// PIO program (9 instructions, wrap 1→8):
//   addr 0: SET PINDIRS, 1   — mark bit 0 as output (runs once at startup)
//   addr 1: PULL BLOCK       — on_count from TX FIFO          ← wrap_bottom
//   addr 2: MOV X, OSR       — X = on_count
//   addr 3: SET PINS, 1      — drive pin HIGH
//   addr 4: JMP X--, 4       — hold high for X+1 cycles
//   addr 5: PULL BLOCK       — off_count from TX FIFO
//   addr 6: MOV X, OSR       — X = off_count
//   addr 7: SET PINS, 0      — drive pin LOW
//   addr 8: JMP X--, 8       — hold low for X+1 cycles        ← wrap_top
//                              (fall-through wraps to addr 1)
//
// CPU pushes alternating (on_count, off_count) pairs.  JMP X-- loops for
// X+1 PIO-clock cycles, so push on-1 / off-1 to get exactly `on` / `off`
// cycles (min 1 each — harmless for a visual demo).
//
// Timing @ 100 MHz, clkdiv=1:
//   PERIOD = 10 000 PIO cycles = 100 µs → 10 kHz PWM
//   BREATH_HOLD = 100 PWM periods per brightness step = 10 ms/step
//   BREATH_STEPS = 100 → 200 steps per breath (up + down) × 10 ms = ~2 s

#define SET_PINDIRS_1   0xE081u   // SET PINDIRS, 1
#define SET_PINS_1      0xE001u   // SET PINS, 1
#define SET_PINS_0      0xE000u   // SET PINS, 0
#define PULL_BLOCK      0x8080u   // PULL blocking
#define MOV_X_OSR       0xA027u   // MOV X, OSR
#define JMP_X_DEC(a)    (0x0040u | (a))

#define PERIOD          10000u    // PIO cycles per PWM period
#define BREATH_HOLD     100u      // PWM periods per brightness step
#define BREATH_STEPS    100u      // number of brightness levels

static inline void fifo_push(uint32_t base, int sm, uint32_t val) {
    while (PIO_FSTAT(base) & PIO_FSTAT_TXFULL(sm));
    PIO_TXF(base, sm) = val;
}

void main(void) {
    const uint32_t base = PIO0_BASE;
    const int sm = 0;

    // --- Load PIO program ---
    PIO_INSTR_MEM(base, 0) = SET_PINDIRS_1;
    PIO_INSTR_MEM(base, 1) = PULL_BLOCK;
    PIO_INSTR_MEM(base, 2) = MOV_X_OSR;
    PIO_INSTR_MEM(base, 3) = SET_PINS_1;
    PIO_INSTR_MEM(base, 4) = JMP_X_DEC(4);
    PIO_INSTR_MEM(base, 5) = PULL_BLOCK;
    PIO_INSTR_MEM(base, 6) = MOV_X_OSR;
    PIO_INSTR_MEM(base, 7) = SET_PINS_0;
    PIO_INSTR_MEM(base, 8) = JMP_X_DEC(8);

    // --- Configure SM0 ---
    PIO_SM_CLKDIV(base, sm)    = PIO_CLKDIV(1, 0);              // full 100 MHz
    PIO_SM_EXECCTRL(base, sm)  = PIO_EXECCTRL_WRAP_TOP(8)
                                | PIO_EXECCTRL_WRAP_BOTTOM(1);
    PIO_SM_SHIFTCTRL(base, sm) = 0;
    PIO_SM_PINCTRL(base, sm)   = PIO_PINCTRL_SET_BASE(0)        // SET → bit 0
                                | PIO_PINCTRL_SET_COUNT(1);

    // --- Enable SM (stalls immediately on PULL at addr 1) ---
    PIO_CTRL(base) = PIO_CTRL_SM_ENABLE(sm);

    // --- Breathing loop ---
    // Ramp duty from 1/STEPS to (STEPS-1)/STEPS and back.
    // Skip exact 0% and 100% to avoid underflow (on/off are always >= 1).
    while (1) {
        // Ramp up: dim → bright
        for (uint32_t d = 1; d < BREATH_STEPS; d++) {
            uint32_t on  = d * PERIOD / BREATH_STEPS;
            uint32_t off = PERIOD - on;
            for (uint32_t h = 0; h < BREATH_HOLD; h++) {
                fifo_push(base, sm, on  - 1);
                fifo_push(base, sm, off - 1);
            }
        }
        // Ramp down: bright → dim
        for (uint32_t d = BREATH_STEPS - 1; d > 0; d--) {
            uint32_t on  = d * PERIOD / BREATH_STEPS;
            uint32_t off = PERIOD - on;
            for (uint32_t h = 0; h < BREATH_HOLD; h++) {
                fifo_push(base, sm, on  - 1);
                fifo_push(base, sm, off - 1);
            }
        }
    }
}
