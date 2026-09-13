// rxpsm32 — Single-core RISC-V SoC with JTAG debug.
//
// CPU:   Hazard3 (RV32IMC), single hart
// Debug: JTAG DTM → DM → CPU debug port (RISC-V 0.13.2 debug spec)
//
// Instruction port: CPU0-I → i_dec → SRAM I port or XIP flash (via cache).
// Data port:        CPU0-D → d_dec → SRAM D port + peripherals.
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

// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
// I decoder → SRAM I port

wire [31:0] dec_isram_haddr,  dec_isram_hrdata;
wire [1:0]  dec_isram_htrans;
wire        dec_isram_hready, dec_isram_hresp;

// ----------------------------------------------------------------------------
// Decoder → SRAM D port

wire [31:0] dec_sram_haddr,  dec_sram_hwdata,  dec_sram_hrdata;
wire        dec_sram_hwrite, dec_sram_hready,  dec_sram_hresp;
wire [1:0]  dec_sram_htrans;
wire [2:0]  dec_sram_hsize;
wire        dec_sram_hexokay;

// ----------------------------------------------------------------------------
// Decoder → GPIO

wire [31:0] dec_gpio_haddr,  dec_gpio_hwdata,  dec_gpio_hrdata;
wire        dec_gpio_hwrite, dec_gpio_hready,  dec_gpio_hresp;
wire [1:0]  dec_gpio_htrans;
wire [2:0]  dec_gpio_hsize;

// ----------------------------------------------------------------------------
// Decoder → PIO0

wire [31:0] dec_pio0_haddr,  dec_pio0_hwdata,  dec_pio0_hrdata;
wire        dec_pio0_hwrite, dec_pio0_hready,  dec_pio0_hresp;
wire [1:0]  dec_pio0_htrans;
wire [2:0]  dec_pio0_hsize;

// ----------------------------------------------------------------------------
// Decoder → PIO1

wire [31:0] dec_pio1_haddr,  dec_pio1_hwdata,  dec_pio1_hrdata;
wire        dec_pio1_hwrite, dec_pio1_hready,  dec_pio1_hresp;
wire [1:0]  dec_pio1_htrans;
wire [2:0]  dec_pio1_hsize;

// ----------------------------------------------------------------------------
// Decoder → UART0

wire [31:0] dec_uart0_haddr,  dec_uart0_hwdata,  dec_uart0_hrdata;
wire        dec_uart0_hwrite, dec_uart0_hready,  dec_uart0_hresp;
wire [1:0]  dec_uart0_htrans;
wire [2:0]  dec_uart0_hsize;

// ----------------------------------------------------------------------------
// Decoder → SPI0

wire [31:0] dec_spi0_haddr,  dec_spi0_hwdata,  dec_spi0_hrdata;
wire        dec_spi0_hwrite, dec_spi0_hready,  dec_spi0_hresp;
wire [1:0]  dec_spi0_htrans;
wire [2:0]  dec_spi0_hsize;

// ----------------------------------------------------------------------------
// Decoder → TIMER

wire [31:0] dec_timer_haddr,  dec_timer_hwdata,  dec_timer_hrdata;
wire        dec_timer_hwrite, dec_timer_hready,  dec_timer_hresp;
wire [1:0]  dec_timer_htrans;
wire [2:0]  dec_timer_hsize;

// ----------------------------------------------------------------------------
// Decoder → WATCHDOG

wire [31:0] dec_wdog_haddr,  dec_wdog_hwdata,  dec_wdog_hrdata;
wire        dec_wdog_hwrite, dec_wdog_hready,  dec_wdog_hresp;
wire [1:0]  dec_wdog_htrans;
wire [2:0]  dec_wdog_hsize;

// ----------------------------------------------------------------------------
// Decoder → RESET CONTROLLER

