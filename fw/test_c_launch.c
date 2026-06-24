#include "soc.h"

// Tests core 1 launch mechanism only. No arithmetic.
// Core 1 writes a known value and sets a flag.
// Core 0 waits for the flag, verifies the value, writes sentinel.

volatile uint32_t core1_flag = 0;

void core1_main(void) {
    core1_flag = 0xCAFE;
}

void main(void) {
    CORE1_MAILBOX = (uint32_t)core1_main;

    while (core1_flag != 0xCAFE);

    TEST_PASS();
    while (1);
}
