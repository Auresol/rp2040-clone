// rxpsm32 — Dual-core RISC-V SoC with JTAG debug.
//
// CPU:   2 × Hazard3 (RV32IMC), hart 0 + hart 1
// Debug: JTAG DTM → DM (2 harts) → CPU debug ports (RISC-V 0.13.2)
//
// Instruction port: CPU0-I ┐                   ┌ SRAM I port
//                   CPU1-I ┘→ i_xbar (2×2) → ─┤
//                                              └ XIP flash (via cache)
//
// Data port:        CPU0-D ┐→ d_xbar (2×11) → SRAM D port + peripherals + SIO
//                   CPU1-D ┘
//
// Address map (instruction port):
//   0x0000_0000 – 0x0000_FFFF  →  SRAM I port (64 KB)
//   0x1000_0000 – 0x1FFF_FFFF  →  XIP flash (via cache → SPI 03h)
//
// Address map (data port):
//   0x0000_0000 – 0x0000_FFFF  →  SRAM     (64 KB)
//   0x4000_0000 – 0x4000_FFFF  →  GPIO     (SIO-style: IN/OUT/OE + SET/CLR/XOR)
//   0x4003_0000 – 0x4003_3FFF  →  UART0    (PL011-compatible)
//   0x4003_C000 – 0x4003_FFFF  →  SPI0     (PL022-compatible)
//   0x4005_0000 – 0x4005_3FFF  →  TIMER    (RISC-V mtime)
//   0x4005_4000 – 0x4005_7FFF  →  RESET    (reset controller)
//   0x4005_8000 – 0x4005_BFFF  →  WATCHDOG
//   0x4005_C000 – 0x4005_FFFF  →  SYSINFO  (read-only ID)
//   0x5020_0000 – 0x5020_FFFF  →  PIO0
//   0x5030_0000 – 0x5030_FFFF  →  PIO1
//   0xD000_0000 – 0xD000_0FFF  →  SIO      (spinlocks, FIFOs, CPUID)