wire [31:0] dec_rstc_haddr,  dec_rstc_hwdata,  dec_rstc_hrdata;
wire        dec_rstc_hwrite, dec_rstc_hready,  dec_rstc_hresp;
wire [1:0]  dec_rstc_htrans;
wire [2:0]  dec_rstc_hsize;

// ----------------------------------------------------------------------------
// Decoder → SYSINFO

wire [31:0] dec_sysinfo_haddr,  dec_sysinfo_hwdata,  dec_sysinfo_hrdata;
wire        dec_sysinfo_hwrite, dec_sysinfo_hready,  dec_sysinfo_hresp;
wire [1:0]  dec_sysinfo_htrans;
wire [2:0]  dec_sysinfo_hsize;

// ----------------------------------------------------------------------------
// Reset controller + watchdog signals

wire        wdog_reset_out;    // watchdog timeout pulse
wire        wdog_tick_1mhz;    // 1 MHz tick (future use)
wire        rc_cpu_rst_n;      // reset controller CPU reset output
wire [7:0]  periph_rst_n;      // per-peripheral reset outputs

// ----------------------------------------------------------------------------
// JTAG Debug: DTM → DM → CPU0

// DMI APB bus (DTM ↔ DM)
wire        dmi_psel;
wire        dmi_penable;
wire        dmi_pwrite;
wire [8:0]  dmi_paddr;
wire [31:0] dmi_pwdata;
wire [31:0] dmi_prdata;
wire        dmi_pready;
wire        dmi_pslverr;

// DM ↔ CPU0 debug signals
wire        hart_req_halt;
wire        hart_req_halt_on_reset;
wire        hart_req_resume;
wire        hart_halted;
wire        hart_running;
wire [31:0] hart_data0_rdata;
wire [31:0] hart_data0_wdata;
wire        hart_data0_wen;
wire [31:0] hart_instr_data;
wire        hart_instr_data_vld;
wire        hart_instr_data_rdy;
wire        hart_instr_caught_exception;
wire        hart_instr_caught_ebreak;

// DM system bus access (unused — tied off)
wire [31:0] sbus_addr;
wire        sbus_write;
wire [1:0]  sbus_size;
wire        sbus_vld;
wire        sbus_rdy;
wire        sbus_err;
wire [31:0] sbus_wdata;
wire [31:0] sbus_rdata;

assign sbus_rdy  = 1'b0;
assign sbus_err  = 1'b0;
assign sbus_rdata = 32'h0;

// DM reset control
wire        sys_reset_req;
wire        hart_reset_req;

// DMI domain reset: hard-reset request from TCK domain OR external reset
wire dmihardreset_req;
wire assert_dmi_reset = !rst_n || dmihardreset_req;
wire rst_n_dmi;

reset_sync dmi_reset_sync (
    .clk       (clk),
    .rst_n_in  (!assert_dmi_reset),
    .rst_n_out (rst_n_dmi)
);

// CPU reset: external reset OR DM system/hart reset request OR watchdog/reset-controller
wire assert_cpu_reset = !rst_n || sys_reset_req || hart_reset_req || !rc_cpu_rst_n;
wire rst_n_cpu;

reset_sync cpu_reset_sync (
    .clk       (clk),
    .rst_n_in  (!assert_cpu_reset),
    .rst_n_out (rst_n_cpu)
);

// Reset done feedback to DM (active-high = out of reset)
wire sys_reset_done  = rst_n_cpu;
wire hart_reset_done = rst_n_cpu;

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

// DM: DMI APB bus → per-hart debug signals
hazard3_dm #(
    .N_HARTS  (1),
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

// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
// CPU0 — single hart

