// ahb_decoder_4s.sv — 1-master, 4-slave AHB-Lite address decoder.
//
// Address map:
//   0x0000_0000 – 0x0000_FFFF  →  slave 0 (SRAM)
//   0x4000_0000 – 0x4000_FFFF  →  slave 1 (GPIO)
//   0x5020_0000 – 0x5020_FFFF  →  slave 2 (PIO0)
//   0x5030_0000 – 0x5030_FFFF  →  slave 3 (PIO1)
//   everything else             →  slave 0 (SRAM, default)
//
// sel encoding: 2'b00=SRAM, 2'b01=GPIO, 2'b10=PIO0, 2'b11=PIO1
//
// Address-phase mux: forwards htrans to the selected slave only (others get IDLE).
// Data-phase mux: registered sel_r selects which slave's hrdata/hready/hresp returns.

`default_nettype none

module ahb_decoder_4s (
    input  wire        clk,
    input  wire        rst_n,

    // Master port
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
    input  wire        s1_hresp,

    // Slave 2 — PIO0
    output wire [31:0] s2_haddr,
    output wire        s2_hwrite,
    output wire [1:0]  s2_htrans,
    output wire [2:0]  s2_hsize,
    output wire [31:0] s2_hwdata,
    input  wire [31:0] s2_hrdata,
    input  wire        s2_hready,
    input  wire        s2_hresp,

    // Slave 3 — PIO1
    output wire [31:0] s3_haddr,
    output wire        s3_hwrite,
    output wire [1:0]  s3_htrans,
    output wire [2:0]  s3_hsize,
    output wire [31:0] s3_hwdata,
    input  wire [31:0] s3_hrdata,
    input  wire        s3_hready,
    input  wire        s3_hresp
);

// ----------------------------------------------------------------------------
// Address decode

localparam [1:0] SEL_SRAM = 2'b00;
localparam [1:0] SEL_GPIO = 2'b01;
localparam [1:0] SEL_PIO0 = 2'b10;
localparam [1:0] SEL_PIO1 = 2'b11;

function automatic [1:0] decode_addr;
    input [31:0] addr;
    if      (addr[31:20] == 12'h503) decode_addr = SEL_PIO1;
    else if (addr[31:20] == 12'h502) decode_addr = SEL_PIO0;
    else if (addr[31:16] == 16'h4000) decode_addr = SEL_GPIO;
    else                              decode_addr = SEL_SRAM;
endfunction

wire [1:0] sel = decode_addr(m_haddr);

// Register sel for data-phase mux
reg [1:0] sel_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sel_r <= SEL_SRAM;
    else        sel_r <= sel;
end

// ----------------------------------------------------------------------------
// Address-phase mux: forward htrans only to the selected slave

assign s0_htrans = (sel == SEL_SRAM) ? m_htrans : 2'b00;
assign s1_htrans = (sel == SEL_GPIO) ? m_htrans : 2'b00;
assign s2_htrans = (sel == SEL_PIO0) ? m_htrans : 2'b00;
assign s3_htrans = (sel == SEL_PIO1) ? m_htrans : 2'b00;

// Broadcast address / control / write data to all slaves
assign s0_haddr  = m_haddr;  assign s0_hwrite = m_hwrite;  assign s0_hsize = m_hsize;  assign s0_hwdata = m_hwdata;
assign s1_haddr  = m_haddr;  assign s1_hwrite = m_hwrite;  assign s1_hsize = m_hsize;  assign s1_hwdata = m_hwdata;
assign s2_haddr  = m_haddr;  assign s2_hwrite = m_hwrite;  assign s2_hsize = m_hsize;  assign s2_hwdata = m_hwdata;
assign s3_haddr  = m_haddr;  assign s3_hwrite = m_hwrite;  assign s3_hsize = m_hsize;  assign s3_hwdata = m_hwdata;

// ----------------------------------------------------------------------------
// Data-phase mux: return response from whichever slave was selected last cycle

assign m_hrdata = (sel_r == SEL_GPIO) ? s1_hrdata :
                  (sel_r == SEL_PIO0) ? s2_hrdata :
                  (sel_r == SEL_PIO1) ? s3_hrdata :
                                        s0_hrdata;

assign m_hready = (sel_r == SEL_GPIO) ? s1_hready :
                  (sel_r == SEL_PIO0) ? s2_hready :
                  (sel_r == SEL_PIO1) ? s3_hready :
                                        s0_hready;

assign m_hresp  = (sel_r == SEL_GPIO) ? s1_hresp :
                  (sel_r == SEL_PIO0) ? s2_hresp :
                  (sel_r == SEL_PIO1) ? s3_hresp :
                                        s0_hresp;

endmodule