`default_nettype none

module rxpsm32 (
    input  wire        clk,
    input  wire        rst_n,

    // JTAG debug port
    input  wire        tck,
    input  wire        trst_n,
    input  wire        tms,
    input  wire        tdi,
    output wire        tdo,

    // GPIO
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_out,
    output wire [31:0] gpio_oe,

    // PIO GPIO interface
    input  wire [31:0] pio_gpio_in,
    output wire [31:0] pio_gpio_out,
    output wire [31:0] pio_gpio_oe,

    // PIO IRQ outputs: [3:0]=PIO0 IRQs, [7:4]=PIO1 IRQs
    output wire [7:0]  pio_irq,

    // UART0
    output wire        uart_tx,
    input  wire        uart_rx,

    // SPI flash (XIP)
    output wire        spi_cs_n,
    output wire        spi_sck,
    output wire        spi_mosi,
    input  wire        spi_miso,

    // SPI0 general-purpose master
    output wire        spi0_sclk,
    output wire        spi0_mosi,
    input  wire        spi0_miso,
    output wire        spi0_cs_n
);

// ============================================================================
// CPU0 AHB signals

wire [31:0] cpu0_i_haddr,  cpu0_i_hwdata,  cpu0_i_hrdata;
wire        cpu0_i_hwrite, cpu0_i_hready,  cpu0_i_hresp;
wire [1:0]  cpu0_i_htrans;
wire [2:0]  cpu0_i_hsize,  cpu0_i_hburst;
wire [3:0]  cpu0_i_hprot;
wire        cpu0_i_hmastlock;
wire [7:0]  cpu0_i_hmaster;

wire [31:0] cpu0_d_haddr,  cpu0_d_hwdata,  cpu0_d_hrdata;
wire        cpu0_d_hwrite, cpu0_d_hready,  cpu0_d_hresp;
wire [1:0]  cpu0_d_htrans;
wire [2:0]  cpu0_d_hsize,  cpu0_d_hburst;
wire [3:0]  cpu0_d_hprot;
wire        cpu0_d_hmastlock;
wire [7:0]  cpu0_d_hmaster;
wire        cpu0_d_hexcl;

// ============================================================================
// CPU1 AHB signals

wire [31:0] cpu1_i_haddr,  cpu1_i_hwdata,  cpu1_i_hrdata;
wire        cpu1_i_hwrite, cpu1_i_hready,  cpu1_i_hresp;
wire [1:0]  cpu1_i_htrans;
wire [2:0]  cpu1_i_hsize,  cpu1_i_hburst;
wire [3:0]  cpu1_i_hprot;
wire        cpu1_i_hmastlock;
wire [7:0]  cpu1_i_hmaster;

wire [31:0] cpu1_d_haddr,  cpu1_d_hwdata,  cpu1_d_hrdata;
wire        cpu1_d_hwrite, cpu1_d_hready,  cpu1_d_hresp;
wire [1:0]  cpu1_d_htrans;
wire [2:0]  cpu1_d_hsize,  cpu1_d_hburst;
wire [3:0]  cpu1_d_hprot;
wire        cpu1_d_hmastlock;
wire [7:0]  cpu1_d_hmaster;
wire        cpu1_d_hexcl;

// ============================================================================
// I-port crossbar slave wires (SRAM I-port + XIP)

wire [31:0] ixbar_sram_haddr,  ixbar_sram_hrdata;
wire [1:0]  ixbar_sram_htrans;
wire        ixbar_sram_hready, ixbar_sram_hresp;

wire [31:0] ixbar_xip_haddr,  ixbar_xip_hwdata,  ixbar_xip_hrdata;
wire        ixbar_xip_hwrite, ixbar_xip_hready,   ixbar_xip_hresp;
wire [1:0]  ixbar_xip_htrans;
wire [2:0]  ixbar_xip_hsize;

// ============================================================================
// Decoder → peripheral wires (same as before)

wire [31:0] dec_sram_haddr,  dec_sram_hwdata,  dec_sram_hrdata;
wire        dec_sram_hwrite, dec_sram_hready,  dec_sram_hresp;
wire [1:0]  dec_sram_htrans;
wire [2:0]  dec_sram_hsize;
wire        dec_sram_hexokay;

wire [31:0] dec_gpio_haddr,  dec_gpio_hwdata,  dec_gpio_hrdata;
wire        dec_gpio_hwrite, dec_gpio_hready,  dec_gpio_hresp;
wire [1:0]  dec_gpio_htrans;
wire [2:0]  dec_gpio_hsize;

wire [31:0] dec_pio0_haddr,  dec_pio0_hwdata,  dec_pio0_hrdata;
wire        dec_pio0_hwrite, dec_pio0_hready,  dec_pio0_hresp;
wire [1:0]  dec_pio0_htrans;
wire [2:0]  dec_pio0_hsize;

wire [31:0] dec_pio1_haddr,  dec_pio1_hwdata,  dec_pio1_hrdata;
wire        dec_pio1_hwrite, dec_pio1_hready,  dec_pio1_hresp;
wire [1:0]  dec_pio1_htrans;
wire [2:0]  dec_pio1_hsize;

wire [31:0] dec_uart0_haddr,  dec_uart0_hwdata,  dec_uart0_hrdata;
wire        dec_uart0_hwrite, dec_uart0_hready,  dec_uart0_hresp;
wire [1:0]  dec_uart0_htrans;
wire [2:0]  dec_uart0_hsize;

wire [31:0] dec_spi0_haddr,  dec_spi0_hwdata,  dec_spi0_hrdata;
wire        dec_spi0_hwrite, dec_spi0_hready,  dec_spi0_hresp;
wire [1:0]  dec_spi0_htrans;
wire [2:0]  dec_spi0_hsize;

wire [31:0] dec_timer_haddr,  dec_timer_hwdata,  dec_timer_hrdata;
wire        dec_timer_hwrite, dec_timer_hready,  dec_timer_hresp;
wire [1:0]  dec_timer_htrans;
wire [2:0]  dec_timer_hsize;

wire [31:0] dec_wdog_haddr,  dec_wdog_hwdata,  dec_wdog_hrdata;
wire        dec_wdog_hwrite, dec_wdog_hready,  dec_wdog_hresp;
wire [1:0]  dec_wdog_htrans;
wire [2:0]  dec_wdog_hsize;

wire [31:0] dec_rstc_haddr,  dec_rstc_hwdata,  dec_rstc_hrdata;
wire        dec_rstc_hwrite, dec_rstc_hready,  dec_rstc_hresp;
wire [1:0]  dec_rstc_htrans;
wire [2:0]  dec_rstc_hsize;

wire [31:0] dec_sysinfo_haddr,  dec_sysinfo_hwdata,  dec_sysinfo_hrdata;
wire        dec_sysinfo_hwrite, dec_sysinfo_hready,  dec_sysinfo_hresp;
wire [1:0]  dec_sysinfo_htrans;
wire [2:0]  dec_sysinfo_hsize;

// SIO crossbar slave signals (SIO has dual ports, but crossbar sees one slave)
wire [31:0] dec_sio_haddr,  dec_sio_hwdata,  dec_sio_hrdata;
wire        dec_sio_hwrite, dec_sio_hready,  dec_sio_hresp;
wire [1:0]  dec_sio_htrans;
wire [2:0]  dec_sio_hsize;

// ============================================================================
// Reset controller + watchdog signals

wire        wdog_reset_out;
wire        wdog_tick_1mhz;
wire [1:0]  rc_cpu_rst_n;     // per-core reset outputs
wire [7:0]  periph_rst_n;

// ============================================================================
// JTAG Debug: DTM → DM → CPU0 + CPU1

// DMI APB bus (DTM ↔ DM)
wire        dmi_psel;
wire        dmi_penable;
wire        dmi_pwrite;
wire [8:0]  dmi_paddr;
wire [31:0] dmi_pwdata;
wire [31:0] dmi_prdata;
wire        dmi_pready;
wire        dmi_pslverr;

// DM ↔ CPU debug signals (2 harts, packed)
wire [1:0]  hart_req_halt;
wire [1:0]  hart_req_halt_on_reset;
wire [1:0]  hart_req_resume;
wire [1:0]  hart_halted;
wire [1:0]  hart_running;
wire [63:0] hart_data0_rdata;   // 2 × 32
wire [63:0] hart_data0_wdata;
wire [1:0]  hart_data0_wen;
wire [63:0] hart_instr_data;    // 2 × 32
wire [1:0]  hart_instr_data_vld;
wire [1:0]  hart_instr_data_rdy;
wire [1:0]  hart_instr_caught_exception;
wire [1:0]  hart_instr_caught_ebreak;

// DM system bus access (unused — tied off)
wire [31:0] sbus_addr;
wire        sbus_write;
wire [1:0]  sbus_size;
wire        sbus_vld;
wire        sbus_rdy;
wire        sbus_err;
wire [31:0] sbus_wdata;
wire [31:0] sbus_rdata;

// DM reset control
wire        sys_reset_req;
wire [1:0]  hart_reset_req;

// DMI domain reset
wire dmihardreset_req;
wire assert_dmi_reset = !rst_n || dmihardreset_req;
wire rst_n_dmi;

reset_sync dmi_reset_sync (
    .clk       (clk),
    .rst_n_in  (!assert_dmi_reset),
    .rst_n_out (rst_n_dmi)
);

// Per-core reset: external OR DM OR watchdog/reset-controller
wire assert_cpu0_reset = !rst_n || sys_reset_req || hart_reset_req[0] || !rc_cpu_rst_n[0];
wire assert_cpu1_reset = !rst_n || sys_reset_req || hart_reset_req[1] || !rc_cpu_rst_n[1];
wire rst_n_cpu0, rst_n_cpu1;

reset_sync cpu0_reset_sync (
    .clk       (clk),
    .rst_n_in  (!assert_cpu0_reset),
    .rst_n_out (rst_n_cpu0)
);

reset_sync cpu1_reset_sync (
    .clk       (clk),
    .rst_n_in  (!assert_cpu1_reset),
    .rst_n_out (rst_n_cpu1)
);

// Reset done feedback to DM
wire [1:0] hart_reset_done = {rst_n_cpu1, rst_n_cpu0};
wire       sys_reset_done  = rst_n_cpu0 & rst_n_cpu1;

// DTM: JTAG TAP → DMI APB bus
hazard3_jtag_dtm #(
    .IDCODE (32'hdeadbeef)
) dtm (
    .tck              (tck),
    .trst_n           (trst_n),
    .tms              (tms),
    .tdi              (tdi),
    .tdo              (tdo),

    .dmihardreset_req (dmihardreset_req),

    .clk_dmi          (clk),
    .rst_n_dmi        (rst_n_dmi),

    .dmi_psel         (dmi_psel),
    .dmi_penable      (dmi_penable),
    .dmi_pwrite       (dmi_pwrite),
    .dmi_paddr        (dmi_paddr),
    .dmi_pwdata       (dmi_pwdata),
    .dmi_prdata       (dmi_prdata),
    .dmi_pready       (dmi_pready),
    .dmi_pslverr      (dmi_pslverr)
);

// DM: DMI APB bus → per-hart debug signals (2 harts)
hazard3_dm #(
    .N_HARTS  (2),
    .HAVE_SBA (0)
) dm (
    .clk                         (clk),
    .rst_n                       (rst_n),

    .dmi_psel                    (dmi_psel),
    .dmi_penable                 (dmi_penable),
    .dmi_pwrite                  (dmi_pwrite),
    .dmi_paddr                   (dmi_paddr),
    .dmi_pwdata                  (dmi_pwdata),
    .dmi_prdata                  (dmi_prdata),
    .dmi_pready                  (dmi_pready),
    .dmi_pslverr                 (dmi_pslverr),

    .sys_reset_req               (sys_reset_req),
    .sys_reset_done              (sys_reset_done),
    .hart_reset_req              (hart_reset_req),
    .hart_reset_done             (hart_reset_done),

    .hart_req_halt               (hart_req_halt),
    .hart_req_halt_on_reset      (hart_req_halt_on_reset),
    .hart_req_resume             (hart_req_resume),
    .hart_halted                 (hart_halted),
    .hart_running                (hart_running),

    .hart_data0_rdata            (hart_data0_rdata),
    .hart_data0_wdata            (hart_data0_wdata),
    .hart_data0_wen              (hart_data0_wen),

    .hart_instr_data             (hart_instr_data),
    .hart_instr_data_vld         (hart_instr_data_vld),
    .hart_instr_data_rdy         (hart_instr_data_rdy),
    .hart_instr_caught_exception (hart_instr_caught_exception),
    .hart_instr_caught_ebreak    (hart_instr_caught_ebreak),

    .sbus_addr                   (sbus_addr),
    .sbus_write                  (sbus_write),
    .sbus_size                   (sbus_size),
    .sbus_vld                    (sbus_vld),
    .sbus_rdy                    (sbus_rdy),
    .sbus_err                    (sbus_err),
    .sbus_wdata                  (sbus_wdata),
    .sbus_rdata                  (sbus_rdata)
);

// ============================================================================
// PIO GPIO signals (merged from PIO0 and PIO1; PIO1 has higher priority)

wire [31:0] pio0_gpio_out, pio0_gpio_oe;
wire [31:0] pio1_gpio_out, pio1_gpio_oe;
wire [3:0]  pio0_irq, pio1_irq;
wire        uart0_irq;
wire        spi0_irq;

// Per-bit priority mux: PIO1 overrides PIO0 when PIO1 has OE
assign pio_gpio_out = (pio1_gpio_oe & pio1_gpio_out) |
                      (~pio1_gpio_oe & pio0_gpio_oe & pio0_gpio_out);
assign pio_gpio_oe  = pio0_gpio_oe | pio1_gpio_oe;
assign pio_irq      = {pio1_irq, pio0_irq};

// ============================================================================
// CPU0 — hart 0

hazard3_cpu_2port cpu0 (
    .clk           (clk),
    .clk_always_on (clk),
    .rst_n         (rst_n_cpu0),

    .pwrup_req     (),
    .pwrup_ack     (1'b1),
    .clk_en        (),
    .unblock_out   (),
    .unblock_in    (1'b0),

    .i_haddr       (cpu0_i_haddr),
    .i_hwrite      (cpu0_i_hwrite),
    .i_htrans      (cpu0_i_htrans),
    .i_hsize       (cpu0_i_hsize),
    .i_hburst      (cpu0_i_hburst),
    .i_hprot       (cpu0_i_hprot),
    .i_hmastlock   (cpu0_i_hmastlock),
    .i_hmaster     (cpu0_i_hmaster),
    .i_hready      (cpu0_i_hready),
    .i_hresp       (cpu0_i_hresp),
    .i_hwdata      (cpu0_i_hwdata),
    .i_hrdata      (cpu0_i_hrdata),

    .d_haddr       (cpu0_d_haddr),
    .d_hwrite      (cpu0_d_hwrite),
    .d_htrans      (cpu0_d_htrans),
    .d_hsize       (cpu0_d_hsize),
    .d_hburst      (cpu0_d_hburst),
    .d_hprot       (cpu0_d_hprot),
    .d_hmastlock   (cpu0_d_hmastlock),
    .d_hmaster     (cpu0_d_hmaster),
    .d_hexcl       (cpu0_d_hexcl),
    .d_hready      (cpu0_d_hready),
    .d_hresp       (cpu0_d_hresp),
    .d_hexokay     (1'b0),
    .d_hwdata      (cpu0_d_hwdata),
    .d_hrdata      (cpu0_d_hrdata),

    .fence_i_vld   (),
    .fence_d_vld   (),
    .fence_rdy     (1'b1),

    // Debug port — hart 0
    .dbg_req_halt               (hart_req_halt[0]),
    .dbg_req_halt_on_reset      (hart_req_halt_on_reset[0]),
    .dbg_req_resume             (hart_req_resume[0]),
    .dbg_halted                 (hart_halted[0]),
    .dbg_running                (hart_running[0]),
    .dbg_data0_rdata            (hart_data0_rdata[31:0]),
    .dbg_data0_wdata            (hart_data0_wdata[31:0]),
    .dbg_data0_wen              (hart_data0_wen[0]),
    .dbg_instr_data             (hart_instr_data[31:0]),
    .dbg_instr_data_vld         (hart_instr_data_vld[0]),
    .dbg_instr_data_rdy         (hart_instr_data_rdy[0]),
    .dbg_instr_caught_exception (hart_instr_caught_exception[0]),
    .dbg_instr_caught_ebreak    (hart_instr_caught_ebreak[0]),
    .dbg_sbus_addr              (sbus_addr),
    .dbg_sbus_write             (sbus_write),
    .dbg_sbus_size              (sbus_size),
    .dbg_sbus_vld               (sbus_vld),
    .dbg_sbus_rdy               (sbus_rdy),
    .dbg_sbus_err               (sbus_err),
    .dbg_sbus_wdata             (sbus_wdata),
    .dbg_sbus_rdata             (sbus_rdata),

    .mhartid_val   (32'h0),
    .eco_version    (4'h0),

    .irq           (uart0_irq | spi0_irq),
    .soft_irq      (1'b0),
    .timer_irq     (timer_irq)
);

// ============================================================================
// CPU1 — hart 1 (starts in reset; core 0 releases it via reset controller)

hazard3_cpu_2port cpu1 (
    .clk           (clk),
    .clk_always_on (clk),
    .rst_n         (rst_n_cpu1),

    .pwrup_req     (),
    .pwrup_ack     (1'b1),
    .clk_en        (),
    .unblock_out   (),
    .unblock_in    (1'b0),

    .i_haddr       (cpu1_i_haddr),
    .i_hwrite      (cpu1_i_hwrite),
    .i_htrans      (cpu1_i_htrans),
    .i_hsize       (cpu1_i_hsize),
    .i_hburst      (cpu1_i_hburst),
    .i_hprot       (cpu1_i_hprot),
    .i_hmastlock   (cpu1_i_hmastlock),
    .i_hmaster     (cpu1_i_hmaster),
    .i_hready      (cpu1_i_hready),
    .i_hresp       (cpu1_i_hresp),
    .i_hwdata      (cpu1_i_hwdata),
    .i_hrdata      (cpu1_i_hrdata),

    .d_haddr       (cpu1_d_haddr),
    .d_hwrite      (cpu1_d_hwrite),
    .d_htrans      (cpu1_d_htrans),
    .d_hsize       (cpu1_d_hsize),
    .d_hburst      (cpu1_d_hburst),
    .d_hprot       (cpu1_d_hprot),
    .d_hmastlock   (cpu1_d_hmastlock),
    .d_hmaster     (cpu1_d_hmaster),
    .d_hexcl       (cpu1_d_hexcl),
    .d_hready      (cpu1_d_hready),
    .d_hresp       (cpu1_d_hresp),
    .d_hexokay     (1'b0),
    .d_hwdata      (cpu1_d_hwdata),
    .d_hrdata      (cpu1_d_hrdata),

    .fence_i_vld   (),
    .fence_d_vld   (),
    .fence_rdy     (1'b1),

    // Debug port — hart 1
    .dbg_req_halt               (hart_req_halt[1]),
    .dbg_req_halt_on_reset      (hart_req_halt_on_reset[1]),
    .dbg_req_resume             (hart_req_resume[1]),
    .dbg_halted                 (hart_halted[1]),
    .dbg_running                (hart_running[1]),
    .dbg_data0_rdata            (hart_data0_rdata[63:32]),
    .dbg_data0_wdata            (hart_data0_wdata[63:32]),
    .dbg_data0_wen              (hart_data0_wen[1]),
    .dbg_instr_data             (hart_instr_data[63:32]),
    .dbg_instr_data_vld         (hart_instr_data_vld[1]),
    .dbg_instr_data_rdy         (hart_instr_data_rdy[1]),
    .dbg_instr_caught_exception (hart_instr_caught_exception[1]),
    .dbg_instr_caught_ebreak    (hart_instr_caught_ebreak[1]),
    // CPU1 doesn't get sbus — tie off inputs, leave outputs open
    .dbg_sbus_addr              (32'h0),    // input
    .dbg_sbus_write             (1'b0),     // input
    .dbg_sbus_size              (2'b00),    // input
    .dbg_sbus_vld               (1'b0),     // input — no sbus requests
    .dbg_sbus_rdy               (),         // output
    .dbg_sbus_err               (),         // output
    .dbg_sbus_wdata             (32'h0),    // input
    .dbg_sbus_rdata             (),         // output

    .mhartid_val   (32'h1),
    .eco_version    (4'h0),

    .irq           (uart0_irq | spi0_irq),
    .soft_irq      (1'b0),
    .timer_irq     (timer_irq)
);

// ============================================================================
// Instruction-port crossbar: 2 CPU I-ports → 2 slaves (SRAM + XIP).
// CPU0 has priority (lower index = higher priority in strict crossbar).

localparam XBAR_I_NM = 2;   // masters: CPU0-I, CPU1-I
localparam XBAR_I_NS = 2;   // slaves:  SRAM I-port, XIP flash

localparam [XBAR_I_NS*32-1:0] XBAR_I_ADDR_MAP = {
    32'h1000_0000,  // 1: XIP flash
    32'h0000_0000   // 0: SRAM
};
localparam [XBAR_I_NS*32-1:0] XBAR_I_ADDR_MASK = {
    32'hF000_0000,  // 1: XIP  (256 MB)
    32'hFFFF_0000   // 0: SRAM (64 KB)
};

// Crossbar slave-side packed buses
wire [XBAR_I_NS-1:0]      xbar_i_dst_hready;
wire [XBAR_I_NS-1:0]      xbar_i_dst_hready_resp;
wire [XBAR_I_NS-1:0]      xbar_i_dst_hresp;
wire [XBAR_I_NS*32-1:0]   xbar_i_dst_haddr;
wire [XBAR_I_NS-1:0]      xbar_i_dst_hwrite;
wire [XBAR_I_NS*2-1:0]    xbar_i_dst_htrans;
wire [XBAR_I_NS*3-1:0]    xbar_i_dst_hsize;
wire [XBAR_I_NS*3-1:0]    xbar_i_dst_hburst;
wire [XBAR_I_NS*4-1:0]    xbar_i_dst_hprot;
wire [XBAR_I_NS-1:0]      xbar_i_dst_hmastlock;
wire [XBAR_I_NS*32-1:0]   xbar_i_dst_hwdata;
wire [XBAR_I_NS*32-1:0]   xbar_i_dst_hrdata;

ahbl_crossbar_strict #(
    .N_MASTERS    (XBAR_I_NM),
    .N_SLAVES     (XBAR_I_NS),
    .ADDR_MAP     (XBAR_I_ADDR_MAP),
    .ADDR_MASK    (XBAR_I_ADDR_MASK)
) i_xbar (
    .clk              (clk),
    .rst_n            (rst_n),

    // Master 0: CPU0-I, Master 1: CPU1-I (packed: {cpu1, cpu0})
    .src_hready_resp  ({cpu1_i_hready,    cpu0_i_hready}),
    .src_hresp        ({cpu1_i_hresp,     cpu0_i_hresp}),
    .src_haddr        ({cpu1_i_haddr,     cpu0_i_haddr}),
    .src_hwrite       ({cpu1_i_hwrite,    cpu0_i_hwrite}),
    .src_htrans       ({cpu1_i_htrans,    cpu0_i_htrans}),
    .src_hsize        ({cpu1_i_hsize,     cpu0_i_hsize}),
    .src_hburst       ({cpu1_i_hburst,    cpu0_i_hburst}),
    .src_hprot        ({cpu1_i_hprot,     cpu0_i_hprot}),
    .src_hmastlock    ({cpu1_i_hmastlock, cpu0_i_hmastlock}),
    .src_hwdata       ({cpu1_i_hwdata,    cpu0_i_hwdata}),
    .src_hrdata       ({cpu1_i_hrdata,    cpu0_i_hrdata}),

    // Slave bus (packed)
    .dst_hready       (xbar_i_dst_hready),
    .dst_hready_resp  (xbar_i_dst_hready_resp),
    .dst_hresp        (xbar_i_dst_hresp),
    .dst_haddr        (xbar_i_dst_haddr),
    .dst_hwrite       (xbar_i_dst_hwrite),
    .dst_htrans       (xbar_i_dst_htrans),
    .dst_hsize        (xbar_i_dst_hsize),
    .dst_hburst       (xbar_i_dst_hburst),
    .dst_hprot        (xbar_i_dst_hprot),
    .dst_hmastlock    (xbar_i_dst_hmastlock),
    .dst_hwdata       (xbar_i_dst_hwdata),
    .dst_hrdata       (xbar_i_dst_hrdata)
);

// Unpack I-port crossbar → SRAM I-port + XIP
assign ixbar_sram_haddr  = xbar_i_dst_haddr [0*32 +: 32];
assign ixbar_sram_htrans = xbar_i_dst_htrans[0*2  +: 2];

assign ixbar_xip_haddr   = xbar_i_dst_haddr [1*32 +: 32];
assign ixbar_xip_hwrite  = xbar_i_dst_hwrite[1];
assign ixbar_xip_htrans  = xbar_i_dst_htrans[1*2  +: 2];
assign ixbar_xip_hsize   = xbar_i_dst_hsize [1*3  +: 3];
assign ixbar_xip_hwdata  = xbar_i_dst_hwdata[1*32 +: 32];

// Pack SRAM + XIP responses → crossbar
assign xbar_i_dst_hready_resp = {ixbar_xip_hready,  ixbar_sram_hready};
assign xbar_i_dst_hresp       = {ixbar_xip_hresp,   ixbar_sram_hresp};
assign xbar_i_dst_hrdata      = {ixbar_xip_hrdata,  ixbar_sram_hrdata};

// ============================================================================
// Data-port crossbar: 2 masters (CPU0-D, CPU1-D) → 11 slaves.

localparam XBAR_D_NM = 2;   // masters: CPU0-D, CPU1-D
localparam XBAR_D_NS = 11;  // slaves (10 original + SIO)

// Slave indices (must match ADDR_MAP packing order)
localparam S_SRAM = 0, S_GPIO = 1, S_PIO0 = 2, S_PIO1 = 3, S_UART0 = 4,
           S_SPI0 = 5, S_TIMER = 6, S_WDOG = 7, S_RSTC = 8, S_SYSINFO = 9,
           S_SIO = 10;

// Address map: (addr ^ MAP[i]) & MASK[i] == 0 → slave i
// Packed MSB-first: {slave10, slave9, ..., slave0}
localparam [XBAR_D_NS*32-1:0] XBAR_D_ADDR_MAP = {
    32'hD000_0000,  // 10: SIO
    32'h4005_C000,  //  9: SYSINFO
    32'h4005_4000,  //  8: RESET
    32'h4005_8000,  //  7: WATCHDOG
    32'h4005_0000,  //  6: TIMER
    32'h4003_C000,  //  5: SPI0
    32'h4003_4000,  //  4: UART0
    32'h5030_0000,  //  3: PIO1
    32'h5020_0000,  //  2: PIO0
    32'h4000_0000,  //  1: GPIO
    32'h0000_0000   //  0: SRAM
};
localparam [XBAR_D_NS*32-1:0] XBAR_D_ADDR_MASK = {
    32'hF000_F000,  // 10: SIO     (4 KB)
    32'hFFFF_C000,  //  9: SYSINFO (16 KB)
    32'hFFFF_C000,  //  8: RESET   (16 KB)
    32'hFFFF_C000,  //  7: WATCHDOG(16 KB)
    32'hFFFF_C000,  //  6: TIMER   (16 KB)
    32'hFFFF_C000,  //  5: SPI0    (16 KB)
    32'hFFFF_C000,  //  4: UART0   (16 KB)
    32'hFFF0_0000,  //  3: PIO1    (1 MB)
    32'hFFF0_0000,  //  2: PIO0    (1 MB)
    32'hFFFF_0000,  //  1: GPIO    (64 KB)
    32'hFFFF_0000   //  0: SRAM    (64 KB)
};

// Crossbar slave-side packed buses
wire [XBAR_D_NS-1:0]      xbar_d_dst_hready;
wire [XBAR_D_NS-1:0]      xbar_d_dst_hready_resp;
wire [XBAR_D_NS-1:0]      xbar_d_dst_hresp;
wire [XBAR_D_NS*32-1:0]   xbar_d_dst_haddr;
wire [XBAR_D_NS-1:0]      xbar_d_dst_hwrite;
wire [XBAR_D_NS*2-1:0]    xbar_d_dst_htrans;
wire [XBAR_D_NS*3-1:0]    xbar_d_dst_hsize;
wire [XBAR_D_NS*3-1:0]    xbar_d_dst_hburst;
wire [XBAR_D_NS*4-1:0]    xbar_d_dst_hprot;
wire [XBAR_D_NS-1:0]      xbar_d_dst_hmastlock;
wire [XBAR_D_NS*32-1:0]   xbar_d_dst_hwdata;
wire [XBAR_D_NS*32-1:0]   xbar_d_dst_hrdata;

ahbl_crossbar_strict #(
    .N_MASTERS    (XBAR_D_NM),
    .N_SLAVES     (XBAR_D_NS),
    .ADDR_MAP     (XBAR_D_ADDR_MAP),
    .ADDR_MASK    (XBAR_D_ADDR_MASK)
) d_xbar (
    .clk              (clk),
    .rst_n            (rst_n),

    // Master 0: CPU0-D, Master 1: CPU1-D (packed: {cpu1, cpu0})
    .src_hready_resp  ({cpu1_d_hready,    cpu0_d_hready}),
    .src_hresp        ({cpu1_d_hresp,     cpu0_d_hresp}),
    .src_haddr        ({cpu1_d_haddr,     cpu0_d_haddr}),
    .src_hwrite       ({cpu1_d_hwrite,    cpu0_d_hwrite}),
    .src_htrans       ({cpu1_d_htrans,    cpu0_d_htrans}),
    .src_hsize        ({cpu1_d_hsize,     cpu0_d_hsize}),
    .src_hburst       ({cpu1_d_hburst,    cpu0_d_hburst}),
    .src_hprot        ({cpu1_d_hprot,     cpu0_d_hprot}),
    .src_hmastlock    ({cpu1_d_hmastlock, cpu0_d_hmastlock}),
    .src_hwdata       ({cpu1_d_hwdata,    cpu0_d_hwdata}),
    .src_hrdata       ({cpu1_d_hrdata,    cpu0_d_hrdata}),

    // Slave bus (packed)
    .dst_hready       (xbar_d_dst_hready),
    .dst_hready_resp  (xbar_d_dst_hready_resp),
    .dst_hresp        (xbar_d_dst_hresp),
    .dst_haddr        (xbar_d_dst_haddr),
    .dst_hwrite       (xbar_d_dst_hwrite),
    .dst_htrans       (xbar_d_dst_htrans),
    .dst_hsize        (xbar_d_dst_hsize),
    .dst_hburst       (xbar_d_dst_hburst),
    .dst_hprot        (xbar_d_dst_hprot),
    .dst_hmastlock    (xbar_d_dst_hmastlock),
    .dst_hwdata       (xbar_d_dst_hwdata),
    .dst_hrdata       (xbar_d_dst_hrdata)
);

// Unpack crossbar → per-slave wires
`define XBAR_UNPACK_SLAVE(IDX, PFX) \
    assign PFX``_haddr  = xbar_d_dst_haddr [IDX*32 +: 32]; \
    assign PFX``_hwrite = xbar_d_dst_hwrite[IDX];           \
    assign PFX``_htrans = xbar_d_dst_htrans[IDX*2  +: 2];  \
    assign PFX``_hsize  = xbar_d_dst_hsize [IDX*3  +: 3];  \
    assign PFX``_hwdata = xbar_d_dst_hwdata[IDX*32 +: 32];

