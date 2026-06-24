// Single-core SoC with bus fabric.
//
// Instruction port: CPU0-I → i_dec → SRAM I port.
// Data port:        CPU0-D → d_dec → SRAM D port, GPIO, PIO0, or PIO1.
//
// Address map (data port):
//   0x0000_0000 – 0x0000_FFFF  →  SRAM  (64 KB)
//   0x4000_0000 – 0x4000_FFFF  →  GPIO  (32-bit output register)
//   0x5020_0000 – 0x5020_FFFF  →  PIO0
//   0x5030_0000 – 0x5030_FFFF  →  PIO1
//
// No arbiter: single core connects directly to decoders.
// Debug and interrupt inputs are tied off.

`default_nettype none

module rvsoc_top (
    input  wire        clk,
    input  wire        rst_n,

    // Simple GPIO output (backward-compatible with existing tests)
    output wire [31:0] gpio_out,

    // PIO GPIO interface
    input  wire [31:0] pio_gpio_in,
    output wire [31:0] pio_gpio_out,
    output wire [31:0] pio_gpio_oe,

    // PIO IRQ outputs: [3:0]=PIO0 IRQs, [7:4]=PIO1 IRQs
    output wire [7:0]  pio_irq
);

// ----------------------------------------------------------------------------
// CPU0 AHB signals

wire [31:0] cpu0_i_haddr,  cpu0_i_hwdata,  cpu0_i_hrdata;
wire        cpu0_i_hwrite, cpu0_i_hready,  cpu0_i_hresp;
wire [1:0]  cpu0_i_htrans;
wire [2:0]  cpu0_i_hsize,  cpu0_i_hburst;
wire [3:0]  cpu0_i_hprot;
wire        cpu0_i_hmastlock;
wire [7:0]  cpu0_i_hmaster;

wire [31:0] cpu0_d_haddr,  cpu0_d_hwdata,  cpu0_d_hrdata;
wire        cpu0_d_hwrite, cpu0_d_hready,  cpu0_d_hresp;
wire [1:0]  cpu0_d_htrans;
wire [2:0]  cpu0_d_hsize,  cpu0_d_hburst;
wire [3:0]  cpu0_d_hprot;
wire        cpu0_d_hmastlock;
wire [7:0]  cpu0_d_hmaster;
wire        cpu0_d_hexcl;

// ----------------------------------------------------------------------------
// I decoder → SRAM I port

wire [31:0] dec_isram_haddr,  dec_isram_hrdata;
wire [1:0]  dec_isram_htrans;
wire        dec_isram_hready, dec_isram_hresp;

// ----------------------------------------------------------------------------
// Decoder → SRAM D port

wire [31:0] dec_sram_haddr,  dec_sram_hwdata,  dec_sram_hrdata;
wire        dec_sram_hwrite, dec_sram_hready,  dec_sram_hresp;
wire [1:0]  dec_sram_htrans;
wire [2:0]  dec_sram_hsize;
wire        dec_sram_hexokay;

// ----------------------------------------------------------------------------
// Decoder → GPIO

wire [31:0] dec_gpio_haddr,  dec_gpio_hwdata,  dec_gpio_hrdata;
wire        dec_gpio_hwrite, dec_gpio_hready,  dec_gpio_hresp;
wire [1:0]  dec_gpio_htrans;
wire [2:0]  dec_gpio_hsize;

// ----------------------------------------------------------------------------
// Decoder → PIO0

wire [31:0] dec_pio0_haddr,  dec_pio0_hwdata,  dec_pio0_hrdata;
wire        dec_pio0_hwrite, dec_pio0_hready,  dec_pio0_hresp;
wire [1:0]  dec_pio0_htrans;
wire [2:0]  dec_pio0_hsize;

// ----------------------------------------------------------------------------
// Decoder → PIO1

wire [31:0] dec_pio1_haddr,  dec_pio1_hwdata,  dec_pio1_hrdata;
wire        dec_pio1_hwrite, dec_pio1_hready,  dec_pio1_hresp;
wire [1:0]  dec_pio1_htrans;
wire [2:0]  dec_pio1_hsize;

// ----------------------------------------------------------------------------
// PIO GPIO signals (merged from PIO0 and PIO1; PIO1 has higher priority)

wire [31:0] pio0_gpio_out, pio0_gpio_oe;
wire [31:0] pio1_gpio_out, pio1_gpio_oe;
wire [3:0]  pio0_irq, pio1_irq;

// Per-bit priority mux: PIO1 overrides PIO0 when PIO1 has OE
assign pio_gpio_out = (pio1_gpio_oe & pio1_gpio_out) |
                      (~pio1_gpio_oe & pio0_gpio_oe & pio0_gpio_out);
assign pio_gpio_oe  = pio0_gpio_oe | pio1_gpio_oe;
assign pio_irq      = {pio1_irq, pio0_irq};

// ----------------------------------------------------------------------------
// CPU0 — single hart

hazard3_cpu_2port cpu0 (
    .clk           (clk),
    .clk_always_on (clk),
    .rst_n         (rst_n),

    .pwrup_req     (),
    .pwrup_ack     (1'b1),
    .clk_en        (),
    .unblock_out   (),
    .unblock_in    (1'b0),

    .i_haddr       (cpu0_i_haddr),
    .i_hwrite      (cpu0_i_hwrite),
    .i_htrans      (cpu0_i_htrans),
    .i_hsize       (cpu0_i_hsize),
    .i_hburst      (cpu0_i_hburst),
    .i_hprot       (cpu0_i_hprot),
    .i_hmastlock   (cpu0_i_hmastlock),
    .i_hmaster     (cpu0_i_hmaster),
    .i_hready      (cpu0_i_hready),
    .i_hresp       (cpu0_i_hresp),
    .i_hwdata      (cpu0_i_hwdata),
    .i_hrdata      (cpu0_i_hrdata),

    .d_haddr       (cpu0_d_haddr),
    .d_hwrite      (cpu0_d_hwrite),
    .d_htrans      (cpu0_d_htrans),
    .d_hsize       (cpu0_d_hsize),
    .d_hburst      (cpu0_d_hburst),
    .d_hprot       (cpu0_d_hprot),
    .d_hmastlock   (cpu0_d_hmastlock),
    .d_hmaster     (cpu0_d_hmaster),
    .d_hexcl       (cpu0_d_hexcl),
    .d_hready      (cpu0_d_hready),
    .d_hresp       (cpu0_d_hresp),
    .d_hexokay     (1'b0),
    .d_hwdata      (cpu0_d_hwdata),
    .d_hrdata      (cpu0_d_hrdata),

    .fence_i_vld   (),
    .fence_d_vld   (),
    .fence_rdy     (1'b1),

    .dbg_req_halt          (1'b0),
    .dbg_req_halt_on_reset (1'b0),
    .dbg_req_resume        (1'b0),
    .dbg_halted            (),
    .dbg_running           (),
    .dbg_data0_rdata       (32'h0),
    .dbg_data0_wdata       (),
    .dbg_data0_wen         (),
    .dbg_instr_data        (32'h0),
    .dbg_instr_data_vld    (1'b0),
    .dbg_instr_data_rdy    (),
    .dbg_instr_caught_exception (),
    .dbg_instr_caught_ebreak    (),
    .dbg_sbus_addr         (32'h0),
    .dbg_sbus_write        (1'b0),
    .dbg_sbus_size         (2'h0),
    .dbg_sbus_vld          (1'b0),
    .dbg_sbus_rdy          (),
    .dbg_sbus_err          (),
    .dbg_sbus_wdata        (32'h0),
    .dbg_sbus_rdata        (),

    .mhartid_val   (32'h0),
    .eco_version    (4'h0),

    .irq           (1'b0),
    .soft_irq      (1'b0),
    .timer_irq     (1'b0)
);

// ----------------------------------------------------------------------------
// Data-port decoder: routes CPU0-D directly to SRAM, GPIO, PIO0, or PIO1

ahb_decoder_4s d_dec (
    .clk       (clk),
    .rst_n     (rst_n),

    .m_haddr   (cpu0_d_haddr),
    .m_hwrite  (cpu0_d_hwrite),
    .m_htrans  (cpu0_d_htrans),
    .m_hsize   (cpu0_d_hsize),
    .m_hwdata  (cpu0_d_hwdata),
    .m_hrdata  (cpu0_d_hrdata),
    .m_hready  (cpu0_d_hready),
    .m_hresp   (cpu0_d_hresp),

    .s0_haddr  (dec_sram_haddr),
    .s0_hwrite (dec_sram_hwrite),
    .s0_htrans (dec_sram_htrans),
    .s0_hsize  (dec_sram_hsize),
    .s0_hwdata (dec_sram_hwdata),
    .s0_hrdata (dec_sram_hrdata),
    .s0_hready (dec_sram_hready),
    .s0_hresp  (dec_sram_hresp),

    .s1_haddr  (dec_gpio_haddr),
    .s1_hwrite (dec_gpio_hwrite),
    .s1_htrans (dec_gpio_htrans),
    .s1_hsize  (dec_gpio_hsize),
    .s1_hwdata (dec_gpio_hwdata),
    .s1_hrdata (dec_gpio_hrdata),
    .s1_hready (dec_gpio_hready),
    .s1_hresp  (dec_gpio_hresp),

    .s2_haddr  (dec_pio0_haddr),
    .s2_hwrite (dec_pio0_hwrite),
    .s2_htrans (dec_pio0_htrans),
    .s2_hsize  (dec_pio0_hsize),
    .s2_hwdata (dec_pio0_hwdata),
    .s2_hrdata (dec_pio0_hrdata),
    .s2_hready (dec_pio0_hready),
    .s2_hresp  (dec_pio0_hresp),

    .s3_haddr  (dec_pio1_haddr),
    .s3_hwrite (dec_pio1_hwrite),
    .s3_htrans (dec_pio1_htrans),
    .s3_hsize  (dec_pio1_hsize),
    .s3_hwdata (dec_pio1_hwdata),
    .s3_hrdata (dec_pio1_hrdata),
    .s3_hready (dec_pio1_hready),
    .s3_hresp  (dec_pio1_hresp)
);

// ----------------------------------------------------------------------------
// Instruction-port decoder: routes CPU0-I directly to SRAM I port.
// s1 reserved for future fetch targets; tied off.

ahb_decoder i_dec (
    .clk       (clk),
    .rst_n     (rst_n),

    .m_haddr   (cpu0_i_haddr),
    .m_hwrite  (cpu0_i_hwrite),
    .m_htrans  (cpu0_i_htrans),
    .m_hsize   (cpu0_i_hsize),
    .m_hwdata  (cpu0_i_hwdata),
    .m_hrdata  (cpu0_i_hrdata),
    .m_hready  (cpu0_i_hready),
    .m_hresp   (cpu0_i_hresp),

    // s0 → SRAM I port (read-only; hwrite/hsize/hwdata outputs unused)
    .s0_haddr  (dec_isram_haddr),
    .s0_hwrite (),
    .s0_htrans (dec_isram_htrans),
    .s0_hsize  (),
    .s0_hwdata (),
    .s0_hrdata (dec_isram_hrdata),
    .s0_hready (dec_isram_hready),
    .s0_hresp  (dec_isram_hresp),

    // s1 → reserved, tied off
    .s1_haddr  (),
    .s1_hwrite (),
    .s1_htrans (),
    .s1_hsize  (),
    .s1_hwdata (),
    .s1_hrdata (32'h0),
    .s1_hready (1'b1),
    .s1_hresp  (1'b0)
);

// ----------------------------------------------------------------------------
// Shared SRAM (64 KB)

sram_top mem (
    .clk       (clk),
    .i_haddr   (dec_isram_haddr),
    .i_htrans  (dec_isram_htrans),
    .i_hrdata  (dec_isram_hrdata),
    .i_hready  (dec_isram_hready),
    .i_hresp   (dec_isram_hresp),
    .d_haddr   (dec_sram_haddr),
    .d_hwrite  (dec_sram_hwrite),
    .d_htrans  (dec_sram_htrans),
    .d_hsize   (dec_sram_hsize),
    .d_hwdata  (dec_sram_hwdata),
    .d_hrdata  (dec_sram_hrdata),
    .d_hready  (dec_sram_hready),
    .d_hresp   (dec_sram_hresp),
    .d_hexokay (dec_sram_hexokay)
);

// ----------------------------------------------------------------------------
// GPIO peripheral

gpio gpio0 (
    .clk      (clk),
    .rst_n    (rst_n),
    .haddr    (dec_gpio_haddr),
    .hwrite   (dec_gpio_hwrite),
    .htrans   (dec_gpio_htrans),
    .hwdata   (dec_gpio_hwdata),
    .hrdata   (dec_gpio_hrdata),
    .hready   (dec_gpio_hready),
    .hresp    (dec_gpio_hresp),
    .gpio_out (gpio_out)
);

// ----------------------------------------------------------------------------
// PIO0 (0x5020_0000)

pio_top pio0 (
    .clk      (clk),
    .rst_n    (rst_n),
    .haddr    (dec_pio0_haddr),
    .hwrite   (dec_pio0_hwrite),
    .htrans   (dec_pio0_htrans),
    .hsize    (dec_pio0_hsize),
    .hwdata   (dec_pio0_hwdata),
    .hrdata   (dec_pio0_hrdata),
    .hready   (dec_pio0_hready),
    .hresp    (dec_pio0_hresp),
    .gpio_in  (pio_gpio_in),
    .gpio_out (pio0_gpio_out),
    .gpio_oe  (pio0_gpio_oe),
    .irq_out  (pio0_irq)
);

// ----------------------------------------------------------------------------
// PIO1 (0x5030_0000)

pio_top pio1 (
    .clk      (clk),
    .rst_n    (rst_n),
    .haddr    (dec_pio1_haddr),
    .hwrite   (dec_pio1_hwrite),
    .htrans   (dec_pio1_htrans),
    .hsize    (dec_pio1_hsize),
    .hwdata   (dec_pio1_hwdata),
    .hrdata   (dec_pio1_hrdata),
    .hready   (dec_pio1_hready),
    .hresp    (dec_pio1_hresp),
    .gpio_in  (pio_gpio_in),
    .gpio_out (pio1_gpio_out),
    .gpio_oe  (pio1_gpio_oe),
    .irq_out  (pio1_irq)
);

endmodule
