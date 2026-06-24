/*
 * Linker script for rvsoc — single 64KB SRAM at 0x00000000.
 *
 * Memory layout (low → high):
 *   0x0000_0000  .text       code (crt0 first, then everything else)
 *                .rodata     read-only data (string literals, const arrays)
 *                .data       initialised globals
 *                .bss        zero-initialised globals
 *                [ heap grows up from end of .bss ]
 *   0x0000_3FF0  CORE1_MAILBOX  (crt0 polls here for core 1 entry point)
 *   0x0000_3FF4  reserved
 *   0x0000_3FF8  TEST_SENTINEL_EXTRA (spare)
 *   0x0000_3FFC  TEST_SENTINEL  (sim checks 0xdeadbeef here for PASS)
 *
 *   0x0000_EFFC  core 1 stack top (grows down, 4 KB)
 *   0x0000_FFFC  core 0 stack top (grows down, 4 KB)
 */

MEMORY {
    SRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS {
    /* ------------------------------------------------------------------ */
    /* Code — crt0 must be first so reset vector lands at 0x0             */
    .text 0x00000000 : {
        KEEP(*(.text.crt0))
        *(.text*)
        *(.rodata*)
    } > SRAM

    /* ------------------------------------------------------------------ */
    /* Initialised globals                                                  */
    .data : {
        *(.data*)
    } > SRAM

    /* ------------------------------------------------------------------ */
    /* Zero-initialised globals (crt0 zeroes this region at startup)       */
    .bss : {
        __bss_start = .;
        *(.bss*)
        *(COMMON)
        __bss_end = .;
    } > SRAM

    /* ------------------------------------------------------------------ */
    /* Discard C++ exception tables and debug info we don't need           */
    /DISCARD/ : {
        *(.eh_frame*)
        *(.comment)
    }
}
