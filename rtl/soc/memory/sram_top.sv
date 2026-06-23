// Memory subsystem top.
// Currently a single 64 KB bank. Future milestones can add banks here
// and introduce an address decoder without touching the rest of the SoC.

`default_nettype none

module sram_top (
    input wire clk,

    // Instruction port (read only)
    input  wire [31:0] i_haddr,
    input  wire [1:0]  i_htrans,
    output wire [31:0] i_hrdata,
    output wire        i_hready,
    output wire        i_hresp,

    // Data port (read/write)
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

sram_bank bank (
    .clk       (clk),
    .i_haddr   (i_haddr),
    .i_htrans  (i_htrans),
    .i_hrdata  (i_hrdata),
    .i_hready  (i_hready),
    .i_hresp   (i_hresp),
    .d_haddr   (d_haddr),
    .d_hwrite  (d_hwrite),
    .d_htrans  (d_htrans),
    .d_hsize   (d_hsize),
    .d_hwdata  (d_hwdata),
    .d_hrdata  (d_hrdata),
    .d_hready  (d_hready),
    .d_hresp   (d_hresp),
    .d_hexokay (d_hexokay)
);

endmodule
