// sram_top.sv — 4-bank SRAM subsystem (64 KB total).
//
// Four banks of 16 KB each.
// Instruction port: single AHB-Lite interface, internally muxed by addr[15:14].
// Data ports: 4 separate AHB-Lite interfaces (one per bank), intended for
//   direct connection to crossbar slaves so different masters can access
//   different banks simultaneously without contention.

`default_nettype none

module sram_top (
    input wire clk,

    // Instruction port — single, internally bank-muxed (read only)
    input  wire [31:0] i_haddr,
    input  wire [1:0]  i_htrans,
    output wire [31:0] i_hrdata,
    output wire        i_hready,
    output wire        i_hresp,

    // Data port — bank 0 (0x0000–0x3FFF)
    input  wire [31:0] d0_haddr,
    input  wire        d0_hwrite,
    input  wire [1:0]  d0_htrans,
    input  wire [2:0]  d0_hsize,
    input  wire [31:0] d0_hwdata,
    output wire [31:0] d0_hrdata,
    output wire        d0_hready,
    output wire        d0_hresp,
    output wire        d0_hexokay,

    // Data port — bank 1 (0x4000–0x7FFF)
    input  wire [31:0] d1_haddr,
    input  wire        d1_hwrite,
    input  wire [1:0]  d1_htrans,
    input  wire [2:0]  d1_hsize,
    input  wire [31:0] d1_hwdata,
    output wire [31:0] d1_hrdata,
    output wire        d1_hready,
    output wire        d1_hresp,
    output wire        d1_hexokay,

    // Data port — bank 2 (0x8000–0xBFFF)
    input  wire [31:0] d2_haddr,
    input  wire        d2_hwrite,
    input  wire [1:0]  d2_htrans,
    input  wire [2:0]  d2_hsize,
    input  wire [31:0] d2_hwdata,
    output wire [31:0] d2_hrdata,
    output wire        d2_hready,
    output wire        d2_hresp,
    output wire        d2_hexokay,

    // Data port — bank 3 (0xC000–0xFFFF)
    input  wire [31:0] d3_haddr,
    input  wire        d3_hwrite,
    input  wire [1:0]  d3_htrans,
    input  wire [2:0]  d3_hsize,
    input  wire [31:0] d3_hwdata,
    output wire [31:0] d3_hrdata,
    output wire        d3_hready,
    output wire        d3_hresp,
    output wire        d3_hexokay
);

localparam N_BANKS    = 4;
localparam BANK_DEPTH = 4096;  // 4096 words × 32-bit = 16 KB per bank

// -------------------------------------------------------------------------
// I-port bank select: addr[15:14] picks 1 of 4 banks

wire [1:0] i_bank_sel = i_haddr[15:14];

// Register bank select for data-phase read mux (AHB pipeline)
reg [1:0] i_bank_sel_r;
always @(posedge clk)
    i_bank_sel_r <= i_bank_sel;

// -------------------------------------------------------------------------
// Per-bank I-port read data

wire [31:0] bank_i_hrdata [0:N_BANKS-1];

// -------------------------------------------------------------------------
// Per-bank D-port signal arrays (wired from top-level ports)

wire [31:0] d_haddr  [0:N_BANKS-1];
wire        d_hwrite [0:N_BANKS-1];
wire [1:0]  d_htrans [0:N_BANKS-1];
wire [2:0]  d_hsize  [0:N_BANKS-1];
wire [31:0] d_hwdata [0:N_BANKS-1];
wire [31:0] d_hrdata [0:N_BANKS-1];
wire        d_hready [0:N_BANKS-1];
wire        d_hresp  [0:N_BANKS-1];
wire        d_hexokay[0:N_BANKS-1];

// Map individual ports to arrays
assign d_haddr[0]  = d0_haddr;   assign d_hwrite[0] = d0_hwrite;
assign d_htrans[0] = d0_htrans;  assign d_hsize[0]  = d0_hsize;
assign d_hwdata[0] = d0_hwdata;
assign d0_hrdata   = d_hrdata[0]; assign d0_hready  = d_hready[0];
assign d0_hresp    = d_hresp[0];  assign d0_hexokay = d_hexokay[0];

assign d_haddr[1]  = d1_haddr;   assign d_hwrite[1] = d1_hwrite;
assign d_htrans[1] = d1_htrans;  assign d_hsize[1]  = d1_hsize;
assign d_hwdata[1] = d1_hwdata;
assign d1_hrdata   = d_hrdata[1]; assign d1_hready  = d_hready[1];
assign d1_hresp    = d_hresp[1];  assign d1_hexokay = d_hexokay[1];

assign d_haddr[2]  = d2_haddr;   assign d_hwrite[2] = d2_hwrite;
assign d_htrans[2] = d2_htrans;  assign d_hsize[2]  = d2_hsize;
assign d_hwdata[2] = d2_hwdata;
assign d2_hrdata   = d_hrdata[2]; assign d2_hready  = d_hready[2];
assign d2_hresp    = d_hresp[2];  assign d2_hexokay = d_hexokay[2];

assign d_haddr[3]  = d3_haddr;   assign d_hwrite[3] = d3_hwrite;
assign d_htrans[3] = d3_htrans;  assign d_hsize[3]  = d3_hsize;
assign d_hwdata[3] = d3_hwdata;
assign d3_hrdata   = d_hrdata[3]; assign d3_hready  = d_hready[3];
assign d3_hresp    = d_hresp[3];  assign d3_hexokay = d_hexokay[3];

// -------------------------------------------------------------------------
// Instantiate 4 banks

genvar gi;
generate
    for (gi = 0; gi < N_BANKS; gi = gi + 1) begin : gen_banks
        // I-port: gate htrans so only the selected bank sees an active transfer
        wire [1:0] bank_i_htrans = (i_bank_sel == gi[1:0]) ? i_htrans : 2'b00;

        sram_bank #(
            .DEPTH (BANK_DEPTH)
        ) bank (
            .clk       (clk),

            // I-port: shared, bank-selected
            .i_haddr   (i_haddr),
            .i_htrans  (bank_i_htrans),
            .i_hrdata  (bank_i_hrdata[gi]),
            .i_hready  (),
            .i_hresp   (),

            // D-port: direct from crossbar
            .d_haddr   (d_haddr[gi]),
            .d_hwrite  (d_hwrite[gi]),
            .d_htrans  (d_htrans[gi]),
            .d_hsize   (d_hsize[gi]),
            .d_hwdata  (d_hwdata[gi]),
            .d_hrdata  (d_hrdata[gi]),
            .d_hready  (d_hready[gi]),
            .d_hresp   (d_hresp[gi]),
            .d_hexokay (d_hexokay[gi])
        );
    end
endgenerate

// -------------------------------------------------------------------------
// I-port data-phase read mux

assign i_hrdata = bank_i_hrdata[i_bank_sel_r];
assign i_hready = 1'b1;
assign i_hresp  = 1'b0;

endmodule
