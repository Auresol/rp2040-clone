// sysinfo.sv — Read-only system identification registers.
//
// Base address: caller-defined (decoder handles base; offsets below are relative).
//
// Register map (byte offset from base):
//   0x00  CHIP_ID    [31:0]  chip identifier (default 0x52505332 = "RPS2")
//   0x04  PLATFORM   [31:0]  target platform
//                              0 = ASIC
//                              1 = FPGA
//   0x08  GITREV     [31:0]  git commit hash, baked in at synthesis time
//
// All registers are read-only; writes are silently ignored.
// Values are set via module parameters at instantiation.
//
// Not implemented (RP2040 sysinfo has additional registers):
//   0x00  CHIP_ID    — RP2040 uses [31:28]=REVISION, [27:12]=PART, [11:0]=MANUFACTURER
//                      (our CHIP_ID is a flat 32-bit constant instead)
//   0x40  GITREF_RP2040 — RP2040 ROM git revision (we use GITREV for RTL commit)
//   0x0C+ various    — RP2040 package info, die info not applicable to custom ASIC

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