`XBAR_UNPACK_SLAVE(S_SRAM,    dec_sram)
`XBAR_UNPACK_SLAVE(S_GPIO,    dec_gpio)
`XBAR_UNPACK_SLAVE(S_PIO0,    dec_pio0)
`XBAR_UNPACK_SLAVE(S_PIO1,    dec_pio1)
`XBAR_UNPACK_SLAVE(S_UART0,   dec_uart0)
`XBAR_UNPACK_SLAVE(S_SPI0,    dec_spi0)
`XBAR_UNPACK_SLAVE(S_TIMER,   dec_timer)
`XBAR_UNPACK_SLAVE(S_WDOG,    dec_wdog)
`XBAR_UNPACK_SLAVE(S_RSTC,    dec_rstc)
`XBAR_UNPACK_SLAVE(S_SYSINFO, dec_sysinfo)
`XBAR_UNPACK_SLAVE(S_SIO,     dec_sio)

`undef XBAR_UNPACK_SLAVE

// Pack per-slave responses → crossbar
assign xbar_d_dst_hrdata = {
    dec_sio_hrdata,
    dec_sysinfo_hrdata, dec_rstc_hrdata,  dec_wdog_hrdata,  dec_timer_hrdata,
    dec_spi0_hrdata,    dec_uart0_hrdata, dec_pio1_hrdata,  dec_pio0_hrdata,
    dec_gpio_hrdata,    dec_sram_hrdata
};
assign xbar_d_dst_hready_resp = {
    dec_sio_hready,
    dec_sysinfo_hready, dec_rstc_hready,  dec_wdog_hready,  dec_timer_hready,
    dec_spi0_hready,    dec_uart0_hready, dec_pio1_hready,  dec_pio0_hready,
    dec_gpio_hready,    dec_sram_hready
};
assign xbar_d_dst_hresp = {
    dec_sio_hresp,
    dec_sysinfo_hresp, dec_rstc_hresp,  dec_wdog_hresp,  dec_timer_hresp,
    dec_spi0_hresp,    dec_uart0_hresp, dec_pio1_hresp,  dec_pio0_hresp,
    dec_gpio_hresp,    dec_sram_hresp
};

