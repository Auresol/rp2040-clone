# Minimal RISC-V test program
# Writes sentinel value 0xdeadbeef to address 0x0000_3ffc (top of 64KB SRAM)
# Testbench watches that address and exits when it sees the value

.section .text
.global _start

_start:
    li   a0, 0xdeadbeef      # sentinel value
    li   a1, 0x00003ffc      # top word of 64KB SRAM
    sw   a0, 0(a1)
done:
    j    done                 # loop forever
