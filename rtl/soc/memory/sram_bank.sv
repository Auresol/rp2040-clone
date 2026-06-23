// Single SRAM bank with separate instruction (read-only) and data (read/write)
// AHB-Lite ports. Extracted from rvsoc_top for the dual-core milestone.
//
// Write-first semantics on the data port: blocking assignments update the
// array before the registered read evaluates, so back-to-back sw/lw to the
// same address returns the new value (required by RISC-V hart ordering).

`default_nettype none

module sram_bank #(
    parameter DEPTH = 16384  // words; default = 64 KB (16K × 32-bit)
) (
    input wire clk,

    // Instruction port — read only, 1-cycle latency
    input  wire [31:0] i_haddr,
    input  wire [1:0]  i_htrans,
    output wire [31:0] i_hrdata,
    output wire        i_hready,
    output wire        i_hresp,

    // Data port — read/write, 1-cycle latency
    input  wire [31:0] d_haddr,
    input  wire        d_hwrite,
    input  wire [1:0]  d_htrans,
    input  wire [2:0]  d_hsize,
    input  wire [31:0] d_hwdata,
    output wire [31:0] d_hrdata,
    output wire        d_hready,
    output wire        d_hresp,
    output wire        d_hexokay
);

localparam AW = 14;  // log2(16384) — update if DEPTH changes

reg [31:0] sram [0:DEPTH-1] /* verilator public */;

// ----------------------------------------------------------------------------
// Instruction port

wire [AW-1:0] i_word_addr = i_haddr[AW+1:2];
reg  [31:0]   i_hrdata_r;

always @(posedge clk)
    i_hrdata_r <= sram[i_word_addr];

assign i_hrdata = i_hrdata_r;
assign i_hready = 1'b1;
assign i_hresp  = 1'b0;

// ----------------------------------------------------------------------------
// Data port

wire [AW-1:0] d_word_addr = d_haddr[AW+1:2];
wire          d_active     = d_htrans[1];

// Byte-enable strobes derived from hsize and address offset
wire [3:0] d_wstrb = (d_hsize == 3'b000) ? (4'b0001 << d_haddr[1:0]) :
                     (d_hsize == 3'b001) ? (4'b0011 << d_haddr[1:0]) :
                                            4'b1111;

// AHB pipeline: register address-phase signals so they are valid alongside
// hwdata in the following (data) cycle.
reg [AW-1:0] d_word_addr_r;
reg          d_hwrite_r;
reg          d_active_r;
reg [3:0]    d_wstrb_r;

always @(posedge clk) begin
    d_word_addr_r <= d_word_addr;
    d_hwrite_r    <= d_hwrite;
    d_active_r    <= d_active;
    d_wstrb_r     <= d_wstrb;
end

reg [31:0] d_hrdata_r;

always @(posedge clk) begin
    // Blocking = updates the array immediately so the read below sees the
    // new value when write and read target the same word (write-first).
    if (d_active_r && d_hwrite_r) begin
        if (d_wstrb_r[0]) sram[d_word_addr_r][ 7: 0] = d_hwdata[ 7: 0];
        if (d_wstrb_r[1]) sram[d_word_addr_r][15: 8] = d_hwdata[15: 8];
        if (d_wstrb_r[2]) sram[d_word_addr_r][23:16] = d_hwdata[23:16];
        if (d_wstrb_r[3]) sram[d_word_addr_r][31:24] = d_hwdata[31:24];
    end
    d_hrdata_r <= sram[d_word_addr];
end

assign d_hrdata  = d_hrdata_r;
assign d_hready  = 1'b1;
assign d_hresp   = 1'b0;
assign d_hexokay = 1'b0;  // exclusive access not supported

endmodule
