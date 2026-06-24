#include "soc.h"

// Simplest possible C firmware: core 1 spins, core 0 writes sentinel.
// If this passes, crt0 + linker script + toolchain are all correct.

void main(void) {
    TEST_PASS();
    while (1);
}
