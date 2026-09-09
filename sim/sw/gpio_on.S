# Minimal hardware test: write 0xFF to GPIO and loop forever.
# No C runtime. Tests firmware loading + CPU execution + GPIO peripheral.

.section .text
.global _start

_start:
    csrr  a0, mhartid
    bnez  a0, spin         # hart 1 spins

    li    a1, 0x40000000   # GPIO base
    li    a0, 0xFF
    sw    a0, 0(a1)        # GPIO_OUT = 0xFF

    li    a1, 0x00003ffc   # sentinel address (SRAM[0xfff])
    li    a0, 0xdeadbeef
    sw    a0, 0(a1)        # signal pass to simulator

spin:
    j     spin
