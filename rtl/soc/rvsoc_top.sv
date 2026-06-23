// Dual-core SoC with bus fabric.
//
// Instruction port: both CPUs share i_arb → i_dec → SRAM I port.
// Data port: both CPUs share d_arb → d_dec → SRAM D port or GPIO.
//
// Address map (data port):
//   0x0000_0000 – 0x0000_FFFF  →  SRAM  (64 KB)
//   0x4000_0000 – 0x4000_FFFF  →  GPIO  (32-bit output register)
//
// Debug and interrupt inputs are tied off — no debugger in this milestone.

`default_nettype none

module rvsoc_top (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] gpio_out
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

// ----------------------------------------------------------------------------
// Arbitrated I bus (i_arb → i_dec)

wire [31:0] arb_i_haddr,  arb_i_hwdata,  arb_i_hrdata;
wire        arb_i_hwrite, arb_i_hready,  arb_i_hresp;
wire [1:0]  arb_i_htrans;
wire [2:0]  arb_i_hsize,  arb_i_hburst;
wire [3:0]  arb_i_hprot;
wire        arb_i_hmastlock;
wire [7:0]  arb_i_hmaster;

// ----------------------------------------------------------------------------
// I decoder → SRAM I port

wire [31:0] dec_isram_haddr,  dec_isram_hrdata;
wire [1:0]  dec_isram_htrans;
wire        dec_isram_hready, dec_isram_hresp;

// ----------------------------------------------------------------------------
// Arbitrated D bus (d_arb → d_dec)

wire [31:0] arb_d_haddr,  arb_d_hwdata,  arb_d_hrdata;
wire        arb_d_hwrite, arb_d_hready,  arb_d_hresp;
wire [1:0]  arb_d_htrans;
wire [2:0]  arb_d_hsize,  arb_d_hburst;
wire [3:0]  arb_d_hprot;
wire        arb_d_hmastlock;
wire [7:0]  arb_d_hmaster;

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
// CPU0 — hart 0

hazard3_cpu_2port cpu0 (
    .clk           (clk),
    .clk_always_on (clk),
    .rst_n         (rst_n),

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

    .dbg_req_halt          (1'b0),
    .dbg_req_halt_on_reset (1'b0),
    .dbg_req_resume        (1'b0),
    .dbg_halted            (),
    .dbg_running           (),
    .dbg_data0_rdata       (32'h0),
    .dbg_data0_wdata       (),
    .dbg_data0_wen         (),
    .dbg_instr_data        (32'h0),
    .dbg_instr_data_vld    (1'b0),
    .dbg_instr_data_rdy    (),
    .dbg_instr_caught_exception (),
    .dbg_instr_caught_ebreak    (),
    .dbg_sbus_addr         (32'h0),
    .dbg_sbus_write        (1'b0),
    .dbg_sbus_size         (2'h0),
    .dbg_sbus_vld          (1'b0),
    .dbg_sbus_rdy          (),
    .dbg_sbus_err          (),
    .dbg_sbus_wdata        (32'h0),
    .dbg_sbus_rdata        (),

    .mhartid_val   (32'h0),
    .eco_version    (4'h0),

    .irq           (1'b0),
    .soft_irq      (1'b0),
    .timer_irq     (1'b0)
);

// ----------------------------------------------------------------------------
// CPU1 — hart 1

hazard3_cpu_2port cpu1 (
    .clk           (clk),
    .clk_always_on (clk),
    .rst_n         (rst_n),

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

    .dbg_req_halt          (1'b0),
    .dbg_req_halt_on_reset (1'b0),
    .dbg_req_resume        (1'b0),
    .dbg_halted            (),
    .dbg_running           (),
    .dbg_data0_rdata       (32'h0),
    .dbg_data0_wdata       (),
    .dbg_data0_wen         (),
    .dbg_instr_data        (32'h0),
    .dbg_instr_data_vld    (1'b0),
    .dbg_instr_data_rdy    (),
    .dbg_instr_caught_exception (),
    .dbg_instr_caught_ebreak    (),
    .dbg_sbus_addr         (32'h0),
    .dbg_sbus_write        (1'b0),
    .dbg_sbus_size         (2'h0),
    .dbg_sbus_vld          (1'b0),
    .dbg_sbus_rdy          (),
    .dbg_sbus_err          (),
    .dbg_sbus_wdata        (32'h0),
    .dbg_sbus_rdata        (),

    .mhartid_val   (32'h1),
    .eco_version    (4'h0),

    .irq           (1'b0),
    .soft_irq      (1'b0),
    .timer_irq     (1'b0)
);

// ----------------------------------------------------------------------------
// Instruction-port arbiter: CPU0-I (M0, priority) vs CPU1-I (M1)

ahb_arbiter i_arb (
    .clk          (clk),
    .rst_n        (rst_n),

    .m0_haddr     (cpu0_i_haddr),
    .m0_hwrite    (cpu0_i_hwrite),
    .m0_htrans    (cpu0_i_htrans),
    .m0_hsize     (cpu0_i_hsize),
    .m0_hburst    (cpu0_i_hburst),
    .m0_hprot     (cpu0_i_hprot),
    .m0_hmastlock (cpu0_i_hmastlock),
    .m0_hmaster   (cpu0_i_hmaster),
    .m0_hwdata    (cpu0_i_hwdata),
    .m0_hrdata    (cpu0_i_hrdata),
    .m0_hready    (cpu0_i_hready),
    .m0_hresp     (cpu0_i_hresp),

    .m1_haddr     (cpu1_i_haddr),
    .m1_hwrite    (cpu1_i_hwrite),
    .m1_htrans    (cpu1_i_htrans),
    .m1_hsize     (cpu1_i_hsize),
    .m1_hburst    (cpu1_i_hburst),
    .m1_hprot     (cpu1_i_hprot),
    .m1_hmastlock (cpu1_i_hmastlock),
    .m1_hmaster   (cpu1_i_hmaster),
    .m1_hwdata    (cpu1_i_hwdata),
    .m1_hrdata    (cpu1_i_hrdata),
    .m1_hready    (cpu1_i_hready),
    .m1_hresp     (cpu1_i_hresp),

    .s_haddr      (arb_i_haddr),
    .s_hwrite     (arb_i_hwrite),
    .s_htrans     (arb_i_htrans),
    .s_hsize      (arb_i_hsize),
    .s_hburst     (arb_i_hburst),
    .s_hprot      (arb_i_hprot),
    .s_hmastlock  (arb_i_hmastlock),
    .s_hmaster    (arb_i_hmaster),
    .s_hwdata     (arb_i_hwdata),
    .s_hrdata     (arb_i_hrdata),
    .s_hready     (arb_i_hready),
    .s_hresp      (arb_i_hresp)
);

// ----------------------------------------------------------------------------
// Data-port arbiter: CPU0-D (M0, priority) vs CPU1-D (M1)

ahb_arbiter d_arb (
    .clk          (clk),
    .rst_n        (rst_n),

    .m0_haddr     (cpu0_d_haddr),
    .m0_hwrite    (cpu0_d_hwrite),
    .m0_htrans    (cpu0_d_htrans),
    .m0_hsize     (cpu0_d_hsize),
    .m0_hburst    (cpu0_d_hburst),
    .m0_hprot     (cpu0_d_hprot),
    .m0_hmastlock (cpu0_d_hmastlock),
    .m0_hmaster   (cpu0_d_hmaster),
    .m0_hwdata    (cpu0_d_hwdata),
    .m0_hrdata    (cpu0_d_hrdata),
    .m0_hready    (cpu0_d_hready),
    .m0_hresp     (cpu0_d_hresp),

    .m1_haddr     (cpu1_d_haddr),
    .m1_hwrite    (cpu1_d_hwrite),
    .m1_htrans    (cpu1_d_htrans),
    .m1_hsize     (cpu1_d_hsize),
    .m1_hburst    (cpu1_d_hburst),
    .m1_hprot     (cpu1_d_hprot),
    .m1_hmastlock (cpu1_d_hmastlock),
    .m1_hmaster   (cpu1_d_hmaster),
    .m1_hwdata    (cpu1_d_hwdata),
    .m1_hrdata    (cpu1_d_hrdata),
    .m1_hready    (cpu1_d_hready),
    .m1_hresp     (cpu1_d_hresp),

    .s_haddr      (arb_d_haddr),
    .s_hwrite     (arb_d_hwrite),
    .s_htrans     (arb_d_htrans),
    .s_hsize      (arb_d_hsize),
    .s_hburst     (arb_d_hburst),
    .s_hprot      (arb_d_hprot),
    .s_hmastlock  (arb_d_hmastlock),
    .s_hmaster    (arb_d_hmaster),
    .s_hwdata     (arb_d_hwdata),
    .s_hrdata     (arb_d_hrdata),
    .s_hready     (arb_d_hready),
    .s_hresp      (arb_d_hresp)
);

// ----------------------------------------------------------------------------
// Data-port decoder: routes d_arb output to SRAM or GPIO by address

ahb_decoder d_dec (
    .clk       (clk),
    .rst_n     (rst_n),

    .m_haddr   (arb_d_haddr),
    .m_hwrite  (arb_d_hwrite),
    .m_htrans  (arb_d_htrans),
    .m_hsize   (arb_d_hsize),
    .m_hwdata  (arb_d_hwdata),
    .m_hrdata  (arb_d_hrdata),
    .m_hready  (arb_d_hready),
    .m_hresp   (arb_d_hresp),

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
    .s1_hresp  (dec_gpio_hresp)
);

// ----------------------------------------------------------------------------
// Instruction-port decoder: routes i_arb output to SRAM I port (s0).
// s1 is reserved for future fetch targets (e.g. ROM); tied off for now.

ahb_decoder i_dec (
    .clk       (clk),
    .rst_n     (rst_n),

    .m_haddr   (arb_i_haddr),
    .m_hwrite  (arb_i_hwrite),
    .m_htrans  (arb_i_htrans),
    .m_hsize   (arb_i_hsize),
    .m_hwdata  (arb_i_hwdata),
    .m_hrdata  (arb_i_hrdata),
    .m_hready  (arb_i_hready),
    .m_hresp   (arb_i_hresp),

    // s0 → SRAM I port (read-only; hwrite/hsize/hwdata outputs unused)
    .s0_haddr  (dec_isram_haddr),
    .s0_hwrite (),
    .s0_htrans (dec_isram_htrans),
    .s0_hsize  (),
    .s0_hwdata (),
    .s0_hrdata (dec_isram_hrdata),
    .s0_hready (dec_isram_hready),
    .s0_hresp  (dec_isram_hresp),

    // s1 → reserved, tied off
    .s1_haddr  (),
    .s1_hwrite (),
    .s1_htrans (),
    .s1_hsize  (),
    .s1_hwdata (),
    .s1_hrdata (32'h0),
    .s1_hready (1'b1),
    .s1_hresp  (1'b0)
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
    .rst_n    (rst_n),
    .haddr    (dec_gpio_haddr),
    .hwrite   (dec_gpio_hwrite),
    .htrans   (dec_gpio_htrans),
    .hwdata   (dec_gpio_hwdata),
    .hrdata   (dec_gpio_hrdata),
    .hready   (dec_gpio_hready),
    .hresp    (dec_gpio_hresp),
    .gpio_out (gpio_out)
);

endmodule
