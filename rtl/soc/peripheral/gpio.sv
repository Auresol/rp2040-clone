// gpio.sv — SIO-style GPIO with atomic SET/CLR/XOR and output enable.
//
// Base address: caller-defined (decoder handles base; offsets below are relative).
//
// Modelled after the RP2040 SIO GPIO registers. The SIO block is a custom
// Raspberry Pi design — it does NOT follow any ARM standard (not PL061).
//
// Register map (byte offset from base):
//   0x00  GPIO_IN       [31:0]  pad input levels (read-only, directly sampled)
//   0x04  GPIO_OUT      [31:0]  output level latch (read/write)
//   0x08  GPIO_OUT_SET  [31:0]  atomic bit-set on GPIO_OUT (write-only, reads as GPIO_OUT)
//   0x0C  GPIO_OUT_CLR  [31:0]  atomic bit-clear on GPIO_OUT (write-only, reads as GPIO_OUT)
//   0x10  GPIO_OUT_XOR  [31:0]  atomic bit-toggle on GPIO_OUT (write-only, reads as GPIO_OUT)
//   0x14  GPIO_OE       [31:0]  output enable (1=output, 0=input) (read/write)
//   0x18  GPIO_OE_SET   [31:0]  atomic bit-set on GPIO_OE (write-only, reads as GPIO_OE)
//   0x1C  GPIO_OE_CLR   [31:0]  atomic bit-clear on GPIO_OE (write-only, reads as GPIO_OE)
//   0x20  GPIO_OE_XOR   [31:0]  atomic bit-toggle on GPIO_OE (write-only, reads as GPIO_OE)
//
// The SET/CLR/XOR aliases let firmware do atomic bit manipulation without
// read-modify-write, which matters for concurrent access from two cores.
//
// Not implemented (RP2040 SIO/IO_BANK0/PADS differences):
//   IO_BANK0 FUNCSEL     — per-pin function mux (GPIO/UART/SPI/PIO); handled
//                          at SoC level by the bus decoder and PIO GPIO mux
//   IO_BANK0 overrides   — OUTOVER, OEOVER, INOVER, IRQOVER per pin
//   IO_BANK0 interrupts  — per-pin edge/level detect, per-core IRQ routing
//   PADS_BANK0           — drive strength, slew rate, pull-up/down, schmitt,
//                          input enable (ASIC-only, no effect on FPGA)
//   GPIO_HI_*            — QSPI pin GPIO aliases (not applicable)
//
// Known limitations:
//   - gpio_in is sampled directly (no 2-FF synchronizer); add one if inputs
//     come from an asynchronous domain (e.g. external pins)
//   - No per-pin function mux: all 32 bits are GPIO; peripheral pin routing
//     is fixed at the SoC level
//   - No interrupt generation (level/edge detect not implemented)
//   - SET/CLR/XOR reads return the base register value (matches RP2040 SIO)
//
// AHB pipeline: address phase registers htrans/hwrite/haddr; data phase captures
// hwdata for writes and returns hrdata combinationally for reads.

`default_nettype none

module gpio (
    input  wire        clk,
    input  wire        rst_n,

    // AHB-Lite slave port
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] haddr,
    input  wire        hwrite,
    input  wire [1:0]  htrans,
    input  wire [2:0]  hsize,
    input  wire [31:0] hwdata,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [31:0] hrdata,
    output wire        hready,
    output wire        hresp,

    // GPIO pins
    input  wire [31:0] gpio_in,
    output reg  [31:0] gpio_out,
    output reg  [31:0] gpio_oe
);

// ---------------------------------------------------------------------------
// AHB pipeline

wire active = htrans[1];
reg  active_r, hwrite_r;
reg  [5:2] reg_addr_r;   // word address: 0x00–0x20 → 0–8

always @(posedge clk) begin
    active_r   <= active;
    hwrite_r   <= hwrite;
    reg_addr_r <= haddr[5:2];
end

// ---------------------------------------------------------------------------
// Register writes

wire wr = active_r && hwrite_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        gpio_out <= 32'h0;
        gpio_oe  <= 32'h0;
    end else if (wr) begin
        case (reg_addr_r)
            4'd1: gpio_out <= hwdata;                  // OUT direct
            4'd2: gpio_out <= gpio_out | hwdata;       // OUT_SET
            4'd3: gpio_out <= gpio_out & ~hwdata;      // OUT_CLR
            4'd4: gpio_out <= gpio_out ^ hwdata;       // OUT_XOR
            4'd5: gpio_oe  <= hwdata;                  // OE direct
            4'd6: gpio_oe  <= gpio_oe | hwdata;        // OE_SET
            4'd7: gpio_oe  <= gpio_oe & ~hwdata;       // OE_CLR
            4'd8: gpio_oe  <= gpio_oe ^ hwdata;        // OE_XOR
            default: ;
        endcase
    end
end

// ---------------------------------------------------------------------------
// AHB read

assign hrdata = (reg_addr_r == 4'd0) ? gpio_in    :  // IN
                (reg_addr_r <= 4'd4)  ? gpio_out   :  // OUT, SET, CLR, XOR all read OUT
                (reg_addr_r <= 4'd8)  ? gpio_oe    :  // OE, SET, CLR, XOR all read OE
                                             32'h0;

assign hready = 1'b1;
assign hresp  = 1'b0;

endmodule
