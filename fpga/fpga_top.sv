`default_nettype none

// Basys3 top-level wrapper for rxpio32.
// Clock: 100 MHz onboard oscillator (W5)
// Reset: btnC (T17), active-high → inverted to rst_n
// GPIO:  gpio_out[15:0] → LD15:LD0
// SW:    sw[15:0] → pio_gpio_in[15:0]

module fpga_top (
    input  wire        clk,
    input  wire        reset,
    output wire [15:0] led,
    input  wire [15:0] sw
);

wire rst_n = ~reset;

wire [31:0] gpio_out;
wire [31:0] pio_gpio_out;
wire [31:0] pio_gpio_oe;
wire [7:0]  pio_irq;

assign led = gpio_out[15:0];

rxpio32 soc (
    .clk          (clk),
    .rst_n        (rst_n),

    // JTAG debug — tied off (no external debugger in this build)
    .tck          (1'b0),
    .trst_n       (1'b1),
    .tms          (1'b1),
    .tdi          (1'b0),
    .tdo          (),

    .gpio_out     (gpio_out),
    .pio_gpio_in  ({16'b0, sw}),
    .pio_gpio_out (pio_gpio_out),
    .pio_gpio_oe  (pio_gpio_oe),
    .pio_irq      (pio_irq),

    // UART — unused on Basys3 for now
    .uart_tx      (),
    .uart_rx      (1'b1),

    // SPI flash — tied off (no flash attached in this build)
    .spi_cs_n     (),
    .spi_sck      (),
    .spi_mosi     (),
    .spi_miso     (1'b0)
);

endmodule
