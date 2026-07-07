`default_nettype none

// Basys3 top-level wrapper for rvsoc_top.
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

rvsoc_top soc (
    .clk          (clk),
    .rst_n        (rst_n),
    .gpio_out     (gpio_out),
    .pio_gpio_in  ({16'b0, sw}),
    .pio_gpio_out (pio_gpio_out),
    .pio_gpio_oe  (pio_gpio_oe),
    .pio_irq      (pio_irq)
);

endmodule
