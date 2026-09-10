// sysinfo.sv — Read-only system identification registers.
//
// Register map (byte offset from base):
//   0x00  CHIP_ID    [31:0]  chip identifier
//   0x04  PLATFORM   [31:0]  0=ASIC, 1=FPGA
//   0x08  GITREV     [31:0]  git commit hash (set at build time)

`default_nettype none

module sysinfo #(
    parameter [31:0] CHIP_ID  = 32'h5250_5332,  // "RPS2"
    parameter [31:0] PLATFORM = 32'h0000_0001,   // 1=FPGA
    parameter [31:0] GITREV   = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst_n,

    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] haddr,
    input  wire        hwrite,
    input  wire [1:0]  htrans,
    input  wire [2:0]  hsize,
    input  wire [31:0] hwdata,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [31:0] hrdata,
    output wire        hready,
    output wire        hresp
);

reg [3:2] reg_addr_r;

always @(posedge clk)
    reg_addr_r <= haddr[3:2];

assign hrdata = (reg_addr_r == 2'd0) ? CHIP_ID  :
                (reg_addr_r == 2'd1) ? PLATFORM :
                (reg_addr_r == 2'd2) ? GITREV   :
                                       32'h0;

assign hready = 1'b1;
assign hresp  = 1'b0;

endmodule
