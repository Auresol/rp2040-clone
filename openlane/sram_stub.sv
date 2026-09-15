// sram_stub.sv — Stub replacement for sram_bank in OpenLane synthesis.
//
// Same ports as sram_bank, all outputs tied to constants.
// Lets Yosys synthesize the SoC without a real SRAM macro.
// Area/timing numbers will NOT reflect actual SRAM — fine for logic sizing.

module sram_bank #(
    parameter DEPTH = 16384
) (
    input wire clk,

    // Instruction port
    input  wire [31:0] i_haddr,
    input  wire [1:0]  i_htrans,
    output wire [31:0] i_hrdata,
    output wire        i_hready,
    output wire        i_hresp,

    // Data port
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

assign i_hrdata  = 32'h0;
assign i_hready  = 1'b1;
assign i_hresp   = 1'b0;

assign d_hrdata  = 32'h0;
assign d_hready  = 1'b1;
assign d_hresp   = 1'b0;
assign d_hexokay = 1'b0;

endmodule
