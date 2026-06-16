// Minimal SoC: single Hazard3 core + 64KB SRAM
// Both I and D ports share the same SRAM (no crossbar yet)
// Debug signals are tied off — no debugger in this milestone

`default_nettype none

module rvsoc_top (
    input wire clk,
    input wire rst_n
);

// ----------------------------------------------------------------------------
// Parameters

localparam W_ADDR = 32;
localparam W_DATA = 32;
localparam SRAM_DEPTH = 16384; // 64KB (16K x 32-bit words)
localparam SRAM_BASE  = 32'h0000_0000;

// ----------------------------------------------------------------------------
// AHB signals — instruction port

wire [W_ADDR-1:0] i_haddr;
wire              i_hwrite;
wire [1:0]        i_htrans;
wire [2:0]        i_hsize;
wire [2:0]        i_hburst;
wire [3:0]        i_hprot;
wire              i_hmastlock;
wire [7:0]        i_hmaster;
wire              i_hready;
wire              i_hresp;
wire [W_DATA-1:0] i_hwdata;
wire [W_DATA-1:0] i_hrdata;

// AHB signals — data port

wire [W_ADDR-1:0] d_haddr;
wire              d_hwrite;
wire [1:0]        d_htrans;
wire [2:0]        d_hsize;
wire [2:0]        d_hburst;
wire [3:0]        d_hprot;
wire              d_hmastlock;
wire [7:0]        d_hmaster;
wire              d_hexcl;
wire              d_hready;
wire              d_hresp;
wire              d_hexokay;
wire [W_DATA-1:0] d_hwdata;
wire [W_DATA-1:0] d_hrdata;

// ----------------------------------------------------------------------------
// Hazard3 CPU

hazard3_cpu_2port #(
    `include "hazard3_config_inst.vh"
) cpu (
    .clk              (clk),
    .clk_always_on    (clk),
    .rst_n            (rst_n),

    // Power — tie off (always on)
    .pwrup_req        (),
    .pwrup_ack        (1'b1),
    .clk_en           (),
    .unblock_out      (),
    .unblock_in       (1'b0),

    // Instruction port
    .i_haddr          (i_haddr),
    .i_hwrite         (i_hwrite),
    .i_htrans         (i_htrans),
    .i_hsize          (i_hsize),
    .i_hburst         (i_hburst),
    .i_hprot          (i_hprot),
    .i_hmastlock      (i_hmastlock),
    .i_hmaster        (i_hmaster),
    .i_hready         (i_hready),
    .i_hresp          (i_hresp),
    .i_hwdata         (i_hwdata),
    .i_hrdata         (i_hrdata),

    // Data port
    .d_haddr          (d_haddr),
    .d_hwrite         (d_hwrite),
    .d_htrans         (d_htrans),
    .d_hsize          (d_hsize),
    .d_hburst         (d_hburst),
    .d_hprot          (d_hprot),
    .d_hmastlock      (d_hmastlock),
    .d_hmaster        (d_hmaster),
    .d_hexcl          (d_hexcl),
    .d_hready         (d_hready),
    .d_hresp          (d_hresp),
    .d_hexokay        (d_hexokay),
    .d_hwdata         (d_hwdata),
    .d_hrdata         (d_hrdata),

    // Memory ordering
    .fence_i_vld      (),
    .fence_d_vld      (),
    .fence_rdy        (1'b1),

    // Debug — tied off
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

    // Hart ID
    .mhartid_val      (32'h0),
    .eco_version       (4'h0),

    // Interrupts — tied off
    .irq              (32'h0),
    .soft_irq         (1'b0),
    .timer_irq        (1'b0)
);

// ----------------------------------------------------------------------------
// Shared SRAM
// Both I and D ports get their own read data; D port wins on write conflict.
// Simple priority: D port has write access; I port is read-only.

reg [W_DATA-1:0] sram [0:SRAM_DEPTH-1];

// Instruction port — read only, 1-cycle latency
wire [13:0] i_word_addr = i_haddr[15:2];
reg  [W_DATA-1:0] i_hrdata_r;

always @(posedge clk)
    i_hrdata_r <= sram[i_word_addr];

assign i_hrdata = i_hrdata_r;
assign i_hready = 1'b1;
assign i_hresp  = 1'b0;

// Data port — read/write, 1-cycle latency
wire [13:0] d_word_addr = d_haddr[15:2];
wire        d_active    = (d_htrans[1] == 1'b1); // NONSEQ or SEQ

reg [W_DATA-1:0] d_hrdata_r;

// Write enables per byte lane
wire [3:0] d_wstrb = (d_hsize == 3'b000) ? (4'b0001 << d_haddr[1:0]) :
                     (d_hsize == 3'b001) ? (4'b0011 << d_haddr[1:0]) :
                                            4'b1111;

always @(posedge clk) begin
    if (d_active && d_hwrite) begin
        if (d_wstrb[0]) sram[d_word_addr][ 7: 0] <= d_hwdata[ 7: 0];
        if (d_wstrb[1]) sram[d_word_addr][15: 8] <= d_hwdata[15: 8];
        if (d_wstrb[2]) sram[d_word_addr][23:16] <= d_hwdata[23:16];
        if (d_wstrb[3]) sram[d_word_addr][31:24] <= d_hwdata[31:24];
    end
    d_hrdata_r <= sram[d_word_addr];
end

assign d_hrdata  = d_hrdata_r;
assign d_hready  = 1'b1;
assign d_hresp   = 1'b0;
assign d_hexokay = 1'b0;

// ----------------------------------------------------------------------------
// SRAM initialisation from hex file (simulation only)

initial begin
    $readmemh("sim/sw/hello.hex", sram);
end

endmodule
