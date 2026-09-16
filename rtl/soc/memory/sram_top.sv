// sram_top.sv — 4-bank SRAM subsystem (64 KB total).
//
// Four banks of 16 KB each, selected by addr[15:14].
// Each bank has dual AHB-Lite ports (I = read-only, D = read/write).
// Bank selection is registered for AHB data-phase muxing.
//
// External interface is unchanged from the single-bank version —
// rxpsm32.sv sees the same ports.

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

localparam N_BANKS   = 4;
localparam BANK_DEPTH = 4096;  // 4096 words × 32-bit = 16 KB per bank

// -------------------------------------------------------------------------
// Bank select: addr[15:14] picks 1 of 4 banks

wire [1:0] i_bank_sel = i_haddr[15:14];
wire [1:0] d_bank_sel = d_haddr[15:14];

// Register bank select for data-phase read mux (AHB pipeline)
reg [1:0] i_bank_sel_r, d_bank_sel_r;
always @(posedge clk) begin
    i_bank_sel_r <= i_bank_sel;
    d_bank_sel_r <= d_bank_sel;
end

// -------------------------------------------------------------------------
// Per-bank signals

wire [31:0] bank_i_hrdata [0:N_BANKS-1];
wire [31:0] bank_d_hrdata [0:N_BANKS-1];
wire [N_BANKS-1:0] bank_d_hexokay;

// -------------------------------------------------------------------------
// Instantiate 4 banks

genvar gi;
generate
    for (gi = 0; gi < N_BANKS; gi = gi + 1) begin : gen_banks
        // Gate htrans so only the selected bank sees an active transfer.
        // Non-selected banks see IDLE and ignore the cycle.
        wire [1:0] bank_i_htrans = (i_bank_sel == gi[1:0]) ? i_htrans : 2'b00;
        wire [1:0] bank_d_htrans = (d_bank_sel == gi[1:0]) ? d_htrans : 2'b00;

        sram_bank #(
            .DEPTH (BANK_DEPTH)
        ) bank (
            .clk       (clk),

            .i_haddr   (i_haddr),
            .i_htrans  (bank_i_htrans),
            .i_hrdata  (bank_i_hrdata[gi]),
            .i_hready  (),              // each bank is always ready
            .i_hresp   (),

            .d_haddr   (d_haddr),
            .d_hwrite  (d_hwrite),
            .d_htrans  (bank_d_htrans),
            .d_hsize   (d_hsize),
            .d_hwdata  (d_hwdata),
            .d_hrdata  (bank_d_hrdata[gi]),
            .d_hready  (),
            .d_hresp   (),
            .d_hexokay (bank_d_hexokay[gi])
        );
    end
endgenerate

// -------------------------------------------------------------------------
// Data-phase read mux: select output from the bank that was addressed

assign i_hrdata = bank_i_hrdata[i_bank_sel_r];
assign d_hrdata = bank_d_hrdata[d_bank_sel_r];

// Always ready, no errors (each bank is always ready)
assign i_hready  = 1'b1;
assign i_hresp   = 1'b0;
assign d_hready  = 1'b1;
assign d_hresp   = 1'b0;
assign d_hexokay = bank_d_hexokay[d_bank_sel_r];

endmodule