hazard3_cpu_2port cpu0 (
    .clk           (clk),
    .clk_always_on (clk),
    .rst_n         (rst_n_cpu),

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

    // Debug port — wired to DM
    .dbg_req_halt               (hart_req_halt),
    .dbg_req_halt_on_reset      (hart_req_halt_on_reset),
    .dbg_req_resume             (hart_req_resume),
    .dbg_halted                 (hart_halted),
    .dbg_running                (hart_running),
    .dbg_data0_rdata            (hart_data0_rdata),
    .dbg_data0_wdata            (hart_data0_wdata),
    .dbg_data0_wen              (hart_data0_wen),
    .dbg_instr_data             (hart_instr_data),
    .dbg_instr_data_vld         (hart_instr_data_vld),
    .dbg_instr_data_rdy         (hart_instr_data_rdy),
    .dbg_instr_caught_exception (hart_instr_caught_exception),
    .dbg_instr_caught_ebreak    (hart_instr_caught_ebreak),
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

// ----------------------------------------------------------------------------
// Data-port decoder: routes CPU0-D directly to SRAM, GPIO, PIO0, PIO1, or UART0

ahb_d_decoder d_dec (
    .clk       (clk),
    .rst_n     (rst_n),

    .m_haddr   (cpu0_d_haddr),
    .m_hwrite  (cpu0_d_hwrite),
    .m_htrans  (cpu0_d_htrans),
    .m_hsize   (cpu0_d_hsize),
    .m_hwdata  (cpu0_d_hwdata),
    .m_hrdata  (cpu0_d_hrdata),
    .m_hready  (cpu0_d_hready),
    .m_hresp   (cpu0_d_hresp),

    .s0_haddr  (dec_sram_haddr),
    .s0_hwrite (dec_sram_hwrite),
    .s0_htrans (dec_sram_htrans),
    .s0_hsize  (dec_sram_hsize),
    .s0_hwdata (dec_sram_hwdata),
    .s0_hrdata (dec_sram_hrdata),
    .s0_hready (dec_sram_hready),
    .s0_hresp  (dec_sram_hresp),

    .s1_haddr  (dec_gpio_haddr),
    .s1_hwrite (dec_gpio_hwrite),
    .s1_htrans (dec_gpio_htrans),
    .s1_hsize  (dec_gpio_hsize),
    .s1_hwdata (dec_gpio_hwdata),
    .s1_hrdata (dec_gpio_hrdata),
    .s1_hready (dec_gpio_hready),
    .s1_hresp  (dec_gpio_hresp),

    .s2_haddr  (dec_pio0_haddr),
    .s2_hwrite (dec_pio0_hwrite),
    .s2_htrans (dec_pio0_htrans),
    .s2_hsize  (dec_pio0_hsize),
    .s2_hwdata (dec_pio0_hwdata),
    .s2_hrdata (dec_pio0_hrdata),
    .s2_hready (dec_pio0_hready),
    .s2_hresp  (dec_pio0_hresp),

    .s3_haddr  (dec_pio1_haddr),
    .s3_hwrite (dec_pio1_hwrite),
    .s3_htrans (dec_pio1_htrans),
    .s3_hsize  (dec_pio1_hsize),
    .s3_hwdata (dec_pio1_hwdata),
    .s3_hrdata (dec_pio1_hrdata),
    .s3_hready (dec_pio1_hready),
    .s3_hresp  (dec_pio1_hresp),

    .s4_haddr  (dec_uart0_haddr),
    .s4_hwrite (dec_uart0_hwrite),
    .s4_htrans (dec_uart0_htrans),
    .s4_hsize  (dec_uart0_hsize),
    .s4_hwdata (dec_uart0_hwdata),
    .s4_hrdata (dec_uart0_hrdata),
    .s4_hready (dec_uart0_hready),
    .s4_hresp  (dec_uart0_hresp),

    .s5_haddr  (dec_spi0_haddr),
    .s5_hwrite (dec_spi0_hwrite),
    .s5_htrans (dec_spi0_htrans),
    .s5_hsize  (dec_spi0_hsize),
    .s5_hwdata (dec_spi0_hwdata),
    .s5_hrdata (dec_spi0_hrdata),
    .s5_hready (dec_spi0_hready),
    .s5_hresp  (dec_spi0_hresp),

    .s6_haddr  (dec_timer_haddr),
    .s6_hwrite (dec_timer_hwrite),
    .s6_htrans (dec_timer_htrans),
    .s6_hsize  (dec_timer_hsize),
    .s6_hwdata (dec_timer_hwdata),
    .s6_hrdata (dec_timer_hrdata),
    .s6_hready (dec_timer_hready),
    .s6_hresp  (dec_timer_hresp),

    .s7_haddr  (dec_wdog_haddr),
    .s7_hwrite (dec_wdog_hwrite),
    .s7_htrans (dec_wdog_htrans),
    .s7_hsize  (dec_wdog_hsize),
    .s7_hwdata (dec_wdog_hwdata),
    .s7_hrdata (dec_wdog_hrdata),
    .s7_hready (dec_wdog_hready),
    .s7_hresp  (dec_wdog_hresp),

    .s8_haddr  (dec_rstc_haddr),
    .s8_hwrite (dec_rstc_hwrite),
    .s8_htrans (dec_rstc_htrans),
    .s8_hsize  (dec_rstc_hsize),
    .s8_hwdata (dec_rstc_hwdata),
    .s8_hrdata (dec_rstc_hrdata),
    .s8_hready (dec_rstc_hready),
    .s8_hresp  (dec_rstc_hresp),

    .s9_haddr  (dec_sysinfo_haddr),
    .s9_hwrite (dec_sysinfo_hwrite),
    .s9_htrans (dec_sysinfo_htrans),
    .s9_hsize  (dec_sysinfo_hsize),
    .s9_hwdata (dec_sysinfo_hwdata),
    .s9_hrdata (dec_sysinfo_hrdata),
    .s9_hready (dec_sysinfo_hready),
    .s9_hresp  (dec_sysinfo_hresp)
);

// ----------------------------------------------------------------------------
// Instruction-port decoder: routes CPU0-I to SRAM I port or XIP flash.

// i_dec s1 → XIP cache (upstream) wires
wire [31:0] dec_xip_haddr,  dec_xip_hwdata,  dec_xip_hrdata;
wire        dec_xip_hwrite, dec_xip_hready,  dec_xip_hresp;
wire [1:0]  dec_xip_htrans;
wire [2:0]  dec_xip_hsize;

ahb_i_decoder i_dec (
    .clk       (clk),
    .rst_n     (rst_n),

    .m_haddr   (cpu0_i_haddr),
    .m_hwrite  (cpu0_i_hwrite),
    .m_htrans  (cpu0_i_htrans),
    .m_hsize   (cpu0_i_hsize),
    .m_hwdata  (cpu0_i_hwdata),
    .m_hrdata  (cpu0_i_hrdata),
    .m_hready  (cpu0_i_hready),
    .m_hresp   (cpu0_i_hresp),

    // s0 → SRAM I port (read-only; hwrite/hsize/hwdata outputs unused)
    .s0_haddr  (dec_isram_haddr),
    .s0_hwrite (),
    .s0_htrans (dec_isram_htrans),
    .s0_hsize  (),
    .s0_hwdata (),
    .s0_hrdata (dec_isram_hrdata),
    .s0_hready (dec_isram_hready),
    .s0_hresp  (dec_isram_hresp),

    // s1 → XIP flash (via cache)
    .s1_haddr  (dec_xip_haddr),
    .s1_hwrite (dec_xip_hwrite),
    .s1_htrans (dec_xip_htrans),
    .s1_hsize  (dec_xip_hsize),
    .s1_hwdata (dec_xip_hwdata),
    .s1_hrdata (dec_xip_hrdata),
    .s1_hready (dec_xip_hready),
    .s1_hresp  (dec_xip_hresp)
);

// ----------------------------------------------------------------------------
// XIP flash: read-only cache → SPI 03h controller
//
// Cache: 256 × 32-bit = 1 KB, direct-mapped, 1-word lines (no burst).
// SPI: single-bit MOSI/MISO, SCK = clk/2, 03h read command, 24-bit address.

// Cache downstream → SPI controller wires
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

    // Upstream: from i_dec s1
    .src_hready_resp  (dec_xip_hready),
    .src_hready       (dec_xip_hready),
    .src_hresp        (dec_xip_hresp),
    .src_haddr        (dec_xip_haddr),
    .src_hwrite       (dec_xip_hwrite),
    .src_htrans       (dec_xip_htrans),
    .src_hsize        (dec_xip_hsize),
    .src_hburst       (3'b000),
    .src_hprot        (4'b0011),
    .src_hmastlock    (1'b0),
    .src_hwdata       (dec_xip_hwdata),
    .src_hrdata       (dec_xip_hrdata),

    // Downstream: to SPI controller
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

    // APB direct-access port — tied off (no flash programming from CPU yet)
    .apbs_psel        (1'b0),
    .apbs_penable     (1'b0),
    .apbs_pwrite      (1'b0),
    .apbs_paddr       (16'h0),
    .apbs_pwdata      (32'h0),
    .apbs_prdata      (),
    .apbs_pready      (),
    .apbs_pslverr     (),

    // AHB-Lite slave: from cache downstream
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

    // SPI pins
    .spi_cs_n          (spi_cs_n),
    .spi_sck           (spi_sck),
    .spi_mosi          (spi_mosi),
    .spi_miso          (spi_miso)
);

// ----------------------------------------------------------------------------
// Shared SRAM (64 KB)

sram_top mem (
    .clk       (clk),
    .i_haddr   (dec_isram_haddr),
    .i_htrans  (dec_isram_htrans),
    .i_hrdata  (dec_isram_hrdata),
    .i_hready  (dec_isram_hready),
    .i_hresp   (dec_isram_hresp),
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

// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
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

// ----------------------------------------------------------------------------
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
    .uart_rts_n (),         // flow control — not wired to top yet
    .uart_cts_n (1'b0),     // CTS deasserted (always clear to send)
    .uart_tx_dreq (),       // DMA request — no DMA controller yet
    .uart_rx_dreq (),
    .uart_irq   (uart0_irq)
);

// ----------------------------------------------------------------------------
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
    .spi_dreq    (),          // DMA RX request — not wired yet
    .spi_dreq_tx ()           // DMA TX request — not wired yet
);

// ----------------------------------------------------------------------------
// Timer (base 0x4005_4000)

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

// ----------------------------------------------------------------------------
// Watchdog (base 0x4005_8000)

watchdog #(
    .CLK_HZ (100_000_000)
) wdog0 (
    .clk       (clk),
    .rst_n     (rst_n),          // POR only — survives watchdog resets
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

// ----------------------------------------------------------------------------
// Reset controller (base 0x4005_4000)

reset_controller rstc0 (
    .clk         (clk),
    .por_n       (rst_n),        // POR only — raw top-level reset
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

// ----------------------------------------------------------------------------
// Sysinfo (base 0x4005_C000)

sysinfo #(
    .CHIP_ID  (32'h5250_5332),   // "RPS2"
    .PLATFORM (32'h0000_0001),   // 1 = FPGA
    .GITREV   (32'h0000_0000)
) sysinfo0 (
    .clk      (clk),
    .rst_n    (rst_n),           // POR only
    .haddr    (dec_sysinfo_haddr),
    .hwrite   (dec_sysinfo_hwrite),
    .htrans   (dec_sysinfo_htrans),
    .hsize    (dec_sysinfo_hsize),
    .hwdata   (dec_sysinfo_hwdata),
    .hrdata   (dec_sysinfo_hrdata),
    .hready   (dec_sysinfo_hready),
    .hresp    (dec_sysinfo_hresp)
);

endmodule
