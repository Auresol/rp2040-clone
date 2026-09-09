#include "soc.h"

// Each GPIO bit blinks at half the frequency of the bit below it.
// Output is bits [28:21] of a free-running counter, giving a binary ripple.
//
// At 100 MHz with ~4 cycles/iteration:
//   bit 0: ~12 Hz   bit 1: ~6 Hz   bit 2: ~3 Hz   bit 3: ~1.5 Hz
//   bit 4: ~0.75 Hz  bit 5: ~0.37 Hz  bit 6: ~0.19 Hz  bit 7: ~0.09 Hz
//
// Adjust the shift right if blinks are too fast or too slow.

void main(void) {
    uint32_t ctr = 0;
    while (1) {
        GPIO_OUT = (ctr >> 21) & 0xFF;
        ctr++;
    }
}