// ============================================================================
// XIP flash: read-only cache → SPI 03h controller

wire [31:0] cache_spi_haddr,  cache_spi_hwdata,  cache_spi_hrdata;
wire        cache_spi_hwrite, cache_spi_hready_resp;
wire [1:0]  cache_spi_htrans;
wire [2:0]  cache_spi_hsize, cache_spi_hburst;
wire [3:0]  cache_spi_hprot;
wire        cache_spi_hmastlock;
wire        cache_spi_hresp;

ahb_cache_readonly #(
    .N_WAYS (1),
    .W_LINE (32),
    .DEPTH  (256)
) xip_cache (
    .clk              (clk),
    .rst_n            (rst_n),

    .src_hready_resp  (ixbar_xip_hready),
    .src_hready       (ixbar_xip_hready),
    .src_hresp        (ixbar_xip_hresp),
    .src_haddr        (ixbar_xip_haddr),
    .src_hwrite       (ixbar_xip_hwrite),
    .src_htrans       (ixbar_xip_htrans),
    .src_hsize        (ixbar_xip_hsize),
    .src_hburst       (3'b000),
    .src_hprot        (4'b0011),
    .src_hmastlock    (1'b0),
    .src_hwdata       (ixbar_xip_hwdata),
    .src_hrdata       (ixbar_xip_hrdata),

    .dst_hready_resp  (cache_spi_hready_resp),
    .dst_hready       (),
    .dst_hresp        (cache_spi_hresp),
    .dst_haddr        (cache_spi_haddr),
    .dst_hwrite       (cache_spi_hwrite),
    .dst_htrans       (cache_spi_htrans),
    .dst_hsize        (cache_spi_hsize),
    .dst_hburst       (cache_spi_hburst),
    .dst_hprot        (cache_spi_hprot),
    .dst_hmastlock    (cache_spi_hmastlock),
    .dst_hwdata       (cache_spi_hwdata),
    .dst_hrdata       (cache_spi_hrdata)
);

spi_03h_xip xip_spi (
    .clk              (clk),
    .rst_n            (rst_n),

    .apbs_psel        (1'b0),
    .apbs_penable     (1'b0),
    .apbs_pwrite      (1'b0),
    .apbs_paddr       (16'h0),
    .apbs_pwdata      (32'h0),
    .apbs_prdata      (),
    .apbs_pready      (),
    .apbs_pslverr     (),

    .ahbls_hready_resp (cache_spi_hready_resp),
    .ahbls_hready      (cache_spi_hready_resp),
    .ahbls_hresp       (cache_spi_hresp),
    .ahbls_haddr       (cache_spi_haddr),
    .ahbls_hwrite      (cache_spi_hwrite),
    .ahbls_htrans      (cache_spi_htrans),
    .ahbls_hsize       (cache_spi_hsize),
    .ahbls_hburst      (cache_spi_hburst),
    .ahbls_hprot       (cache_spi_hprot),
    .ahbls_hmastlock   (cache_spi_hmastlock),
    .ahbls_hwdata      (cache_spi_hwdata),
    .ahbls_hrdata      (cache_spi_hrdata),

    .spi_cs_n          (spi_cs_n),
    .spi_sck           (spi_sck),
    .spi_mosi          (spi_mosi),
    .spi_miso          (spi_miso)
);

// ============================================================================
// Shared SRAM (64 KB)

sram_top mem (
    .clk       (clk),
    .i_haddr   (ixbar_sram_haddr),
    .i_htrans  (ixbar_sram_htrans),
    .i_hrdata  (ixbar_sram_hrdata),
    .i_hready  (ixbar_sram_hready),
    .i_hresp   (ixbar_sram_hresp),
    .d_haddr   (dec_sram_haddr),
    .d_hwrite  (dec_sram_hwrite),
    .d_htrans  (dec_sram_htrans),
    .d_hsize   (dec_sram_hsize),
    .d_hwdata  (dec_sram_hwdata),
    .d_hrdata  (dec_sram_hrdata),
    .d_hready  (dec_sram_hready),
    .d_hresp   (dec_sram_hresp),
    .d_hexokay (dec_sram_hexokay)
);

// ============================================================================
// GPIO peripheral

gpio gpio0 (
    .clk      (clk),
    .rst_n    (periph_rst_n[0]),
    .haddr    (dec_gpio_haddr),
    .hwrite   (dec_gpio_hwrite),
    .htrans   (dec_gpio_htrans),
    .hsize    (dec_gpio_hsize),
    .hwdata   (dec_gpio_hwdata),
    .hrdata   (dec_gpio_hrdata),
    .hready   (dec_gpio_hready),
    .hresp    (dec_gpio_hresp),
    .gpio_in  (gpio_in),
    .gpio_out (gpio_out),
    .gpio_oe  (gpio_oe)
);

// ============================================================================
// PIO0 (0x5020_0000)

pio_top pio0 (
    .clk      (clk),
    .rst_n    (periph_rst_n[1]),
    .haddr    (dec_pio0_haddr),
    .hwrite   (dec_pio0_hwrite),
    .htrans   (dec_pio0_htrans),
    .hsize    (dec_pio0_hsize),
    .hwdata   (dec_pio0_hwdata),
    .hrdata   (dec_pio0_hrdata),
    .hready   (dec_pio0_hready),
    .hresp    (dec_pio0_hresp),
    .gpio_in  (pio_gpio_in),
    .gpio_out (pio0_gpio_out),
    .gpio_oe  (pio0_gpio_oe),
    .irq_out  (pio0_irq)
);

// ============================================================================
// PIO1 (0x5030_0000)

pio_top pio1 (
    .clk      (clk),
    .rst_n    (periph_rst_n[2]),
    .haddr    (dec_pio1_haddr),
    .hwrite   (dec_pio1_hwrite),
    .htrans   (dec_pio1_htrans),
    .hsize    (dec_pio1_hsize),
    .hwdata   (dec_pio1_hwdata),
    .hrdata   (dec_pio1_hrdata),
    .hready   (dec_pio1_hready),
    .hresp    (dec_pio1_hresp),
    .gpio_in  (pio_gpio_in),
    .gpio_out (pio1_gpio_out),
    .gpio_oe  (pio1_gpio_oe),
    .irq_out  (pio1_irq)
);

// ============================================================================
// UART0 (base 0x4003_4000)

uart uart0 (
    .clk      (clk),
    .rst_n    (periph_rst_n[3]),
    .haddr    (dec_uart0_haddr),
    .hwrite   (dec_uart0_hwrite),
    .htrans   (dec_uart0_htrans),
    .hsize    (dec_uart0_hsize),
    .hwdata   (dec_uart0_hwdata),
    .hrdata   (dec_uart0_hrdata),
    .hready   (dec_uart0_hready),
    .hresp    (dec_uart0_hresp),
    .uart_tx    (uart_tx),
    .uart_rx    (uart_rx),
    .uart_rts_n (),
    .uart_cts_n (1'b0),
    .uart_tx_dreq (),
    .uart_rx_dreq (),
    .uart_irq   (uart0_irq)
);

// ============================================================================
// SPI0 (base 0x4003_C000)

spi spi0 (
    .clk      (clk),
    .rst_n    (periph_rst_n[4]),
    .haddr    (dec_spi0_haddr),
    .hwrite   (dec_spi0_hwrite),
    .htrans   (dec_spi0_htrans),
    .hsize    (dec_spi0_hsize),
    .hwdata   (dec_spi0_hwdata),
    .hrdata   (dec_spi0_hrdata),
    .hready   (dec_spi0_hready),
    .hresp    (dec_spi0_hresp),
    .spi_sclk (spi0_sclk),
    .spi_mosi (spi0_mosi),
    .spi_miso (spi0_miso),
    .spi_cs_n (spi0_cs_n),
    .spi_irq  (spi0_irq),
    .spi_dreq    (),
    .spi_dreq_tx ()
);

// ============================================================================
// Timer (base 0x4005_0000)

wire timer_irq;

timer timer0 (
    .clk       (clk),
    .rst_n     (periph_rst_n[5]),
    .haddr     (dec_timer_haddr),
    .hwrite    (dec_timer_hwrite),
    .htrans    (dec_timer_htrans),
    .hsize     (dec_timer_hsize),
    .hwdata    (dec_timer_hwdata),
    .hrdata    (dec_timer_hrdata),
    .hready    (dec_timer_hready),
    .hresp     (dec_timer_hresp),
    .dbg_halt  (1'b0),
    .timer_irq (timer_irq)
);

// ============================================================================
// Watchdog (base 0x4005_8000)

watchdog #(
    .CLK_HZ (100_000_000)
) wdog0 (
    .clk       (clk),
    .rst_n     (rst_n),
    .haddr     (dec_wdog_haddr),
    .hwrite    (dec_wdog_hwrite),
    .htrans    (dec_wdog_htrans),
    .hsize     (dec_wdog_hsize),
    .hwdata    (dec_wdog_hwdata),
    .hrdata    (dec_wdog_hrdata),
    .hready    (dec_wdog_hready),
    .hresp     (dec_wdog_hresp),
    .dbg_halt  (1'b0),
    .wdog_reset (wdog_reset_out),
    .tick_1mhz  (wdog_tick_1mhz)
);

// ============================================================================
// Reset controller (base 0x4005_4000)

reset_controller rstc0 (
    .clk         (clk),
    .por_n       (rst_n),
    .haddr       (dec_rstc_haddr),
    .hwrite      (dec_rstc_hwrite),
    .htrans      (dec_rstc_htrans),
    .hsize       (dec_rstc_hsize),
    .hwdata      (dec_rstc_hwdata),
    .hrdata      (dec_rstc_hrdata),
    .hready      (dec_rstc_hready),
    .hresp       (dec_rstc_hresp),
    .wdog_reset  (wdog_reset_out),
    .cpu_rst_n   (rc_cpu_rst_n),
    .periph_rst_n (periph_rst_n)
);

// ============================================================================
// Sysinfo (base 0x4005_C000)

sysinfo #(
    .CHIP_ID  (32'h5250_5332),   // "RPS2"
    .PLATFORM (32'h0000_0002),   // 2 = dual-core
    .GITREV   (32'h0000_0000)
) sysinfo0 (
    .clk      (clk),
    .rst_n    (rst_n),
    .haddr    (dec_sysinfo_haddr),
    .hwrite   (dec_sysinfo_hwrite),
    .htrans   (dec_sysinfo_htrans),
    .hsize    (dec_sysinfo_hsize),
    .hwdata   (dec_sysinfo_hwdata),
    .hrdata   (dec_sysinfo_hrdata),
    .hready   (dec_sysinfo_hready),
    .hresp    (dec_sysinfo_hresp)
);

// ============================================================================
// SIO — inter-core communication (base 0xD000_0000)
//
// SIO has dual AHB ports (one per core). But it's on the shared crossbar,
// so only one core can access it at a time through the crossbar port.
// For true simultaneous access, SIO would need dedicated per-core ports
// outside the crossbar. For now, single-port via crossbar is sufficient —
// the crossbar serializes concurrent accesses.
//
// TODO: For RP2040-compatible behavior, give SIO dedicated per-core ports
// bypassing the crossbar entirely.

sio sio0 (
    .clk       (clk),
    .rst_n     (rst_n),

    // Port 0 — connected to crossbar (either core can access)
    .c0_haddr  (dec_sio_haddr),
    .c0_hwrite (dec_sio_hwrite),
    .c0_htrans (dec_sio_htrans),
    .c0_hsize  (dec_sio_hsize),
    .c0_hwdata (dec_sio_hwdata),
    .c0_hrdata (dec_sio_hrdata),
    .c0_hready (dec_sio_hready),
    .c0_hresp  (dec_sio_hresp),

    // Port 1 — tied off for now (future: dedicated core 1 port)
    .c1_haddr  (32'h0),
    .c1_hwrite (1'b0),
    .c1_htrans (2'b00),
    .c1_hsize  (3'b000),
    .c1_hwdata (32'h0),
    .c1_hrdata (),
    .c1_hready (),
    .c1_hresp  ()
);

endmodule
