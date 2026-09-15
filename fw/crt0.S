// crt0.S — C RunTime 0: the code that runs before main().
//
// The C compiler assumes certain things are already true when main() starts.
// crt0 makes those things true.
//
// Single-core variant: only one hart (mhartid = 0) runs.
//
// ---------------------------------------------------------------------------
// Jobs before calling main():
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
// ---------------------------------------------------------------------------
// Stack layout — one core, 4 KB region growing downward:
//
//   Core 0: 0xEFFC+1 .. 0xFFFC   (sp starts at 0xFFFC)

#define CORE0_STACK_TOP  0x0000FFFC

.section .text.crt0
.global _start
_start:
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

    call  main

    // main() returned — hang forever
.hang:
    j     .hang
