// Single 32-bit GPIO output register, AHB-Lite slave.
// One address, one register: write sets gpio_out, read returns it.
//
// AHB pipeline: address phase (htrans/hwrite) is registered, then hwdata
// is captured on the following cycle — same pattern as sram_bank.

`default_nettype none

module gpio (
    input  wire        clk,
    input  wire        rst_n,

    // AHB slave port
    input  wire [31:0] haddr,
    input  wire        hwrite,
    input  wire [1:0]  htrans,
    input  wire [31:0] hwdata,
    output wire [31:0] hrdata,
    output wire        hready,
    output wire        hresp,

    // GPIO output pins
    output reg  [31:0] gpio_out
);

wire active = htrans[1];

// Register address-phase signals
reg hwrite_r;
reg active_r;

always @(posedge clk) begin
    hwrite_r <= hwrite;
    active_r <= active;
end

// Write
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        gpio_out <= 32'h0;
    else if (active_r && hwrite_r)
        gpio_out <= hwdata;
end

// Read — combinational (gpio_out is already a register)
assign hrdata = gpio_out;
assign hready = 1'b1;
assign hresp  = 1'b0;

endmodule
