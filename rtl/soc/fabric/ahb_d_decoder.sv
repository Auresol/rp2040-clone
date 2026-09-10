// ahb_d_decoder.sv — 1-master, 10-slave AHB-Lite data-port decoder.
//
// Address map:
//   0x0000_0000 – 0x0000_FFFF  →  slave 0 (SRAM)
//   0x4000_0000 – 0x4000_FFFF  →  slave 1 (GPIO)
//   0x4003_0000 – 0x4003_3FFF  →  slave 4 (UART0)   ← base 0x4003_0000
//   0x4003_C000 – 0x4003_FFFF  →  slave 5 (SPI0)    ← base 0x4003_C000
//   0x4005_0000 – 0x4005_3FFF  →  slave 6 (TIMER)   ← base 0x4005_0000
//   0x4005_4000 – 0x4005_7FFF  →  slave 8 (RESET)   ← base 0x4005_4000
//   0x4005_8000 – 0x4005_BFFF  →  slave 7 (WATCHDOG)← base 0x4005_8000
//   0x4005_C000 – 0x4005_FFFF  →  slave 9 (SYSINFO) ← base 0x4005_C000
//   0x5020_0000 – 0x5020_FFFF  →  slave 2 (PIO0)
//   0x5030_0000 – 0x5030_FFFF  →  slave 3 (PIO1)
//   everything else             →  slave 0 (SRAM, default)
//
// sel encoding: 4'b0000=SRAM, 0001=GPIO, 0010=PIO0, 0011=PIO1,
//               0100=UART0, 0101=SPI0, 0110=TIMER,
//               0111=WATCHDOG, 1000=RESET, 1001=SYSINFO
//
// Address-phase mux: forwards htrans to the selected slave only (others get IDLE).
// Data-phase mux: registered sel_r selects which slave's hrdata/hready/hresp returns.

