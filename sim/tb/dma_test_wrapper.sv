// dma_test_wrapper.sv — wraps DMA + small SRAM for cocotb standalone testing.
//
// The testbench drives the slave port (s_*) to configure DMA channels.
// The DMA master port connects to a 256-word SRAM so transfers have
// something real to read/write.
//
// SRAM is pre-loadable via a separate AHB-ish write port (mem_*) so the
// testbench can seed memory contents and read results back.

`default_nettype none

module dma_test_wrapper (
    input  wire        clk,
    input  wire        rst_n,

    // AHB-Lite slave port — testbench configures DMA channels here
    input  wire [31:0] s_haddr,
    input  wire        s_hwrite,
    input  wire [1:0]  s_htrans,
    input  wire [2:0]  s_hsize,
    input  wire [31:0] s_hwdata,
    output wire [31:0] s_hrdata,
    output wire        s_hready,
    output wire        s_hresp,

    // DREQ inputs
    input  wire [3:0]  dreq,

    // DMA interrupt
    output wire        dma_irq,

    // Memory access port — testbench reads/writes SRAM directly
    input  wire [9:0]  mem_addr,   // word address (256 words)
    input  wire        mem_we,
    input  wire [31:0] mem_wdata,
    output wire [31:0] mem_rdata
);

// ---------------------------------------------------------------------------
// DMA instance

wire [31:0] m_haddr;
wire        m_hwrite;
wire [1:0]  m_htrans;
wire [2:0]  m_hsize;
wire [31:0] m_hwdata;
wire [31:0] m_hrdata;
wire        m_hready;
wire        m_hresp;

dma dma0 (
    .clk      (clk),
    .rst_n    (rst_n),

    .s_haddr  (s_haddr),
    .s_hwrite (s_hwrite),
    .s_htrans (s_htrans),
    .s_hsize  (s_hsize),
    .s_hwdata (s_hwdata),
    .s_hrdata (s_hrdata),
    .s_hready (s_hready),
    .s_hresp  (s_hresp),

    .m_haddr  (m_haddr),
    .m_hwrite (m_hwrite),
    .m_htrans (m_htrans),
    .m_hsize  (m_hsize),
    .m_hwdata (m_hwdata),
    .m_hrdata (m_hrdata),
    .m_hready (m_hready),
    .m_hresp  (m_hresp),

    .dreq     (dreq),
    .dma_irq  (dma_irq)
);

// ---------------------------------------------------------------------------
// Simple 256-word SRAM with AHB-Lite slave interface for DMA master port
// AND a separate read/write port for testbench access.

reg [31:0] mem [0:255];

// AHB pipeline for DMA master
wire m_active = m_htrans[1];
reg  m_active_r, m_hwrite_r;
reg  [7:0] m_word_addr_r;
reg  [31:0] m_rdata_r;

always @(posedge clk) begin
    m_active_r    <= m_active;
    m_hwrite_r    <= m_hwrite;
    m_word_addr_r <= m_haddr[9:2];
end

always @(posedge clk) begin
    if (m_active_r && m_hwrite_r)
        mem[m_word_addr_r] = m_hwdata;  // write-first
end

assign m_hrdata = mem[m_word_addr_r];
assign m_hready = 1'b1;
assign m_hresp  = 1'b0;

// Testbench direct memory port
always @(posedge clk) begin
    if (mem_we)
        mem[mem_addr[9:2]] = mem_wdata;  // write-first
end

assign mem_rdata = mem[mem_addr[9:2]];

endmodule
