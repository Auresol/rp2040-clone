#include "soc.h"

// ---------------------------------------------------------------------------
// Shared results — core 1 writes its count here, core 0 reads it

volatile uint32_t core1_result = 0;
volatile uint32_t core1_done   = 0;

// ---------------------------------------------------------------------------
// Core 1 entry: hammer a SRAM region as fast as possible

void core1_main(void) {
    volatile uint32_t *buf = (volatile uint32_t *)0x00002000;
    uint32_t n = 0;

    for (uint32_t i = 0; i < 1000; i++) {
        buf[i & 0xFF] = i;      // write
        n += buf[i & 0xFF];     // read back
    }

    core1_result = n;
    core1_done   = 1;
}

// ---------------------------------------------------------------------------
// Core 0 entry

void main(void) {
    // Launch core 1
    CORE1_MAILBOX = (uint32_t)core1_main;

    // Core 0: hammer a different SRAM region at the same time
    volatile uint32_t *buf = (volatile uint32_t *)0x00001000;
    uint32_t n = 0;

    for (uint32_t i = 0; i < 1000; i++) {
        buf[i & 0xFF] = i;
        n += buf[i & 0xFF];
    }

    // Wait for core 1 to finish
    while (!core1_done);

    // Both cores finished — signal pass
    // (n and core1_result should both be 499500 if no corruption)
    if (n == 499500 && core1_result == 499500)
        TEST_PASS();
    // else hang — sim will see FAIL
    while (1);
}
