#include "soc.h"

// Blink all 8 GPIO outputs at ~1 Hz (500ms on, 500ms off).
// At 100 MHz system clock, 500ms = 50,000,000 cycles.
// The delay loop is ~4 cycles/iteration → count = 12,500,000.

#define DELAY_CYCLES 12500000u

static void delay(uint32_t n) {
    volatile uint32_t i = n;
    while (i--);
}

void main(void) {
    while (1) {
        GPIO_OUT = 0xFF;        // all 8 bits on
        delay(DELAY_CYCLES);
        GPIO_OUT = 0x00;        // all off
        delay(DELAY_CYCLES);
    }
}
