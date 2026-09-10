// watchdog.sv — Watchdog timer with 1 MHz tick output.
//
// Down-counter decrements on each tick. If firmware doesn't kick it
// before it reaches zero, wdog_reset asserts for one cycle.
//
// Register map (byte offset from base):
//   0x00  CTRL      [0]  enable, [1] pause_on_debug, [31] force_reset (W1)
//   0x04  LOAD      [23:0]  reload value (max ~16.7M ticks = ~16.7s at 1 MHz)
//   0x08  COUNT     [23:0]  current counter (read-only)
//   0x0C  KICK      write 0x6B696B6B to reload counter from LOAD
//   0x10  REASON    [1:0]  reset reason: [0] watchdog timeout, [1] force reset
//                          (write-1-to-clear, sticky across resets)
//
// Outputs:
//   wdog_reset  — pulse when counter reaches zero or force triggered
//   tick_1mhz   — 1-cycle pulse at ~1 MHz (clk / CLK_HZ_DIV)

`default_nettype none

module watchdog #(
    parameter CLK_HZ = 100_000_000   // input clock frequency
)(
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

    // Debug halt — freeze counter
    input  wire        dbg_halt,

    // Outputs
    output reg         wdog_reset,
    output wire        tick_1mhz
);

localparam TICK_DIV = CLK_HZ / 1_000_000;  // e.g. 100 for 100 MHz
localparam KICK_MAGIC = 32'h6B696B6B;       // "kikk"

// ---------------------------------------------------------------------------
// AHB pipeline

wire active = htrans[1];
reg  active_r, hwrite_r;
reg  [4:2] reg_addr_r;

always @(posedge clk) begin
    active_r   <= active;
    hwrite_r   <= hwrite;
    reg_addr_r <= haddr[4:2];
end

localparam [2:0] ADDR_CTRL   = 3'd0,  // 0x00
                 ADDR_LOAD   = 3'd1,  // 0x04
                 ADDR_COUNT  = 3'd2,  // 0x08
                 ADDR_KICK   = 3'd3,  // 0x0C
                 ADDR_REASON = 3'd4;  // 0x10

// ---------------------------------------------------------------------------
// Prescaler — generates 1 MHz tick from system clock

reg [$clog2(TICK_DIV)-1:0] tick_cnt;
wire tick = (tick_cnt == 0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        tick_cnt <= 0;
    else if (tick_cnt == 0)
        tick_cnt <= TICK_DIV[$clog2(TICK_DIV)-1:0] - 1;
    else
        tick_cnt <= tick_cnt - 1;
end

assign tick_1mhz = tick;

// ---------------------------------------------------------------------------
// Registers and counter

reg        ctrl_en;
reg        ctrl_pause_dbg;
reg [23:0] load_val;
reg [23:0] counter;
reg [1:0]  reason;

wire pause = ctrl_pause_dbg && dbg_halt;
wire wr    = active_r && hwrite_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ctrl_en        <= 1'b0;
        ctrl_pause_dbg <= 1'b0;
        load_val       <= 24'h0;
        counter        <= 24'h0;
        reason         <= 2'b00;
        wdog_reset     <= 1'b0;
    end else begin
        wdog_reset <= 1'b0;

        // Counter tick
        if (ctrl_en && tick && !pause) begin
            if (counter == 24'h0) begin
                wdog_reset <= 1'b1;
                reason[0]  <= 1'b1;
            end else begin
                counter <= counter - 24'd1;
            end
        end

        // Register writes
        if (wr) begin
            case (reg_addr_r)
                ADDR_CTRL: begin
                    ctrl_en        <= hwdata[0];
                    ctrl_pause_dbg <= hwdata[1];
                    // Force reset (bit 31, write-1)
                    if (hwdata[31]) begin
                        wdog_reset <= 1'b1;
                        reason[1]  <= 1'b1;
                    end
                end
                ADDR_LOAD:
                    load_val <= hwdata[23:0];
                ADDR_KICK: begin
                    if (hwdata == KICK_MAGIC)
                        counter <= load_val;
                end
                ADDR_REASON:
                    reason <= reason & ~hwdata[1:0];
                default: ;
            endcase
        end
    end
end

// ---------------------------------------------------------------------------
// AHB read

assign hrdata = (reg_addr_r == ADDR_CTRL)   ? {30'h0, ctrl_pause_dbg, ctrl_en} :
                (reg_addr_r == ADDR_LOAD)    ? {8'h0, load_val}                 :
                (reg_addr_r == ADDR_COUNT)   ? {8'h0, counter}                  :
                (reg_addr_r == ADDR_KICK)    ? 32'h0                            :
                (reg_addr_r == ADDR_REASON)  ? {30'h0, reason}                  :
                                               32'h0;

assign hready = 1'b1;
assign hresp  = 1'b0;

endmodule
