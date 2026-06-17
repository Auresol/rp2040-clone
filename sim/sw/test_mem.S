# Memory test: sw/lw, sh/lh/lhu, sb/lb/lbu, byte-lane isolation
# Scratch area at 0x200 — well past the code.
# Writes 0xdeadbeef to 0x3ffc on pass.

.section .text
.global _start

_start:
    li   s0, 0x200          # base of scratch area

    # sw / lw round-trip
    li   t0, 0xdeadbeef
    sw   t0, 0(s0)
    lw   t1, 0(s0)
    bne  t0, t1, fail

    # sh / lhu (zero-extends on load)
    li   t0, 0xCAFE
    sh   t0, 4(s0)
    lhu  t1, 4(s0)
    bne  t0, t1, fail

    # lh sign-extends a negative halfword
    li   t0, 0x8000
    sh   t0, 4(s0)
    lh   t1, 4(s0)
    li   t2, -32768         # 0xFFFF8000
    bne  t1, t2, fail

    # sb / lbu (zero-extends on load)
    li   t0, 0xAB
    sb   t0, 8(s0)
    lbu  t1, 8(s0)
    bne  t0, t1, fail

    # lb sign-extends a negative byte
    li   t0, 0x80
    sb   t0, 8(s0)
    lb   t1, 8(s0)
    li   t2, -128           # 0xFFFFFF80
    bne  t1, t2, fail

    # Byte-lane isolation: store a word, read back each byte individually
    li   t0, 0x12345678
    sw   t0, 12(s0)
    lbu  t1, 12(s0)
    li   t2, 0x78
    bne  t1, t2, fail
    lbu  t1, 13(s0)
    li   t2, 0x56
    bne  t1, t2, fail
    lbu  t1, 14(s0)
    li   t2, 0x34
    bne  t1, t2, fail
    lbu  t1, 15(s0)
    li   t2, 0x12
    bne  t1, t2, fail

    # Sub-word write isolation: writing a byte must not disturb adjacent bytes
    li   t0, 0xAABBCCDD
    sw   t0, 16(s0)
    li   t0, 0x11
    sb   t0, 17(s0)         # overwrite byte 1 only
    lw   t1, 16(s0)
    li   t2, 0xAABB11DD     # byte 1 changed, others intact
    bne  t1, t2, fail

pass:
    li   a0, 0xdeadbeef
    li   a1, 0x00003ffc
    sw   a0, 0(a1)
done:
    j    done

fail:
    j    fail
