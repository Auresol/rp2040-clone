# test_pio.S — PIO loopback test
#
# Programs PIO0 SM0 with a 3-instruction loop:
#   addr 0: PULL blocking   (TX FIFO → OSR)
#   addr 1: MOV ISR, OSR   (copy)
#   addr 2: PUSH blocking   (ISR → RX FIFO, wraps back to 0)
#
# CPU pushes 3 known words to TXF0, reads them back from RXF0,
# verifies each matches. Writes sentinel 0xdeadbeef to 0x3ffc on pass.
#
# PIO instruction encodings used:
#   PULL blocking  = 0x8080  (opcode=100, bit7=1, IFEMPTY=0, NOBLOCK=0)
#   MOV ISR, OSR  = 0xA0C7  (opcode=101, dst=ISR=110, op=none=00, src=OSR=111)
#   PUSH blocking  = 0x8000  (opcode=100, bit7=0, IFFULL=0, NOBLOCK=0)

.section .text
.global _start

.equ PIO0_BASE,            0x50200000

.equ PIO_CTRL,             0x000
.equ PIO_FSTAT,            0x004
.equ PIO_TXF0,             0x010
.equ PIO_RXF0,             0x020
.equ PIO_INSTR_MEM0,       0x048
.equ PIO_SM0_CLKDIV,       0x0C8
.equ PIO_SM0_EXECCTRL,     0x0CC
.equ PIO_SM0_SHIFTCTRL,    0x0D0
.equ PIO_SM0_PINCTRL,      0x0DC

# FSTAT bits for SM0
.equ FSTAT_SM0_TXFULL,     (1 << 0)    # 0x00000001
.equ FSTAT_SM0_RXEMPTY,    (1 << 24)   # 0x01000000

_start:
    csrr a0, mhartid
    bnez a0, hart1_spin

    li   s0, PIO0_BASE

    # -------------------------------------------------------
    # Write instruction memory
    # -------------------------------------------------------
    li   t0, 0x8080             # PULL blocking
    sw   t0, PIO_INSTR_MEM0 + 0(s0)
    li   t0, 0xA0C7             # MOV ISR, OSR
    sw   t0, PIO_INSTR_MEM0 + 4(s0)
    li   t0, 0x8000             # PUSH blocking
    sw   t0, PIO_INSTR_MEM0 + 8(s0)

    # -------------------------------------------------------
    # Configure SM0
    # -------------------------------------------------------
    # CLKDIV: INT=1, FRAC=0 → tick every system clock cycle
    li   t0, 0x00010000
    sw   t0, PIO_SM0_CLKDIV(s0)

    # EXECCTRL: WRAP_TOP=2 [16:12], WRAP_BOTTOM=0 [11:7]
    # After PUSH at addr 2, SM wraps back to PULL at addr 0
    li   t0, 0x00002000
    sw   t0, PIO_SM0_EXECCTRL(s0)

    # SHIFTCTRL: all defaults (no autopush/pull, shift right)
    sw   zero, PIO_SM0_SHIFTCTRL(s0)

    # PINCTRL: no GPIO used
    sw   zero, PIO_SM0_PINCTRL(s0)

    # -------------------------------------------------------
    # Enable SM0 — it immediately executes PULL and stalls
    # waiting for TX FIFO data
    # -------------------------------------------------------
    li   t0, 0x1
    sw   t0, PIO_CTRL(s0)

    # -------------------------------------------------------
    # Push 3 words into TXF0
    # -------------------------------------------------------
    li   s1, 0xDEAD1234
    jal  ra, push_tx

    li   s1, 0xCAFEBABE
    jal  ra, push_tx

    li   s1, 0x12345678
    jal  ra, push_tx

    # -------------------------------------------------------
    # Pop and verify — must come back in the same order
    # -------------------------------------------------------
    li   s2, 0xDEAD1234
    jal  ra, pop_rx
    bne  s1, s2, fail

    li   s2, 0xCAFEBABE
    jal  ra, pop_rx
    bne  s1, s2, fail

    li   s2, 0x12345678
    jal  ra, pop_rx
    bne  s1, s2, fail

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

# -------------------------------------------------------
# push_tx: push s1 to TXF0, blocking until not full
# clobbers: t0, t1
# -------------------------------------------------------
push_tx:
    li   t0, FSTAT_SM0_TXFULL
1:  lw   t1, PIO_FSTAT(s0)
    and  t1, t1, t0
    bnez t1, 1b
    sw   s1, PIO_TXF0(s0)
    ret

# -------------------------------------------------------
# pop_rx: pop from RXF0 into s1, blocking until not empty
# clobbers: t0, t1
# -------------------------------------------------------
pop_rx:
    li   t0, FSTAT_SM0_RXEMPTY
1:  lw   t1, PIO_FSTAT(s0)
    and  t1, t1, t0
    bnez t1, 1b
    lw   s1, PIO_RXF0(s0)
    ret
