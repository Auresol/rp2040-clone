// pio_sm.sv — RP2040 PIO State Machine (single instance)
//
// Implements all 9 instruction types: JMP, WAIT, IN, OUT, PUSH, PULL, MOV, IRQ, SET.
// Clock divider with 16-bit integer + 8-bit fractional accumulator.
// Side-set applied on instruction execution cycle (not during delay stall).
//
// LUT optimizations vs original:
//   Step 1 — apply_sideset called once (was 8×); saves ~700 LUTs/SM
//   Step 2 — write_pins called once via mux (was 5×); saves ~500 LUTs/SM
//   Step 3 — stall re-check shares WAIT/IRQ decode with fresh path; saves ~300 LUTs/SM

`default_nettype none

module pio_sm #(
    parameter SM_IDX = 0
) (
    input  wire        clk,
    input  wire        rst_n,

    // From CTRL register (one-shot pulses driven by pio_top)
    input  wire        enable,
    input  wire        restart,        // clears PC→0, ISR, OSR, ISC, OSC, delay counter
    input  wire        clkdiv_restart, // resets clock divider phase

    // Configuration registers
    input  wire [31:0] clkdiv,    // [31:16]=INT, [15:8]=FRAC
    input  wire [31:0] execctrl,  // [30]=SIDE_EN,[29]=SIDE_PINDIR,[28:24]=JMP_PIN,
                                  // [16:12]=WRAP_TOP,[11:7]=WRAP_BOTTOM,
                                  // [4]=STATUS_SEL,[3:0]=STATUS_N
    input  wire [31:0] shiftctrl, // [31]=FJOIN_RX,[30]=FJOIN_TX,[29:25]=PULL_THRESH,
                                  // [24:20]=PUSH_THRESH,[19]=OUT_SHIFTDIR,[18]=IN_SHIFTDIR,
                                  // [17]=AUTOPULL,[16]=AUTOPUSH
    input  wire [31:0] pinctrl,   // [31:29]=SIDESET_COUNT,[28:26]=SET_COUNT,[25:20]=OUT_COUNT,
                                  // [19:15]=IN_BASE,[14:10]=SIDESET_BASE,[9:5]=SET_BASE,[4:0]=OUT_BASE

    // Instruction memory (shared 32x16)
    input  wire [15:0] instr_mem [0:31],

    // TX FIFO interface (SM pulls from this)
    output wire        tx_pop,
    input  wire [31:0] tx_rdata,
    input  wire        tx_empty,

    // RX FIFO interface (SM pushes into this)
    output wire        rx_push,
    output wire [31:0] rx_wdata,
    input  wire        rx_full,

    // GPIO
    input  wire [31:0] gpio_in,
    output reg  [31:0] gpio_out,
    output reg  [31:0] gpio_oe,

    // IRQ flags shared across the PIO block
    input  wire [7:0]  irq_flags,
    output wire [7:0]  irq_set,
    output wire [7:0]  irq_clr,

    // Force-execute from SM_INSTR register write
    input  wire [15:0] exec_instr,
    input  wire        exec_vld,   // pulse when new exec_instr written

    // Status outputs
    output wire        exec_stalled,
    output wire [4:0]  pc_out,
    output wire [15:0] instr_out,
    output wire        txstall,
    output wire        txover,
    output wire        rxunder,
    output wire        rxstall
);

// ============================================================================
// Configuration field extraction
// ============================================================================
wire [15:0] cfg_clkdiv_int  = clkdiv[31:16];
wire [7:0]  cfg_clkdiv_frac = clkdiv[15:8];

wire        cfg_side_en      = execctrl[30];
wire        cfg_side_pindir  = execctrl[29];
wire [4:0]  cfg_jmp_pin      = execctrl[28:24];
wire [4:0]  cfg_wrap_top     = execctrl[16:12];
wire [4:0]  cfg_wrap_bottom  = execctrl[11:7];
wire        cfg_status_sel   = execctrl[4];
wire [3:0]  cfg_status_n     = execctrl[3:0];

wire        cfg_fjoin_rx     = shiftctrl[31];
wire        cfg_fjoin_tx     = shiftctrl[30];
wire [4:0]  cfg_pull_thresh  = shiftctrl[29:25]; // 0 means 32
wire [4:0]  cfg_push_thresh  = shiftctrl[24:20]; // 0 means 32
wire        cfg_out_shiftdir = shiftctrl[19];    // 1=right
wire        cfg_in_shiftdir  = shiftctrl[18];    // 1=right
wire        cfg_autopull     = shiftctrl[17];
wire        cfg_autopush     = shiftctrl[16];

wire [2:0]  cfg_sideset_count = pinctrl[31:29];
wire [2:0]  cfg_set_count     = pinctrl[28:26];
wire [5:0]  cfg_out_count     = pinctrl[25:20];
wire [4:0]  cfg_in_base       = pinctrl[19:15];
wire [4:0]  cfg_sideset_base  = pinctrl[14:10];
wire [4:0]  cfg_set_base      = pinctrl[9:5];
wire [4:0]  cfg_out_base      = pinctrl[4:0];

// Effective thresholds: 0 means 32
wire [5:0] pull_thresh_eff = (cfg_pull_thresh == 5'd0) ? 6'd32 : {1'b0, cfg_pull_thresh};
wire [5:0] push_thresh_eff = (cfg_push_thresh == 5'd0) ? 6'd32 : {1'b0, cfg_push_thresh};

// ============================================================================
// Clock divider
// ============================================================================
// FPGA build: counter narrowed to 8 bits (max divide = 256).
// Full RP2040 spec uses 16-bit INT (max 65536) — restore for ASIC if needed.
// Saves ~80 LUTs/SM (×8 SMs = 640 LUTs) vs 16-bit on Artix-7.
reg [7:0]  clkdiv_cnt;
reg [7:0]  clkdiv_frac_acc;
reg        tick;

wire [7:0] clkdiv_int_eff = (cfg_clkdiv_int[15:8] != 8'd0) ? 8'd255 :   // saturate if upper byte set
                             (cfg_clkdiv_int[7:0]  == 8'd0) ? 8'd1   :   // 0 → 1 (divide-by-1)
                                                               cfg_clkdiv_int[7:0];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clkdiv_cnt      <= 8'd1;
        clkdiv_frac_acc <= 8'd0;
        tick            <= 1'b0;
    end else if (!enable) begin
        clkdiv_cnt      <= clkdiv_int_eff;
        clkdiv_frac_acc <= 8'd0;
        tick            <= 1'b0;
    end else if (clkdiv_restart) begin
        clkdiv_cnt      <= clkdiv_int_eff;
        clkdiv_frac_acc <= 8'd0;
        tick            <= 1'b0;
    end else begin
        if (clkdiv_int_eff == 8'd1 && cfg_clkdiv_frac == 8'd0) begin
            tick <= 1'b1;
        end else if (clkdiv_cnt == 8'd1) begin
            tick <= 1'b1;
            begin
                automatic logic [8:0] new_frac = {1'b0, clkdiv_frac_acc} + {1'b0, cfg_clkdiv_frac};
                clkdiv_frac_acc <= new_frac[7:0];
                clkdiv_cnt <= clkdiv_int_eff + {7'd0, new_frac[8]};
            end
        end else begin
            tick       <= 1'b0;
            clkdiv_cnt <= clkdiv_cnt - 8'd1;
        end
    end
end

// ============================================================================
// State machine registers
// ============================================================================
reg [4:0]  pc;
reg [31:0] x_reg;
reg [31:0] y_reg;
reg [31:0] isr;
reg [5:0]  isc;
reg [31:0] osr;
reg [5:0]  osc;
reg [4:0]  delay_cnt;
reg        stalled;
reg        force_exec;
reg [15:0] forced_instr;

reg [7:0]  irq_set_r;
reg [7:0]  irq_clr_r;

reg        tx_pop_r;
reg        rx_push_r;
reg [31:0] rx_wdata_r;

reg        txstall_r;
reg        txover_r;
reg        rxunder_r;
reg        rxstall_r;

assign tx_pop      = tx_pop_r;
assign rx_push     = rx_push_r;
assign rx_wdata    = rx_wdata_r;
assign irq_set     = irq_set_r;
assign irq_clr     = irq_clr_r;
assign exec_stalled= stalled;
assign pc_out      = pc;
assign instr_out   = force_exec ? forced_instr : instr_mem[pc];
assign txstall     = txstall_r;
assign txover      = txover_r;
assign rxunder     = rxunder_r;
assign rxstall     = rxstall_r;

// ============================================================================
// Instruction fetch
// ============================================================================
wire [15:0] cur_instr = force_exec ? forced_instr : instr_mem[pc];

wire [2:0] opcode    = cur_instr[15:13];
wire [4:0] delay_side = cur_instr[12:8];
wire [7:0] op_data   = cur_instr[7:0];

wire [2:0] sideset_bits     = cfg_side_en ? (cfg_sideset_count - 3'd1) : cfg_sideset_count;
wire [2:0] delay_bits_count = 3'd5 - cfg_sideset_count;

wire side_en_bit  = cfg_side_en ? delay_side[4] : 1'b1;
wire [4:0] side_data = cfg_side_en
    ? (delay_side[4:0] & (5'hFF >> (4 - (cfg_sideset_count - 3'd1))))
    : delay_side[4:0];

wire [4:0] delay_val;
generate
    assign delay_val = (delay_side >> cfg_sideset_count) & ((5'h1F) >> cfg_sideset_count);
endgenerate

// ============================================================================
// PINS read helper
// ============================================================================
function automatic [31:0] read_pins_out_range;
    input [31:0] gpio;
    input [4:0]  base;
    input [5:0]  count;
    read_pins_out_range = (gpio >> base) & ((count == 6'd0) ? 32'hFFFF_FFFF : ((32'd1 << count) - 32'd1));
endfunction

// ============================================================================
// Combinational next-state logic
// ============================================================================
reg [4:0]  next_pc;
reg [31:0] next_x;
reg [31:0] next_y;
reg [31:0] next_isr;
reg [5:0]  next_isc;
reg [31:0] next_osr;
reg [5:0]  next_osc;
reg [4:0]  next_delay_cnt;
reg        next_stalled;
reg        next_force_exec;
reg [15:0] next_forced_instr;
reg [31:0] next_gpio_out;
reg [31:0] next_gpio_oe;

reg [7:0]  comb_irq_set;
reg [7:0]  comb_irq_clr;
reg        comb_tx_pop;
reg        comb_rx_push;
reg [31:0] comb_rx_wdata;
reg        comb_txstall;
reg        comb_txover;
reg        comb_rxunder;
reg        comb_rxstall;

// Helper: bit-reverse 32-bit value
function automatic [31:0] bit_reverse32;
    input [31:0] val;
    integer i;
    for (i = 0; i < 32; i = i + 1)
        bit_reverse32[i] = val[31-i];
endfunction

// Helper: extract N bits from gpio_in starting at IN_BASE (wraps at 32)
function automatic [31:0] read_gpio_in_bits;
    input [31:0] gpio;
    input [4:0]  base;
    input [5:0]  count;
    reg [5:0] cnt;
    reg [31:0] rotated;
    begin
        cnt     = (count == 6'd0) ? 6'd32 : count;
        rotated = (gpio >> base) | (gpio << (6'd32 - {1'b0, base}));
        read_gpio_in_bits = rotated & ((cnt == 6'd32) ? 32'hFFFF_FFFF : ((32'd1 << cnt) - 32'd1));
    end
endfunction

always @(*) begin
    // Defaults: hold state
    next_pc           = pc;
    next_x            = x_reg;
    next_y            = y_reg;
    next_isr          = isr;
    next_isc          = isc;
    next_osr          = osr;
    next_osc          = osc;
    next_delay_cnt    = delay_cnt;
    next_stalled      = stalled;
    next_force_exec   = force_exec;
    next_forced_instr = forced_instr;
    next_gpio_out     = gpio_out;
    next_gpio_oe      = gpio_oe;

    comb_irq_set  = 8'd0;
    comb_irq_clr  = 8'd0;
    comb_tx_pop   = 1'b0;
    comb_rx_push  = 1'b0;
    comb_rx_wdata = 32'd0;
    comb_txstall  = 1'b0;
    comb_txover   = 1'b0;
    comb_rxunder  = 1'b0;
    comb_rxstall  = 1'b0;

    if (enable && tick) begin
        if (delay_cnt > 5'd0) begin
            next_delay_cnt = delay_cnt - 5'd1;
        end else begin
            begin : exec_block
                // ---- working variables ----
                reg [31:0] status_val;
                reg        pc_written;
                reg        do_stall;
                reg [4:0]  irq_num;
                reg [31:0] src_val;
                reg [5:0]  shift_n;
                reg [2:0]  jmp_cond;
                reg [4:0]  jmp_addr;
                reg        jmp_taken;
                reg [2:0]  in_src;
                reg [2:0]  out_dst;
                reg [2:0]  mov_dst;
                reg [1:0]  mov_op;
                reg [2:0]  mov_src;
                reg [2:0]  set_dst;
                reg [4:0]  set_data;
                reg        iffull_noblock;
                reg        ifempty_noblock;

                // ---- Step 2: pin-write mux ----
                // Set these instead of calling write_pins directly; single call at end.
                reg [31:0] pin_wdata;
                reg [4:0]  pin_wbase;
                reg [5:0]  pin_wcount;
                reg        pin_wdst;    // 0=gpio_out, 1=gpio_oe
                reg        pin_do_write;

                // ---- Step 3: shared WAIT/IRQ decode ----
                // Computed once before the stalled/fresh split.
                reg        wait_pol_s;
                reg [1:0]  wait_src_s;
                reg [4:0]  wait_idx_s;
                reg        wait_cond_s;

                // --- defaults ---
                pc_written   = 1'b0;
                do_stall     = 1'b0;
                pin_wdata    = 32'd0;
                pin_wbase    = 5'd0;
                pin_wcount   = 6'd0;
                pin_wdst     = 1'b0;
                pin_do_write = 1'b0;

                // STATUS approximation
                if (cfg_status_sel == 1'b0)
                    status_val = (tx_empty && (cfg_status_n != 4'd0)) ? 32'hFFFF_FFFF : 32'h0000_0000;
                else
                    status_val = (!rx_full && (cfg_status_n != 4'd0)) ? 32'hFFFF_FFFF : 32'h0000_0000;

                // ---- Shared WAIT condition (Step 3) ----
                wait_pol_s = op_data[6];
                wait_src_s = op_data[5:4];
                wait_idx_s = {1'b0, op_data[3:0]};
                case (wait_src_s)
                    2'b00:   wait_cond_s = (gpio_in[wait_idx_s] == wait_pol_s);
                    2'b01:   wait_cond_s = (gpio_in[(cfg_in_base + wait_idx_s) & 5'h1F] == wait_pol_s);
                    2'b10:   wait_cond_s = (irq_flags[wait_idx_s[2:0]] == wait_pol_s);
                    default: wait_cond_s = 1'b1;
                endcase

                // ---- Shared IRQ number (Step 3) ----
                irq_num = resolve_irq_num(op_data[4:0], SM_IDX[1:0]);

                // ==============================================================
                // STALL RE-CHECK PATH
                // Uses shared decode — no duplicate casez.
                // ==============================================================
                if (stalled) begin
                    case (opcode)
                        3'b001: begin // WAIT
                            if (wait_cond_s) begin
                                if (wait_src_s == 2'b10 && wait_pol_s == 1'b1)
                                    comb_irq_clr[wait_idx_s[2:0]] = 1'b1;
                                next_delay_cnt = delay_val;
                                next_pc        = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                            end else
                                do_stall = 1'b1;
                        end

                        3'b100: begin // PUSH / PULL
                            if (op_data[7] == 1'b0) begin // PUSH
                                if (!rx_full) begin
                                    comb_rx_push   = 1'b1;
                                    comb_rx_wdata  = isr;
                                    next_isr       = 32'd0;
                                    next_isc       = 6'd0;
                                    next_delay_cnt = delay_val;
                                    next_pc        = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                                end else
                                    do_stall = 1'b1;
                            end else begin // PULL
                                if (!tx_empty) begin
                                    comb_tx_pop    = 1'b1;
                                    next_osr       = tx_rdata;
                                    next_osc       = 6'd0;
                                    next_delay_cnt = delay_val;
                                    next_pc        = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                                end else
                                    do_stall = 1'b1;
                            end
                        end

                        3'b110: begin // IRQ
                            if (!irq_flags[irq_num[2:0]]) begin
                                next_delay_cnt = delay_val;
                                next_pc        = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                            end else
                                do_stall = 1'b1;
                        end

                        default: ; // shouldn't happen — unstall next cycle
                    endcase

                    next_stalled = do_stall;

                end else begin
                    // ==============================================================
                    // FRESH EXECUTE PATH
                    // ==============================================================
                    casez (opcode)

                        // ----------------------------------------------------------
                        // JMP (000)
                        // ----------------------------------------------------------
                        3'b000: begin
                            jmp_cond  = op_data[7:5];
                            jmp_addr  = op_data[4:0];
                            jmp_taken = 1'b0;
                            case (jmp_cond)
                                3'b000: jmp_taken = 1'b1;
                                3'b001: jmp_taken = (x_reg == 32'd0);
                                3'b010: begin
                                    jmp_taken = (x_reg != 32'd0);
                                    next_x    = x_reg - 32'd1; // post-decrement always
                                end
                                3'b011: jmp_taken = (y_reg == 32'd0);
                                3'b100: begin
                                    jmp_taken = (y_reg != 32'd0);
                                    next_y    = y_reg - 32'd1;
                                end
                                3'b101: jmp_taken = (x_reg != y_reg);
                                3'b110: jmp_taken = (gpio_in[cfg_jmp_pin] == 1'b1);
                                3'b111: jmp_taken = (osc < pull_thresh_eff);
                                default: jmp_taken = 1'b0;
                            endcase
                            next_pc        = jmp_taken ? jmp_addr : wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                            pc_written     = 1'b1;
                            next_delay_cnt = delay_val;
                        end

                        // ----------------------------------------------------------
                        // WAIT (001) — uses shared decode (Step 3)
                        // ----------------------------------------------------------
                        3'b001: begin
                            if (wait_cond_s) begin
                                if (wait_src_s == 2'b10 && wait_pol_s == 1'b1)
                                    comb_irq_clr[wait_idx_s[2:0]] = 1'b1;
                                next_delay_cnt = delay_val;
                                next_pc        = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                            end else
                                do_stall = 1'b1;
                        end

                        // ----------------------------------------------------------
                        // IN (010)
                        // ----------------------------------------------------------
                        3'b010: begin
                            begin
                                reg [5:0] n;
                                in_src  = op_data[7:5];
                                shift_n = (op_data[4:0] == 5'd0) ? 6'd32 : {1'b0, op_data[4:0]};
                                n       = shift_n;

                                case (in_src)
                                    3'b000: src_val = read_gpio_in_bits(gpio_in, cfg_in_base, n);
                                    3'b001: src_val = x_reg;
                                    3'b010: src_val = y_reg;
                                    3'b011: src_val = 32'd0;
                                    3'b101: src_val = status_val;
                                    3'b110: src_val = isr;
                                    3'b111: src_val = osr;
                                    default: src_val = 32'd0;
                                endcase

                                if (cfg_in_shiftdir == 1'b0)
                                    next_isr = (n == 6'd32) ? src_val : ((isr << n) | (src_val & ((32'd1 << n) - 32'd1)));
                                else
                                    next_isr = (n == 6'd32) ? src_val : ((isr >> n) | (src_val << (6'd32 - n)));

                                next_isc = (isc + n > 6'd32) ? 6'd32 : (isc + n);

                                if (cfg_autopush && (next_isc >= push_thresh_eff)) begin
                                    if (!rx_full) begin
                                        comb_rx_push  = 1'b1;
                                        comb_rx_wdata = next_isr;
                                        next_isr      = 32'd0;
                                        next_isc      = 6'd0;
                                    end else begin
                                        do_stall = 1'b1;
                                        next_isr = isr;
                                        next_isc = isc;
                                    end
                                end
                            end
                            if (!do_stall) begin
                                next_delay_cnt = delay_val;
                                next_pc        = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                            end
                        end

                        // ----------------------------------------------------------
                        // OUT (011)
                        // ----------------------------------------------------------
                        3'b011: begin
                            begin
                                reg [5:0]  n;
                                reg [31:0] out_bits;
                                out_dst = op_data[7:5];
                                shift_n = (op_data[4:0] == 5'd0) ? 6'd32 : {1'b0, op_data[4:0]};
                                n       = shift_n;

                                if (cfg_out_shiftdir == 1'b1) begin
                                    out_bits = (n == 6'd32) ? osr : (osr & ((32'd1 << n) - 32'd1));
                                    next_osr = (n == 6'd32) ? 32'd0 : (osr >> n);
                                end else begin
                                    out_bits = (n == 6'd32) ? osr : (osr >> (6'd32 - n));
                                    next_osr = (n == 6'd32) ? 32'd0 : (osr << n);
                                end
                                next_osc = (osc + n > 6'd32) ? 6'd32 : (osc + n);

                                // Step 2: set pin-write mux instead of calling write_pins
                                case (out_dst)
                                    3'b000: begin // PINS
                                        pin_do_write = (cfg_out_count > 6'd0);
                                        pin_wdata    = out_bits;
                                        pin_wbase    = cfg_out_base;
                                        pin_wcount   = cfg_out_count;
                                        pin_wdst     = 1'b0;
                                    end
                                    3'b001: next_x = out_bits;
                                    3'b010: next_y = out_bits;
                                    3'b011: ; // NULL
                                    3'b100: begin // PINDIRS
                                        pin_do_write = (cfg_out_count > 6'd0);
                                        pin_wdata    = out_bits;
                                        pin_wbase    = cfg_out_base;
                                        pin_wcount   = cfg_out_count;
                                        pin_wdst     = 1'b1;
                                    end
                                    3'b101: begin // PC
                                        next_pc    = out_bits[4:0];
                                        pc_written = 1'b1;
                                    end
                                    3'b110: begin // ISR
                                        next_isr = out_bits;
                                        next_isc = 6'd0;
                                    end
                                    3'b111: begin // EXEC
                                        next_force_exec   = 1'b1;
                                        next_forced_instr = out_bits[15:0];
                                    end
                                    default: ;
                                endcase

                                if (cfg_autopull && (next_osc >= pull_thresh_eff)) begin
                                    if (!tx_empty) begin
                                        comb_tx_pop = 1'b1;
                                        next_osr    = tx_rdata;
                                        next_osc    = 6'd0;
                                    end else begin
                                        do_stall     = 1'b1;
                                        next_osr     = osr;
                                        next_osc     = osc;
                                        pin_do_write = 1'b0; // cancel pin write on stall
                                    end
                                end
                            end
                            if (!do_stall) begin
                                next_delay_cnt = delay_val;
                                if (!pc_written)
                                    next_pc = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                            end
                        end

                        // ----------------------------------------------------------
                        // PUSH (100, bit[7]=0) / PULL (100, bit[7]=1)
                        // ----------------------------------------------------------
                        3'b100: begin
                            if (op_data[7] == 1'b0) begin // PUSH
                                iffull_noblock = op_data[6];
                                begin
                                    reg noblock_p;
                                    noblock_p = op_data[5];
                                    if (iffull_noblock && (isc < push_thresh_eff)) begin
                                        // IFFULL: not full yet — NOP
                                    end else if (rx_full) begin
                                        if (!noblock_p)
                                            do_stall = 1'b1;
                                        else
                                            comb_rxstall = 1'b1;
                                    end else begin
                                        comb_rx_push  = 1'b1;
                                        comb_rx_wdata = isr;
                                        next_isr      = 32'd0;
                                        next_isc      = 6'd0;
                                    end
                                end
                            end else begin // PULL
                                ifempty_noblock = op_data[6];
                                begin
                                    reg noblock_q;
                                    noblock_q = op_data[5];
                                    if (ifempty_noblock && (osc < pull_thresh_eff)) begin
                                        // IFEMPTY: not empty yet — NOP
                                    end else if (tx_empty) begin
                                        if (!noblock_q) begin
                                            do_stall = 1'b1;
                                        end else begin
                                            next_osr     = x_reg;
                                            next_osc     = 6'd0;
                                            comb_txstall = 1'b1;
                                        end
                                    end else begin
                                        comb_tx_pop = 1'b1;
                                        next_osr    = tx_rdata;
                                        next_osc    = 6'd0;
                                    end
                                end
                            end
                            if (!do_stall) begin
                                next_delay_cnt = delay_val;
                                next_pc        = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                            end
                        end

                        // ----------------------------------------------------------
                        // MOV (101)
                        // ----------------------------------------------------------
                        3'b101: begin
                            begin
                                reg [31:0] mov_val;
                                mov_dst = op_data[7:5];
                                mov_op  = op_data[4:3];
                                mov_src = op_data[2:0];

                                case (mov_src)
                                    3'b000: mov_val = read_pins_out_range(gpio_in, cfg_out_base, {1'b0, cfg_out_count[4:0]});
                                    3'b001: mov_val = x_reg;
                                    3'b010: mov_val = y_reg;
                                    3'b011: mov_val = 32'd0;
                                    3'b100: mov_val = status_val;
                                    3'b110: mov_val = isr;
                                    3'b111: mov_val = osr;
                                    default: mov_val = 32'd0;
                                endcase

                                case (mov_op)
                                    2'b01: mov_val = ~mov_val;
                                    2'b10: mov_val = bit_reverse32(mov_val);
                                    default: ;
                                endcase

                                // Step 2: set pin-write mux instead of calling write_pins
                                case (mov_dst)
                                    3'b000: begin // PINS
                                        pin_do_write = (cfg_out_count > 6'd0);
                                        pin_wdata    = mov_val;
                                        pin_wbase    = cfg_out_base;
                                        pin_wcount   = cfg_out_count;
                                        pin_wdst     = 1'b0;
                                    end
                                    3'b001: next_x = mov_val;
                                    3'b010: next_y = mov_val;
                                    3'b100: begin // EXEC
                                        next_force_exec   = 1'b1;
                                        next_forced_instr = mov_val[15:0];
                                    end
                                    3'b101: begin // PC
                                        next_pc    = mov_val[4:0];
                                        pc_written = 1'b1;
                                    end
                                    3'b110: begin // ISR
                                        next_isr = mov_val;
                                        next_isc = 6'd0;
                                    end
                                    3'b111: begin // OSR
                                        next_osr = mov_val;
                                        next_osc = 6'd0;
                                    end
                                    default: ;
                                endcase
                            end
                            next_delay_cnt = delay_val;
                            if (!pc_written)
                                next_pc = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                        end

                        // ----------------------------------------------------------
                        // IRQ (110) — irq_num from shared decode (Step 3)
                        // ----------------------------------------------------------
                        3'b110: begin
                            begin
                                reg irq_clr_f;
                                reg irq_wait_f;
                                irq_clr_f  = op_data[6];
                                irq_wait_f = op_data[5];
                                if (irq_clr_f) begin
                                    comb_irq_clr[irq_num[2:0]] = 1'b1;
                                end else begin
                                    comb_irq_set[irq_num[2:0]] = 1'b1;
                                    if (irq_wait_f && irq_flags[irq_num[2:0]])
                                        do_stall = 1'b1;
                                end
                            end
                            if (!do_stall) begin
                                next_delay_cnt = delay_val;
                                next_pc        = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                            end
                        end

                        // ----------------------------------------------------------
                        // SET (111)
                        // ----------------------------------------------------------
                        3'b111: begin
                            set_dst  = op_data[7:5];
                            set_data = op_data[4:0];
                            // Step 2: set pin-write mux instead of calling write_pins
                            case (set_dst)
                                3'b000: begin // PINS
                                    pin_do_write = (cfg_set_count > 3'd0);
                                    pin_wdata    = {27'd0, set_data};
                                    pin_wbase    = cfg_set_base;
                                    pin_wcount   = {3'd0, cfg_set_count};
                                    pin_wdst     = 1'b0;
                                end
                                3'b001: next_x = {27'd0, set_data};
                                3'b010: next_y = {27'd0, set_data};
                                3'b100: begin // PINDIRS
                                    pin_do_write = (cfg_set_count > 3'd0);
                                    pin_wdata    = {27'd0, set_data};
                                    pin_wbase    = cfg_set_base;
                                    pin_wcount   = {3'd0, cfg_set_count};
                                    pin_wdst     = 1'b1;
                                end
                                default: ;
                            endcase
                            next_delay_cnt = delay_val;
                            next_pc        = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                        end

                        default: begin
                            next_delay_cnt = delay_val;
                            next_pc        = wrap_pc(pc, cfg_wrap_top, cfg_wrap_bottom);
                        end
                    endcase

                    next_stalled = do_stall;

                    if (force_exec && !do_stall)
                        next_force_exec = 1'b0;

                end // not stalled

                // ==============================================================
                // Unified GPIO writes — Steps 1 & 2
                //
                // Applied once here, after do_stall is resolved.
                // Side-set first (so pin writes take priority on overlap).
                // Neither block runs on a stall cycle.
                // ==============================================================
                if (!do_stall) begin
                    // Step 1: single apply_sideset call (was 8× across stall/fresh paths)
                    if (side_en_bit && cfg_sideset_count > 3'd0) begin
                        if (cfg_side_pindir)
                            next_gpio_oe  = apply_sideset(gpio_oe,  side_data, cfg_sideset_base, cfg_sideset_count);
                        else
                            next_gpio_out = apply_sideset(gpio_out, side_data, cfg_sideset_base, cfg_sideset_count);
                    end
                    // Step 2: single write_pins call (was 5× across OUT/MOV/SET)
                    if (pin_do_write) begin
                        if (pin_wdst)
                            next_gpio_oe  = write_pins(next_gpio_oe,  pin_wdata, pin_wbase, pin_wcount);
                        else
                            next_gpio_out = write_pins(next_gpio_out, pin_wdata, pin_wbase, pin_wcount);
                    end
                end

            end : exec_block
        end // delay_cnt == 0
    end // enable && tick

    // Forward combinational outputs
    irq_set_r  = comb_irq_set;
    irq_clr_r  = comb_irq_clr;
    tx_pop_r   = comb_tx_pop;
    rx_push_r  = comb_rx_push;
    rx_wdata_r = comb_rx_wdata;
    txstall_r  = comb_txstall;
    txover_r   = comb_txover;
    rxunder_r  = comb_rxunder;
    rxstall_r  = comb_rxstall;
end

// ============================================================================
// Helper functions
// ============================================================================

function automatic [4:0] wrap_pc;
    input [4:0] cur_pc;
    input [4:0] wrap_top;
    input [4:0] wrap_bottom;
    if (cur_pc == wrap_top)
        wrap_pc = wrap_bottom;
    else
        wrap_pc = cur_pc + 5'd1;
endfunction

function automatic [4:0] resolve_irq_num;
    input [4:0] raw;
    input [1:0] sm_idx;
    if (raw[4])
        resolve_irq_num = {1'b0, raw[3], 1'b0, ((raw[1:0] + sm_idx) & 2'b11)};
    else
        resolve_irq_num = {2'b0, raw[2:0]};
endfunction

// Write N bits into a 32-bit register at base (no wrap — within 32-bit word)
function automatic [31:0] write_pins;
    input [31:0] cur;
    input [31:0] data;
    input [4:0]  base;
    input [5:0]  count;
    reg [31:0] mask;
    reg [5:0]  cnt;
    begin
        cnt  = (count == 6'd0) ? 6'd32 : count;
        mask = (cnt == 6'd32) ? 32'hFFFF_FFFF : ((32'd1 << cnt) - 32'd1);
        write_pins = (cur & ~(mask << base)) | ((data & mask) << base);
    end
endfunction

function automatic [31:0] apply_sideset;
    input [31:0] cur;
    input [4:0]  data;
    input [4:0]  base;
    input [2:0]  count;
    reg [31:0] mask;
    begin
        if (count == 3'd0)
            apply_sideset = cur;
        else begin
            mask = (32'd1 << count) - 32'd1;
            apply_sideset = (cur & ~(mask << base)) | (({27'd0, data} & mask) << base);
        end
    end
endfunction

// ============================================================================
// Sequential state update
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pc           <= 5'd0;
        x_reg        <= 32'd0;
        y_reg        <= 32'd0;
        isr          <= 32'd0;
        isc          <= 6'd0;
        osr          <= 32'd0;
        osc          <= 6'd0;
        delay_cnt    <= 5'd0;
        stalled      <= 1'b0;
        force_exec   <= 1'b0;
        forced_instr <= 16'd0;
        gpio_out     <= 32'd0;
        gpio_oe      <= 32'd0;
    end else begin
        if (restart) begin
            pc        <= 5'd0;
            isr       <= 32'd0;
            isc       <= 6'd0;
            osr       <= 32'd0;
            osc       <= 6'd0;
            delay_cnt <= 5'd0;
            stalled   <= 1'b0;
        end

        if (exec_vld) begin
            force_exec   <= 1'b1;
            forced_instr <= exec_instr;
        end

        if (enable && tick && !restart) begin
            pc           <= next_pc;
            x_reg        <= next_x;
            y_reg        <= next_y;
            isr          <= next_isr;
            isc          <= next_isc;
            osr          <= next_osr;
            osc          <= next_osc;
            delay_cnt    <= next_delay_cnt;
            stalled      <= next_stalled;
            gpio_out     <= next_gpio_out;
            gpio_oe      <= next_gpio_oe;
            if (force_exec && !next_stalled) begin
                force_exec <= next_force_exec;
                if (next_force_exec)
                    forced_instr <= next_forced_instr;
            end else if (!force_exec && next_force_exec) begin
                force_exec   <= 1'b1;
                forced_instr <= next_forced_instr;
            end
        end
    end
end

endmodule
