# GPIO test: write a pattern to the GPIO register, read it back, verify.
# GPIO base: 0x4000_0000
# Writes 0xdeadbeef to SRAM 0x3ffc on pass.

.section .text
.global _start

_start:
    csrr a0, mhartid
    bnez a0, hart1_spin      # hart 1 spins — only hart 0 runs the test

    li   s0, 0x40000000      # GPIO base address

    # Write a pattern and read it back
    li   t0, 0xA5A5A5A5
    sw   t0, 0(s0)
    lw   t1, 0(s0)
    bne  t0, t1, fail

    # Write a second pattern to confirm the register updates
    li   t0, 0x12345678
    sw   t0, 0(s0)
    lw   t1, 0(s0)
    bne  t0, t1, fail

    # Write zero and verify (checks reset-to-zero behaviour)
    sw   zero, 0(s0)
    lw   t1, 0(s0)
    bne  t1, zero, fail

pass:
    li   a0, 0xdeadbeef
    li   a1, 0x00003ffc
    sw   a0, 0(a1)
done:
    j    done

fail:
    j    fail

hart1_spin:
    j    hart1_spin
