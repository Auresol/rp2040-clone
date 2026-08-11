`default_nettype none

// KR260 top-level wrapper for rvsoc_top.
//
// Clock:  Single-ended 25 MHz reference from KD240 RPi header (J2 pin 7).
//         MMCM generates 100 MHz system clock.
//         ** Verify: J2-pin-7 = SOM240_1_D4 = PACKAGE_PIN H4 (bank 66) **
//         If using PS FCLK instead, remove the MMCM and IBUF below and
//         drive clk_100 directly from the PS FCLK output in the block design.
//
// Reset:  Active-high push button.
//         Using KD240 user push button (verify package pin in kr260.xdc).
//
// GPIO:   gpio_out[7:0] → PMOD J7 pins 1-4, 7-10 (8 data pins).
//         pio_gpio_in tied to 0 (no switches on KR260 carrier).
//
// IO standard: LVCMOS18 throughout (bank 66, VCCO = 1.8V).

module fpga_top_kr260 (
    input  wire       clk_25mhz,   // 25 MHz reference from KD240 carrier
    output wire [5:0] pmod          // PMOD J7 data pins → gpio_out[5:0]
                                    // (6 confirmed-valid pins on sfvc784 package)
);

// ---------------------------------------------------------------------------
// MMCM: 25 MHz → 100 MHz
// CLKFBOUT_MULT_F = 40, DIVCLK_DIVIDE = 1 → VCO = 1000 MHz
// CLKOUT0_DIVIDE_F = 10 → 100 MHz
// ---------------------------------------------------------------------------

wire clk_25mhz_buf, clk_fb, clk_100_mmcm, clk_100;
wire mmcm_locked;

// BUFG on the input path so the MMCM is not constrained to the same
// clock region as the IOB (Place 30-681 workaround).
BUFG bufg_clkin (.I(clk_25mhz), .O(clk_25mhz_buf));

MMCME2_BASE #(
    .CLKIN1_PERIOD    (40.0),   // 25 MHz input
    .CLKFBOUT_MULT_F  (40.0),   // VCO = 25 * 40 / 1 = 1000 MHz
    .DIVCLK_DIVIDE    (1),
    .CLKOUT0_DIVIDE_F (10.0),   // 1000 / 10 = 100 MHz
    .BANDWIDTH        ("OPTIMIZED"),
    .STARTUP_WAIT     ("FALSE")
) mmcm_inst (
    .CLKIN1   (clk_25mhz_buf),
    .CLKFBIN  (clk_fb),
    .CLKFBOUT (clk_fb),
    .CLKOUT0  (clk_100_mmcm),
    .LOCKED   (mmcm_locked),
    .PWRDWN   (1'b0),
    .RST      (1'b0)
);

BUFG bufg_sys (.I(clk_100_mmcm), .O(clk_100));

// ---------------------------------------------------------------------------
// Reset: hold in reset until MMCM locks; button also forces reset
// ---------------------------------------------------------------------------

reg [3:0] rst_pipe = 4'hF;
always @(posedge clk_100 or negedge mmcm_locked) begin
    if (!mmcm_locked)
        rst_pipe <= 4'hF;
    else
        rst_pipe <= {rst_pipe[2:0], 1'b0};
end

wire rst_n = ~rst_pipe[3];

// ---------------------------------------------------------------------------
// SoC
// ---------------------------------------------------------------------------

wire [31:0] gpio_out;
wire [31:0] pio_gpio_out;
wire [31:0] pio_gpio_oe;
wire [7:0]  pio_irq;

rvsoc_top soc (
    .clk          (clk_100),
    .rst_n        (rst_n),
    .gpio_out     (gpio_out),
    .pio_gpio_in  (32'b0),      // no external GPIO in on KR260 carrier
    .pio_gpio_out (pio_gpio_out),
    .pio_gpio_oe  (pio_gpio_oe),
    .pio_irq      (pio_irq)
);

assign pmod = gpio_out[5:0];

endmodule
