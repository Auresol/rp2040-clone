# ALU test: add, sub, and, or, xor, sll, srl, sra, slt, sltu
# Writes 0xdeadbeef to 0x3ffc on pass, loops at fail: on failure.

.section .text
.global _start

_start:
    csrr a0, mhartid
    bnez a0, hart1_spin      # hart 1 spins — only hart 0 runs the test

    # add
    li   t0, 10
    li   t1, 20
    add  t2, t0, t1
    li   t3, 30
    bne  t2, t3, fail

    # sub
    li   t0, 50
    li   t1, 20
    sub  t2, t0, t1
    li   t3, 30
    bne  t2, t3, fail

    # and
    li   t0, 0xFF0
    li   t1, 0x0FF
    and  t2, t0, t1
    li   t3, 0x0F0
    bne  t2, t3, fail

    # or
    li   t0, 0xF00
    li   t1, 0x0F0
    or   t2, t0, t1
    li   t3, 0xFF0
    bne  t2, t3, fail

    # xor
    li   t0, 0xF0F
    li   t1, 0x0F0
    xor  t2, t0, t1
    li   t3, 0xFFF
    bne  t2, t3, fail

    # sll (shift left logical)
    li   t0, 1
    slli t2, t0, 8
    li   t3, 256
    bne  t2, t3, fail

    # srl (shift right logical, zero-fills)
    li   t0, 256
    srli t2, t0, 4
    li   t3, 16
    bne  t2, t3, fail

    # sra (shift right arithmetic, sign-extends)
    li   t0, -256           # 0xFFFFFF00
    srai t2, t0, 4          # expect 0xFFFFFFF0 = -16
    li   t3, -16
    bne  t2, t3, fail

    # srl vs sra differ on negative numbers
    li   t0, -256           # 0xFFFFFF00
    srli t2, t0, 4          # expect 0x0FFFFFF0 (no sign extension)
    li   t3, 0x0FFFFFF0
    bne  t2, t3, fail

    # slt (signed less-than)
    li   t0, -1
    li   t1, 0
    slt  t2, t0, t1         # -1 < 0 → 1
    li   t3, 1
    bne  t2, t3, fail

    slt  t2, t1, t0         # 0 < -1 → 0
    bne  t2, zero, fail

    # sltu (unsigned less-than: 0xFFFFFFFF is large, not negative)
    li   t0, 0
    li   t1, -1             # 0xFFFFFFFF unsigned
    sltu t2, t0, t1         # 0 < 0xFFFFFFFF → 1
    li   t3, 1
    bne  t2, t3, fail

    sltu t2, t1, t0         # 0xFFFFFFFF < 0 → 0
    bne  t2, zero, fail

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
