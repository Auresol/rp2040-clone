#ifndef SOC_H
#define SOC_H

#include <stdint.h>

// ---------------------------------------------------------------------------
// Register access helpers

#define REG(addr)        (*(volatile uint32_t *)(addr))
#define REG16(addr)      (*(volatile uint16_t *)(addr))

// ---------------------------------------------------------------------------
// GPIO  (0x4000_0000)
// Single 32-bit output register — write sets pins, read returns current value.

#define GPIO_BASE        0x40000000u
#define GPIO_OUT         REG(GPIO_BASE + 0x000)

// ---------------------------------------------------------------------------
// PIO0  (0x5020_0000)
// PIO1  (0x5030_0000)
// Register layout matches RP2040 spec exactly.

#define PIO0_BASE        0x50200000u
#define PIO1_BASE        0x50300000u

// -- Global registers -------------------------------------------------------
#define PIO_CTRL(base)          REG((base) + 0x000)  // SM enable / restart
#define PIO_FSTAT(base)         REG((base) + 0x004)  // FIFO status (RO)
#define PIO_FDEBUG(base)        REG((base) + 0x008)  // FIFO debug  (W1C)
#define PIO_FLEVEL(base)        REG((base) + 0x00C)  // FIFO levels (RO)
#define PIO_TXF(base, sm)       REG((base) + 0x010 + (sm)*4)  // TX FIFO WO
#define PIO_RXF(base, sm)       REG((base) + 0x020 + (sm)*4)  // RX FIFO RO
#define PIO_IRQ(base)           REG((base) + 0x030)  // IRQ flags   (W1C)
#define PIO_IRQ_FORCE(base)     REG((base) + 0x034)  // Force-set IRQ (WO)
#define PIO_DBG_PADOUT(base)    REG((base) + 0x03C)  // GPIO out snapshot
#define PIO_DBG_PADOE(base)     REG((base) + 0x040)  // GPIO OE snapshot
#define PIO_DBG_CFGINFO(base)   REG((base) + 0x044)  // Config info (RO)

// -- Instruction memory (32 slots × 16-bit) ---------------------------------
#define PIO_INSTR_MEM(base, i)  REG((base) + 0x048 + (i)*4)

// -- Per-SM registers (sm = 0..3) -------------------------------------------
#define PIO_SM_BASE(base, sm)   ((base) + 0x0C8 + (sm)*0x18)
#define PIO_SM_CLKDIV(base, sm)    REG(PIO_SM_BASE(base, sm) + 0x00)
#define PIO_SM_EXECCTRL(base, sm)  REG(PIO_SM_BASE(base, sm) + 0x04)
#define PIO_SM_SHIFTCTRL(base, sm) REG(PIO_SM_BASE(base, sm) + 0x08)
#define PIO_SM_ADDR(base, sm)      REG(PIO_SM_BASE(base, sm) + 0x0C)  // RO
#define PIO_SM_INSTR(base, sm)     REG(PIO_SM_BASE(base, sm) + 0x10)  // force-exec WO
#define PIO_SM_PINCTRL(base, sm)   REG(PIO_SM_BASE(base, sm) + 0x14)

// -- CTRL bits --------------------------------------------------------------
#define PIO_CTRL_SM_ENABLE(sm)     (1u << (sm))
#define PIO_CTRL_SM_RESTART(sm)    (1u << ((sm) + 4))
#define PIO_CTRL_CLKDIV_RESTART(sm)(1u << ((sm) + 8))

// -- FSTAT bits (each field is 4-bit, one per SM) ---------------------------
#define PIO_FSTAT_TXFULL(sm)   (1u << ((sm) + 0))
#define PIO_FSTAT_TXEMPTY(sm)  (1u << ((sm) + 8))
#define PIO_FSTAT_RXFULL(sm)   (1u << ((sm) + 16))
#define PIO_FSTAT_RXEMPTY(sm)  (1u << ((sm) + 24))

// -- SHIFTCTRL bits ---------------------------------------------------------
#define PIO_SHIFTCTRL_AUTOPUSH     (1u << 16)
#define PIO_SHIFTCTRL_AUTOPULL     (1u << 17)
#define PIO_SHIFTCTRL_IN_SHIFTDIR  (1u << 18)  // 1=left, 0=right
#define PIO_SHIFTCTRL_OUT_SHIFTDIR (1u << 19)  // 1=left, 0=right
#define PIO_SHIFTCTRL_PUSH_THRESH(n) (((n) & 0x1f) << 20)
#define PIO_SHIFTCTRL_PULL_THRESH(n) (((n) & 0x1f) << 25)

// -- CLKDIV helpers ---------------------------------------------------------
// clkdiv = (integer << 16) | (frac << 8)
// integer=1,frac=0 → run at full system clock speed
#define PIO_CLKDIV(integer, frac)  (((integer) << 16) | ((frac) << 8))

// -- EXECCTRL helpers -------------------------------------------------------
#define PIO_EXECCTRL_WRAP_TOP(n)    (((n) & 0x1f) << 12)
#define PIO_EXECCTRL_WRAP_BOTTOM(n) (((n) & 0x1f) <<  7)
#define PIO_EXECCTRL_STATUS_SEL     (1u << 4)  // 0=TXFIFO<N, 1=RXFIFO<N

// -- PINCTRL helpers --------------------------------------------------------
#define PIO_PINCTRL_OUT_BASE(pin)   (((pin) & 0x1f) <<  0)
#define PIO_PINCTRL_SET_BASE(pin)   (((pin) & 0x1f) <<  5)
#define PIO_PINCTRL_SIDESET_BASE(p) (((p)   & 0x1f) << 10)
#define PIO_PINCTRL_IN_BASE(pin)    (((pin) & 0x1f) << 15)
#define PIO_PINCTRL_OUT_COUNT(n)    (((n)   & 0x3f) << 20)
#define PIO_PINCTRL_SET_COUNT(n)    (((n)   & 0x07) << 26)
#define PIO_PINCTRL_SIDESET_COUNT(n)(((n)   & 0x07) << 29)

// ---------------------------------------------------------------------------
// Dual-core mailbox — defined in link.ld comment, used by crt0.S
// Core 0 writes core1's entry point here to wake it.

#define CORE1_MAILBOX   (*(volatile uint32_t *)0x00003FF0u)

// ---------------------------------------------------------------------------
// Sim test sentinel — write 0xdeadbeef here to signal PASS to testbench

#define TEST_PASS()  do { \
    (*(volatile uint32_t *)0x00003FFCu) = 0xdeadbeef; \
} while(0)

#endif // SOC_H
