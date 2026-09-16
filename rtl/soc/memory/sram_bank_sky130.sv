// sram_bank_sky130.sv — ASIC SRAM bank using sky130 PDK macros.
//
// Drop-in replacement for sram_bank.sv (simulation version).
// Same module name `sram_bank`, same ports.
//
// Internally instantiates 8 × sky130_sram_2kbyte_1rw1r_32x512_8 macros:
//   - Port 0 (RW) → data port (D-bus read/write)
//   - Port 1 (R)  → instruction port (I-bus read-only)
//
// Address mapping (within bank, 12-bit word address for 16KB):
//   addr[11:9]  — macro select (1-of-8)
//   addr[8:0]   — word within macro (512 words)
//
// AHB pipeline: address phase registers captured at posedge clk,
// data phase operates on registered values next cycle.
// Write-first forwarding: identical to simulation sram_bank.sv.

`default_nettype none

module sram_bank #(
    parameter DEPTH = 4096  // words (must be 4096 for 8 × 512-word macros)
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

localparam AW       = $clog2(DEPTH);  // 12 for DEPTH=4096
localparam N_MACROS = 8;
localparam MACRO_AW = 9;              // 512 words per macro

// -------------------------------------------------------------------------
// Instruction port: address decode

wire [AW-1:0]      i_word_addr = i_haddr[AW+1:2];
wire [2:0]          i_macro_sel = i_word_addr[AW-1:MACRO_AW];  // addr[11:9]
wire [MACRO_AW-1:0] i_macro_addr = i_word_addr[MACRO_AW-1:0];  // addr[8:0]

// Register macro select for data-phase read mux
reg [2:0] i_macro_sel_r;
always @(posedge clk)
    i_macro_sel_r <= i_macro_sel;

// -------------------------------------------------------------------------
// Data port: AHB pipeline (address phase → data phase)

wire [AW-1:0]      d_word_addr = d_haddr[AW+1:2];
wire               d_active    = d_htrans[1];
wire [2:0]          d_macro_sel = d_word_addr[AW-1:MACRO_AW];
wire [MACRO_AW-1:0] d_macro_addr = d_word_addr[MACRO_AW-1:0];

// Byte-enable strobes from hsize + address offset
wire [3:0] d_wstrb = (d_hsize == 3'b000) ? (4'b0001 << d_haddr[1:0]) :
                     (d_hsize == 3'b001) ? (4'b0011 << d_haddr[1:0]) :
                                            4'b1111;

// Registered pipeline signals
reg [MACRO_AW-1:0] d_macro_addr_r;
reg [2:0]          d_macro_sel_r;
reg                d_hwrite_r;
reg                d_active_r;
reg [3:0]          d_wstrb_r;

always @(posedge clk) begin
    d_macro_addr_r <= d_macro_addr;
    d_macro_sel_r  <= d_macro_sel;
    d_hwrite_r     <= d_hwrite;
    d_active_r     <= d_active;
    d_wstrb_r      <= d_wstrb;
end

// -------------------------------------------------------------------------
// Macro instances

wire [31:0] macro_dout0 [0:N_MACROS-1];  // Port 0 (RW) read data
wire [31:0] macro_dout1 [0:N_MACROS-1];  // Port 1 (R)  read data

genvar gm;
generate
    for (gm = 0; gm < N_MACROS; gm = gm + 1) begin : gen_macro
        // Port 0 (RW): data port — active when this macro is selected
        // csb0/web0 are active-low
        wire csb0 = ~(d_active_r && (d_macro_sel_r == gm[2:0]));
        wire web0 = ~d_hwrite_r;

        // Port 1 (R): instruction port — active when selected
        wire csb1 = ~(i_macro_sel == gm[2:0]);

        sky130_sram_2kbyte_1rw1r_32x512_8 u_sram (
            // Port 0: RW (data)
            .clk0   (clk),
            .csb0   (csb0),
            .web0   (web0),
            .wmask0 (d_wstrb_r),
            .addr0  (d_macro_addr_r),
            .din0   (d_hwdata),
            .dout0  (macro_dout0[gm]),

            // Port 1: R (instruction)
            .clk1   (clk),
            .csb1   (csb1),
            .addr1  (i_macro_addr),
            .dout1  (macro_dout1[gm])
        );
    end
endgenerate

// -------------------------------------------------------------------------
// Read data mux

wire [31:0] d_hrdata_mux = macro_dout0[d_macro_sel_r];
wire [31:0] i_hrdata_mux = macro_dout1[i_macro_sel_r];

// -------------------------------------------------------------------------
// Write-first forwarding (same logic as simulation sram_bank.sv)
//
// When a write and read target the same address in the same cycle,
// the macro returns stale data. Capture write data and mux over
// the macro output byte-by-byte.

wire       fwd_hit = d_active_r && d_hwrite_r &&
                     (d_macro_sel_r == d_macro_sel) &&
                     (d_macro_addr_r == d_macro_addr);
reg        fwd_hit_r;
reg [3:0]  fwd_wstrb_r;
reg [31:0] fwd_data_r;

always @(posedge clk) begin
    fwd_hit_r   <= fwd_hit;
    fwd_wstrb_r <= d_wstrb_r;
    fwd_data_r  <= d_hwdata;
end

assign d_hrdata = {
    (fwd_hit_r && fwd_wstrb_r[3]) ? fwd_data_r[31:24] : d_hrdata_mux[31:24],
    (fwd_hit_r && fwd_wstrb_r[2]) ? fwd_data_r[23:16] : d_hrdata_mux[23:16],
    (fwd_hit_r && fwd_wstrb_r[1]) ? fwd_data_r[15: 8] : d_hrdata_mux[15: 8],
    (fwd_hit_r && fwd_wstrb_r[0]) ? fwd_data_r[ 7: 0] : d_hrdata_mux[ 7: 0]
};

assign i_hrdata = i_hrdata_mux;

// -------------------------------------------------------------------------
// AHB response — always ready, no errors

assign i_hready  = 1'b1;
assign i_hresp   = 1'b0;
assign d_hready  = 1'b1;
assign d_hresp   = 1'b0;
assign d_hexokay = 1'b0;

endmodule
