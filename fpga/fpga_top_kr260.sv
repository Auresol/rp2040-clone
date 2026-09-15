`default_nettype none

// KR260 SoC wrapper — clock and reset come from ps_bd_wrapper via kr260_top.
//
// GPIO mux (per-bit): if pio_gpio_oe[i]=1, PIO drives rpi_gpio[i];
//                     otherwise gpio peripheral drives rpi_gpio[i].
// This lets PIO SET/OUT instructions control RPi header pins autonomously.

module fpga_top_kr260 (
    input  wire       clk,
    input  wire       rst_n,        // active-low, from PS FCLK_RESET0_N
    output wire [7:0] rpi_gpio
);

// ---------------------------------------------------------------------------
// Reset synchronizer: 4-cycle stretch on PS reset into clk domain
// ---------------------------------------------------------------------------

reg [3:0] rst_pipe = 4'hF;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rst_pipe <= 4'hF;
    else
        rst_pipe <= {rst_pipe[2:0], 1'b0};
end

wire rst_n_sync = ~rst_pipe[3];

// ---------------------------------------------------------------------------
// SoC
// ---------------------------------------------------------------------------

wire [31:0] gpio_out;
wire [31:0] pio_gpio_out;
wire [31:0] pio_gpio_oe;
wire [7:0]  pio_irq;

rxpsm32 soc (
    .clk          (clk),
    .rst_n        (rst_n_sync),

    // JTAG debug — tied off (no external debugger in this build)
    .tck          (1'b0),
    .trst_n       (1'b1),
    .tms          (1'b1),
    .tdi          (1'b0),
    .tdo          (),

    .gpio_out     (gpio_out),
    .pio_gpio_in  (32'b0),
    .pio_gpio_out (pio_gpio_out),
    .pio_gpio_oe  (pio_gpio_oe),
    .pio_irq      (pio_irq),

    // UART — unused for now
    .uart_tx      (),
    .uart_rx      (1'b1),

    // SPI flash — tied off (no flash attached in this build)
    .spi_cs_n     (),
    .spi_sck      (),
    .spi_mosi     (),
    .spi_miso     (1'b0),

    // SPI0 — tied off (no SPI slave attached in this build)
    .spi0_sclk    (),
    .spi0_mosi    (),
    .spi0_miso    (1'b0),
    .spi0_cs_n    ()
);

// Per-bit mux: PIO output-enable takes priority over GPIO peripheral.
assign rpi_gpio = (pio_gpio_out[7:0] &  pio_gpio_oe[7:0])
                | (gpio_out[7:0]     & ~pio_gpio_oe[7:0]);

endmodule