`default_nettype none

module ahb_d_decoder (
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
    input  wire        s3_hresp,

    // Slave 4 — UART0
    output wire [31:0] s4_haddr,
    output wire        s4_hwrite,
    output wire [1:0]  s4_htrans,
    output wire [2:0]  s4_hsize,
    output wire [31:0] s4_hwdata,
    input  wire [31:0] s4_hrdata,
    input  wire        s4_hready,
    input  wire        s4_hresp,

    // Slave 5 — SPI0
    output wire [31:0] s5_haddr,
    output wire        s5_hwrite,
    output wire [1:0]  s5_htrans,
    output wire [2:0]  s5_hsize,
    output wire [31:0] s5_hwdata,
    input  wire [31:0] s5_hrdata,
    input  wire        s5_hready,
    input  wire        s5_hresp,

    // Slave 6 — TIMER
    output wire [31:0] s6_haddr,
    output wire        s6_hwrite,
    output wire [1:0]  s6_htrans,
    output wire [2:0]  s6_hsize,
    output wire [31:0] s6_hwdata,
    input  wire [31:0] s6_hrdata,
    input  wire        s6_hready,
    input  wire        s6_hresp,

    // Slave 7 — WATCHDOG
    output wire [31:0] s7_haddr,
    output wire        s7_hwrite,
    output wire [1:0]  s7_htrans,
    output wire [2:0]  s7_hsize,
    output wire [31:0] s7_hwdata,
    input  wire [31:0] s7_hrdata,
    input  wire        s7_hready,
    input  wire        s7_hresp,

    // Slave 8 — RESET CONTROLLER
    output wire [31:0] s8_haddr,
    output wire        s8_hwrite,
    output wire [1:0]  s8_htrans,
    output wire [2:0]  s8_hsize,
    output wire [31:0] s8_hwdata,
    input  wire [31:0] s8_hrdata,
    input  wire        s8_hready,
    input  wire        s8_hresp,

    // Slave 9 — SYSINFO
    output wire [31:0] s9_haddr,
    output wire        s9_hwrite,
    output wire [1:0]  s9_htrans,
    output wire [2:0]  s9_hsize,
    output wire [31:0] s9_hwdata,
    input  wire [31:0] s9_hrdata,
    input  wire        s9_hready,
    input  wire        s9_hresp
);

// ----------------------------------------------------------------------------
// Address decode

localparam [3:0] SEL_SRAM     = 4'd0;
localparam [3:0] SEL_GPIO     = 4'd1;
localparam [3:0] SEL_PIO0     = 4'd2;
localparam [3:0] SEL_PIO1     = 4'd3;
localparam [3:0] SEL_UART0    = 4'd4;
localparam [3:0] SEL_SPI0     = 4'd5;
localparam [3:0] SEL_TIMER    = 4'd6;
localparam [3:0] SEL_WATCHDOG = 4'd7;
localparam [3:0] SEL_RESET    = 4'd8;
localparam [3:0] SEL_SYSINFO  = 4'd9;

function automatic [3:0] decode_addr;
    input [31:0] addr;
    if      (addr[31:20] == 12'h503)    decode_addr = SEL_PIO1;
    else if (addr[31:20] == 12'h502)    decode_addr = SEL_PIO0;
    else if (addr[31:14] == 18'h1000F)  decode_addr = SEL_SPI0;      // 0x4003_C000
    else if (addr[31:14] == 18'h10017)  decode_addr = SEL_SYSINFO;   // 0x4005_C000
    else if (addr[31:14] == 18'h10016)  decode_addr = SEL_WATCHDOG;  // 0x4005_8000
    else if (addr[31:14] == 18'h10015)  decode_addr = SEL_RESET;     // 0x4005_4000
    else if (addr[31:14] == 18'h10014)  decode_addr = SEL_TIMER;     // 0x4005_0000
    else if (addr[31:16] == 16'h4003)   decode_addr = SEL_UART0;
    else if (addr[31:16] == 16'h4000)   decode_addr = SEL_GPIO;
    else                                decode_addr = SEL_SRAM;
endfunction

wire [3:0] sel = decode_addr(m_haddr);

// Register sel for data-phase mux
reg [3:0] sel_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sel_r <= SEL_SRAM;
    else        sel_r <= sel;
end

// ----------------------------------------------------------------------------
// Address-phase mux: forward htrans only to the selected slave

assign s0_htrans = (sel == SEL_SRAM)     ? m_htrans : 2'b00;
assign s1_htrans = (sel == SEL_GPIO)     ? m_htrans : 2'b00;
assign s2_htrans = (sel == SEL_PIO0)     ? m_htrans : 2'b00;
assign s3_htrans = (sel == SEL_PIO1)     ? m_htrans : 2'b00;
assign s4_htrans = (sel == SEL_UART0)    ? m_htrans : 2'b00;
assign s5_htrans = (sel == SEL_SPI0)     ? m_htrans : 2'b00;
assign s6_htrans = (sel == SEL_TIMER)    ? m_htrans : 2'b00;
assign s7_htrans = (sel == SEL_WATCHDOG) ? m_htrans : 2'b00;
assign s8_htrans = (sel == SEL_RESET)    ? m_htrans : 2'b00;
assign s9_htrans = (sel == SEL_SYSINFO)  ? m_htrans : 2'b00;

// Broadcast address / control / write data to all slaves
assign s0_haddr = m_haddr; assign s0_hwrite = m_hwrite; assign s0_hsize = m_hsize; assign s0_hwdata = m_hwdata;
assign s1_haddr = m_haddr; assign s1_hwrite = m_hwrite; assign s1_hsize = m_hsize; assign s1_hwdata = m_hwdata;
assign s2_haddr = m_haddr; assign s2_hwrite = m_hwrite; assign s2_hsize = m_hsize; assign s2_hwdata = m_hwdata;
assign s3_haddr = m_haddr; assign s3_hwrite = m_hwrite; assign s3_hsize = m_hsize; assign s3_hwdata = m_hwdata;
assign s4_haddr = m_haddr; assign s4_hwrite = m_hwrite; assign s4_hsize = m_hsize; assign s4_hwdata = m_hwdata;
assign s5_haddr = m_haddr; assign s5_hwrite = m_hwrite; assign s5_hsize = m_hsize; assign s5_hwdata = m_hwdata;
assign s6_haddr = m_haddr; assign s6_hwrite = m_hwrite; assign s6_hsize = m_hsize; assign s6_hwdata = m_hwdata;
assign s7_haddr = m_haddr; assign s7_hwrite = m_hwrite; assign s7_hsize = m_hsize; assign s7_hwdata = m_hwdata;
assign s8_haddr = m_haddr; assign s8_hwrite = m_hwrite; assign s8_hsize = m_hsize; assign s8_hwdata = m_hwdata;
assign s9_haddr = m_haddr; assign s9_hwrite = m_hwrite; assign s9_hsize = m_hsize; assign s9_hwdata = m_hwdata;

// ----------------------------------------------------------------------------
// Data-phase mux: return response from whichever slave was selected last cycle

assign m_hrdata = (sel_r == SEL_GPIO)     ? s1_hrdata :
                  (sel_r == SEL_PIO0)     ? s2_hrdata :
                  (sel_r == SEL_PIO1)     ? s3_hrdata :
                  (sel_r == SEL_UART0)    ? s4_hrdata :
                  (sel_r == SEL_SPI0)     ? s5_hrdata :
                  (sel_r == SEL_TIMER)    ? s6_hrdata :
                  (sel_r == SEL_WATCHDOG) ? s7_hrdata :
                  (sel_r == SEL_RESET)    ? s8_hrdata :
                  (sel_r == SEL_SYSINFO)  ? s9_hrdata :
                                            s0_hrdata;

assign m_hready = (sel_r == SEL_GPIO)     ? s1_hready :
                  (sel_r == SEL_PIO0)     ? s2_hready :
                  (sel_r == SEL_PIO1)     ? s3_hready :
                  (sel_r == SEL_UART0)    ? s4_hready :
                  (sel_r == SEL_SPI0)     ? s5_hready :
                  (sel_r == SEL_TIMER)    ? s6_hready :
                  (sel_r == SEL_WATCHDOG) ? s7_hready :
                  (sel_r == SEL_RESET)    ? s8_hready :
                  (sel_r == SEL_SYSINFO)  ? s9_hready :
                                            s0_hready;

assign m_hresp  = (sel_r == SEL_GPIO)     ? s1_hresp  :
                  (sel_r == SEL_PIO0)     ? s2_hresp  :
                  (sel_r == SEL_PIO1)     ? s3_hresp  :
                  (sel_r == SEL_UART0)    ? s4_hresp  :
                  (sel_r == SEL_SPI0)     ? s5_hresp  :
                  (sel_r == SEL_TIMER)    ? s6_hresp  :
                  (sel_r == SEL_WATCHDOG) ? s7_hresp  :
                  (sel_r == SEL_RESET)    ? s8_hresp  :
                  (sel_r == SEL_SYSINFO)  ? s9_hresp  :
                                            s0_hresp;

endmodule
