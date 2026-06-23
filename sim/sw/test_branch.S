# Branch test: beq, bne, blt, bge, bltu, bgeu, jal, jalr
# Also tests a counted loop.
# Writes 0xdeadbeef to 0x3ffc on pass.

.section .text
.global _start

_start:
    csrr a0, mhartid
    bnez a0, hart1_spin      # hart 1 spins — only hart 0 runs the test

    # beq — taken
    li   t0, 42
    li   t1, 42
    beq  t0, t1, beq_taken
    j    fail
beq_taken:

    # beq — not taken
    li   t0, 1
    li   t1, 2
    beq  t0, t1, fail

    # bne — taken
    li   t0, 1
    li   t1, 2
    bne  t0, t1, bne_taken
    j    fail
bne_taken:

    # bne — not taken
    li   t0, 5
    li   t1, 5
    bne  t0, t1, fail

    # blt signed — taken (-1 < 0)
    li   t0, -1
    li   t1, 0
    blt  t0, t1, blt_taken
    j    fail
blt_taken:

    # blt signed — not taken (unsigned large is positive when signed)
    li   t0, -1             # 0xFFFFFFFF, signed = -1
    li   t1, -2             # 0xFFFFFFFE, signed = -2
    blt  t0, t1, fail       # -1 < -2 is false

    # bge signed — taken (equal)
    li   t0, 5
    li   t1, 5
    bge  t0, t1, bge_taken
    j    fail
bge_taken:

    # bge signed — taken (greater)
    li   t0, 1
    li   t1, -1
    bge  t0, t1, bge2_taken
    j    fail
bge2_taken:

    # bltu — 0xFFFFFFFF is the largest unsigned value
    li   t0, 0
    li   t1, -1             # 0xFFFFFFFF unsigned
    bltu t0, t1, bltu_taken
    j    fail
bltu_taken:

    # bltu — not taken (same value)
    li   t0, 5
    li   t1, 5
    bltu t0, t1, fail

    # bgeu — taken (0xFFFFFFFF >= anything)
    li   t0, -1
    li   t1, 0
    bgeu t0, t1, bgeu_taken
    j    fail
bgeu_taken:

    # Counted loop: sum 1..10, expect 55
    li   t0, 0              # accumulator
    li   t1, 1              # counter
    li   t2, 10
loop:
    add  t0, t0, t1
    addi t1, t1, 1
    ble  t1, t2, loop
    li   t3, 55
    bne  t0, t3, fail

    # jal: jump and link stores return address in ra
    # jalr: jump to ra (simulates a function return)
    jal  ra, jal_target     # ra = address of next insn (j jalr_done)
    j    jalr_done          # execution returns here via jalr, then continues
    j    fail               # not reached
jal_target:
    ret                     # jalr x0, ra, 0 — returns to caller
jalr_done:

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
