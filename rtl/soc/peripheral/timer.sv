// timer.sv — AHB-Lite RISC-V mtime/mtimecmp timer peripheral.
//
// Register map (byte offset from base):
//   0x00  CTRL       [0]     enable counter
//   0x04  PRESCALER  [15:0]  tick = clk / (PRESCALER+1)
//   0x08  MTIME      [31:0]  counter low  (read/write)
//   0x0C  MTIMEH     [31:0]  counter high (read/write)
//   0x10  MTIMECMP   [31:0]  compare low  (read/write)
//   0x14  MTIMECMPH  [31:0]  compare high (read/write)
//
// timer_irq asserts when mtime >= mtimecmp.
// dbg_halt freezes the counter during debug.

`default_nettype none

module timer (
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

    // Timer interrupt
    output wire        timer_irq
);

// ---------------------------------------------------------------------------
// AHB pipeline registers

wire active = htrans[1];
reg  active_r, hwrite_r;
reg  [4:2] reg_addr_r;

always @(posedge clk) begin
    active_r   <= active;
    hwrite_r   <= hwrite;
    reg_addr_r <= haddr[4:2];
end

// ---------------------------------------------------------------------------
// Register word-address constants (byte_offset >> 2)

localparam [2:0] ADDR_CTRL      = 3'h0; // 0x00
localparam [2:0] ADDR_PRESCALER = 3'h1; // 0x04
localparam [2:0] ADDR_MTIME     = 3'h2; // 0x08
localparam [2:0] ADDR_MTIMEH    = 3'h3; // 0x0C
localparam [2:0] ADDR_MTIMECMP  = 3'h4; // 0x10
localparam [2:0] ADDR_MTIMECMPH = 3'h5; // 0x14

// ---------------------------------------------------------------------------
// Configuration registers

reg        ctrl_en;
reg [15:0] prescaler;

// ---------------------------------------------------------------------------
// Prescaler — counts down from PRESCALER, emits tick on zero

reg [15:0] pre_cnt;
wire       tick = ctrl_en && !dbg_halt && (pre_cnt == 16'h0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pre_cnt <= 16'h0;
    else if (!ctrl_en || dbg_halt)
        pre_cnt <= prescaler;
    else if (pre_cnt == 16'h0)
        pre_cnt <= prescaler;
    else
        pre_cnt <= pre_cnt - 16'd1;
end

// ---------------------------------------------------------------------------
// 64-bit mtime counter

reg [63:0] mtime;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mtime <= 64'h0;
    end else begin
        if (tick)
            mtime <= mtime + 64'd1;
        // Bus writes override — checked after tick so write wins
        if (active_r && hwrite_r && reg_addr_r == ADDR_MTIME)
            mtime[31:0] <= hwdata;
        if (active_r && hwrite_r && reg_addr_r == ADDR_MTIMEH)
            mtime[63:32] <= hwdata;
    end
end

// ---------------------------------------------------------------------------
// 64-bit mtimecmp — stored inverted for LUT savings on comparison

reg [63:0] mtimecmp_inv;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mtimecmp_inv <= 64'h0;
    end else begin
        if (active_r && hwrite_r && reg_addr_r == ADDR_MTIMECMP)
            mtimecmp_inv[31:0] <= ~hwdata;
        if (active_r && hwrite_r && reg_addr_r == ADDR_MTIMECMPH)
            mtimecmp_inv[63:32] <= ~hwdata;
    end
end

// mtime >= mtimecmp  ↔  mtime + ~mtimecmp + 1 doesn't borrow  ↔  carry out = 1
/* verilator lint_off UNUSEDSIGNAL */
wire [64:0] cmp_diff = {1'b0, mtime} + {1'b0, mtimecmp_inv} + 65'd1;
/* verilator lint_on UNUSEDSIGNAL */

reg timer_irq_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        timer_irq_r <= 1'b0;
    else
        timer_irq_r <= cmp_diff[64];
end

assign timer_irq = timer_irq_r;

// ---------------------------------------------------------------------------
// AHB write handler

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ctrl_en   <= 1'b1;    // enabled by default (RISC-V convention)
        prescaler <= 16'h0;   // default: tick every clock
    end else if (active_r && hwrite_r) begin
        case (reg_addr_r)
            ADDR_CTRL:      ctrl_en   <= hwdata[0];
            ADDR_PRESCALER: prescaler <= hwdata[15:0];
            default: ;
        endcase
    end
end

// ---------------------------------------------------------------------------
// AHB read data (combinational)

assign hrdata = (reg_addr_r == ADDR_CTRL)      ? {31'h0, ctrl_en}        :
                (reg_addr_r == ADDR_PRESCALER)  ? {16'h0, prescaler}     :
                (reg_addr_r == ADDR_MTIME)      ? mtime[31:0]            :
                (reg_addr_r == ADDR_MTIMEH)     ? mtime[63:32]           :
                (reg_addr_r == ADDR_MTIMECMP)   ? ~mtimecmp_inv[31:0]    :
                (reg_addr_r == ADDR_MTIMECMPH)  ? ~mtimecmp_inv[63:32]   :
                                                  32'h0;

assign hready = 1'b1;
assign hresp  = 1'b0;

endmodule
