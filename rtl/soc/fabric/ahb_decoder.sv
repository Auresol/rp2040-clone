// 1-master, 2-slave AHB-Lite address decoder.
//
// Address map (hardcoded for M4):
//   0x0000_0000 – 0x0000_FFFF  →  slave 0 (SRAM)
//   0x4000_0000 – 0x4000_FFFF  →  slave 1 (GPIO)
//   everything else             →  slave 0 (SRAM, default)
//
// Routing uses two muxes:
//   - Address phase: combinational `sel` routes htrans/haddr/hwrite/hsize/hwdata
//     to the selected slave; all others receive htrans=IDLE so they ignore the cycle.
//   - Data phase: registered `sel_r` (captured at posedge during address phase)
//     selects which slave's hrdata/hready/hresp goes back to the master.
//     The one-cycle delay is required because hrdata is registered inside the slave.

`default_nettype none

module ahb_decoder (
    input  wire        clk,
    input  wire        rst_n,

    // Master port (from arbiter)
    input  wire [31:0] m_haddr,
    input  wire        m_hwrite,
    input  wire [1:0]  m_htrans,
    input  wire [2:0]  m_hsize,
    input  wire [31:0] m_hwdata,
    output wire [31:0] m_hrdata,
    output wire        m_hready,
    output wire        m_hresp,

    // Slave 0 — SRAM
    output wire [31:0] s0_haddr,
    output wire        s0_hwrite,
    output wire [1:0]  s0_htrans,
    output wire [2:0]  s0_hsize,
    output wire [31:0] s0_hwdata,
    input  wire [31:0] s0_hrdata,
    input  wire        s0_hready,
    input  wire        s0_hresp,

    // Slave 1 — GPIO
    output wire [31:0] s1_haddr,
    output wire        s1_hwrite,
    output wire [1:0]  s1_htrans,
    output wire [2:0]  s1_hsize,
    output wire [31:0] s1_hwdata,
    input  wire [31:0] s1_hrdata,
    input  wire        s1_hready,
    input  wire        s1_hresp
);

// ----------------------------------------------------------------------------
// Address decode

localparam SEL_SRAM = 1'b0;
localparam SEL_GPIO = 1'b1;

wire sel = (m_haddr[31:16] == 16'h4000) ? SEL_GPIO : SEL_SRAM;

// Register sel so the data-phase response mux uses the same slave
// that received the address phase one cycle earlier.
reg sel_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sel_r <= SEL_SRAM;
    else        sel_r <= sel;
end

// ----------------------------------------------------------------------------
// Address-phase mux: forward to selected slave, send IDLE to others

assign s0_htrans = (sel == SEL_SRAM) ? m_htrans : 2'b00;
assign s1_htrans = (sel == SEL_GPIO) ? m_htrans : 2'b00;

// Address, control, and write data broadcast to all slaves.
// Non-selected slaves see htrans=IDLE so they ignore the transaction.
assign s0_haddr  = m_haddr;
assign s0_hwrite = m_hwrite;
assign s0_hsize  = m_hsize;
assign s0_hwdata = m_hwdata;

assign s1_haddr  = m_haddr;
assign s1_hwrite = m_hwrite;
assign s1_hsize  = m_hsize;
assign s1_hwdata = m_hwdata;

// ----------------------------------------------------------------------------
// Data-phase mux: return response from whichever slave was selected last cycle

assign m_hrdata = (sel_r == SEL_GPIO) ? s1_hrdata : s0_hrdata;
assign m_hready = (sel_r == SEL_GPIO) ? s1_hready : s0_hready;
assign m_hresp  = (sel_r == SEL_GPIO) ? s1_hresp  : s0_hresp;

endmodule
