// crt0.S — C RunTime 0: the code that runs before main().
//
// The C compiler assumes certain things are already true when main() starts.
// crt0 makes those things true.
//
// On reset, BOTH cores boot simultaneously at address 0x00000000.
// The first instruction reads mhartid to tell them apart, then they fork.
//
// ---------------------------------------------------------------------------
// Core 0 has three jobs before calling main():
//
//   1. Set stack pointer
//      C functions use the stack for local variables and return addresses.
//      Without sp, the first function call corrupts random memory.
//
//   2. Zero .bss
//      C guarantees global variables without explicit initializers start at 0.
//      The linker puts them in .bss but doesn't fill it — we must do it here.
//      Example:
//          int counter;        // guaranteed 0 at startup — crt0 ensures this
//          void main(void) { counter++; }   // would be garbage without zeroing
//
//   3. Clear the Core 1 mailbox
//      Prevents Core 1 from waking up before main() intentionally launches it.
//
// ---------------------------------------------------------------------------
// Core 1 just waits.
//
//   When main() wants to launch Core 1, it writes a function pointer into
//   the mailbox (0x3FF0). Core 1 polls that address and jumps there.
//
// ---------------------------------------------------------------------------
// Stack layout — each core gets its own 4 KB region, growing downward:
//
//   Core 0: 0xEFFC+1 .. 0xFFFC   (sp starts at 0xFFFC)
//   Core 1: 0xDFFC+1 .. 0xEFFC   (sp starts at 0xEFFC)
//
// Stacks are below the mailbox (0x3FF0) and sentinel (0x3FFC), so a stack
// overflow grows toward lower addresses and won't silently corrupt those.

#define CORE0_STACK_TOP  0x0000FFFC
#define CORE1_STACK_TOP  0x0000EFFC
#define CORE1_MAILBOX    0x00003FF0   // core 0 writes core 1 entry point here

.section .text.crt0
.global _start
_start:
    csrr  a0, mhartid
    bnez  a0, .core1_init          // core 1 goes right, core 0 falls through

// ---------------------------------------------------------------------------
// Core 0 startup
.core0_init:
    li    sp, CORE0_STACK_TOP      // (1) set stack — required before any call

    // (2) zero .bss — C guarantees globals start at 0
    la    a0, __bss_start
    la    a1, __bss_end
.bss_zero:
    bge   a0, a1, .bss_done
    sw    zero, 0(a0)
    addi  a0, a0, 4
    j     .bss_zero
.bss_done:

    // (3) clear mailbox — core 1 must not wake before main() is ready
    li    t0, CORE1_MAILBOX
    sw    zero, 0(t0)

    call  main

    // main() returned — nothing left to do, hang forever
.core0_hang:
    j     .core0_hang

// ---------------------------------------------------------------------------
// Core 1 startup — spin until core 0 writes an entry point into the mailbox
.core1_init:
    li    sp, CORE1_STACK_TOP      // set stack (core 1 needs its own region)
    li    t0, CORE1_MAILBOX
.core1_poll:
    lw    t1, 0(t0)
    beqz  t1, .core1_poll         // keep polling until non-zero
    jr    t1                       // jump to function pointer core 0 wrote
