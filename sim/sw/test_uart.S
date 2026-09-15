# UART test: configure UART0, transmit "Hi\n", wait for TX idle, verify via sentinel.
#
# UART0 base:   0x4003_4000
# UARTDR:       base + 0x000   write=TX enqueue, read=RX dequeue
# UARTFR:       base + 0x018   [7]=TXFE [6]=RXFF [5]=TXFF [4]=RXFE [3]=BUSY
# UARTIBRD:     base + 0x024   integer baud divisor
# UARTCR:       base + 0x030   [0]=UARTEN [8]=TXE [9]=RXE
#
# Use IBRD=10 in sim (fast baud for simulation speed).
# On FPGA at 125 MHz: set IBRD=1085 for 115200 baud.
#
# Writes 0xdeadbeef to SRAM 0x3ffc on pass.

.section .text
.global _start

_start:
    csrr a0, mhartid
    bnez a0, hart1_spin          # hart 1 spins — only hart 0 runs the test

    li   s0, 0x40034000          # UART0 base

    # --- Configure baud rate and enable UART ---
    li   t0, 10
    sw   t0, 0x24(s0)            # UARTIBRD = 10 (fast for simulation)

    li   t0, 0x301               # UARTEN | TXE | RXE
    sw   t0, 0x30(s0)            # UARTCR

    # --- Transmit 'H' (0x48) ---
wait_tx_h:
    lw   t1, 0x18(s0)            # read UARTFR
    andi t1, t1, 0x20            # isolate TXFF (bit 5)
    bnez t1, wait_tx_h           # spin while TX FIFO full
    li   t0, 0x48                # 'H'
    sw   t0, 0(s0)               # write UARTDR

    # --- Transmit 'i' (0x69) ---
wait_tx_i:
    lw   t1, 0x18(s0)
    andi t1, t1, 0x20
    bnez t1, wait_tx_i
    li   t0, 0x69                # 'i'
    sw   t0, 0(s0)

    # --- Transmit '\n' (0x0a) ---
wait_tx_n:
    lw   t1, 0x18(s0)
    andi t1, t1, 0x20
    bnez t1, wait_tx_n
    li   t0, 0x0a                # '\n'
    sw   t0, 0(s0)

    # --- Wait for TX to fully drain (BUSY = bit 3 of UARTFR) ---
wait_busy:
    lw   t1, 0x18(s0)
    andi t1, t1, 0x08            # BUSY bit
    bnez t1, wait_busy

pass:
    li   a0, 0xdeadbeef
    li   a1, 0x00003ffc
    sw   a0, 0(a1)
done:
    j    done

hart1_spin:
    j    hart1_spin
