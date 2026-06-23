// Dual-core SoC: two Hazard3 cores sharing one 64 KB SRAM.
//
// Each core has independent I (fetch) and D (load/store) AHB ports.
// Two ahb_arbiter instances serialize competing accesses:
//   i_arb — CPU0-I vs CPU1-I  →  SRAM instruction port
//   d_arb — CPU0-D vs CPU1-D  →  SRAM data port
//
// CPU0 has priority in both arbiters. CPU1 stalls (hready=0) whenever
// CPU0 holds the bus.
//
// Debug and interrupt inputs are tied off — no debugger in this milestone.

`default_nettype none

module rvsoc_top (
    input wire clk,
    input wire rst_n
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
wire        cpu0_d_hexcl;   // exclusive access — not used, tie off below

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
// Arbitrated bus signals (arbiter → SRAM)

wire [31:0] arb_i_haddr,  arb_i_hwdata,  arb_i_hrdata;
wire        arb_i_hwrite, arb_i_hready,  arb_i_hresp;
wire [1:0]  arb_i_htrans;
wire [2:0]  arb_i_hsize,  arb_i_hburst;
wire [3:0]  arb_i_hprot;
wire        arb_i_hmastlock;
wire [7:0]  arb_i_hmaster;

wire [31:0] arb_d_haddr,  arb_d_hwdata,  arb_d_hrdata;
wire        arb_d_hwrite, arb_d_hready,  arb_d_hresp;
wire [1:0]  arb_d_htrans;
wire [2:0]  arb_d_hsize,  arb_d_hburst;
wire [3:0]  arb_d_hprot;
wire        arb_d_hmastlock;
wire [7:0]  arb_d_hmaster;
wire        arb_d_hexokay;

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
// Shared SRAM (64 KB)

sram_top mem (
    .clk       (clk),
    .i_haddr   (arb_i_haddr),
    .i_htrans  (arb_i_htrans),
    .i_hrdata  (arb_i_hrdata),
    .i_hready  (arb_i_hready),
    .i_hresp   (arb_i_hresp),
    .d_haddr   (arb_d_haddr),
    .d_hwrite  (arb_d_hwrite),
    .d_htrans  (arb_d_htrans),
    .d_hsize   (arb_d_hsize),
    .d_hwdata  (arb_d_hwdata),
    .d_hrdata  (arb_d_hrdata),
    .d_hready  (arb_d_hready),
    .d_hresp   (arb_d_hresp),
    .d_hexokay (arb_d_hexokay)
);

endmodule
