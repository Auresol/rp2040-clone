// pio_top.sv — RP2040 PIO block top-level (one of two identical blocks)
//
// Contains:
//   - 32x16 shared instruction memory
//   - 4 state machines (pio_sm instances)
//   - 4 TX FIFOs + 4 RX FIFOs (pio_fifo instances)
//   - AHB-Lite slave register interface
//   - IRQ flag register (8-bit, shared across all SMs)
//   - GPIO output priority mux (SM3 highest)
//
// Register map (byte offsets from block base, e.g. 0x50200000 for PIO0):
//   0x000 CTRL
//   0x004 FSTAT
//   0x008 FDEBUG   (W1C)
//   0x00C FLEVEL
//   0x010 TXF0..TXF3  (WO)
//   0x020 RXF0..RXF3  (RO)
//   0x030 IRQ         (W1C)
//   0x034 IRQ_FORCE   (WO, force-set)
//   0x038 INPUT_SYNC_BYPASS (stub)
//   0x03C DBG_PADOUT  (RO)
//   0x040 DBG_PADOE   (RO)
//   0x044 DBG_CFGINFO (RO, constant)
//   0x048..0x0C4: INSTR_MEM[0..31]
//   Per SM (offset 0x0C8 + 0x18*sm):
//     +0x00 CLKDIV
//     +0x04 EXECCTRL
//     +0x08 SHIFTCTRL
//     +0x0C ADDR     (RO)
//     +0x10 INSTR    (RO current / WO force-exec)
//     +0x14 PINCTRL

`default_nettype none

module pio_top (
    input  wire        clk,
    input  wire        rst_n,

    // AHB-Lite slave
    input  wire [31:0] haddr,
    input  wire        hwrite,
    input  wire [1:0]  htrans,
    input  wire [2:0]  hsize,
    input  wire [31:0] hwdata,
    output wire [31:0] hrdata,
    output wire        hready,
    output wire        hresp,

    // GPIO pad connections
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_out,
    output wire [31:0] gpio_oe,

    // IRQ to CPU (flags 0-3)
    output wire [3:0]  irq_out
);

// ============================================================================
// AHB pipeline registers
// ============================================================================
wire        ahb_active = htrans[1];

reg [31:0]  haddr_r;
reg         hwrite_r;
reg         active_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        haddr_r  <= 32'd0;
        hwrite_r <= 1'b0;
        active_r <= 1'b0;
    end else begin
        haddr_r  <= haddr;
        hwrite_r <= hwrite;
        active_r <= ahb_active;
    end
end

wire        do_write = active_r && hwrite_r;
wire        do_read  = active_r && !hwrite_r;
wire [11:0] reg_addr = haddr_r[11:0]; // offset within 4KB block

// ============================================================================
// Instruction memory (32 x 16-bit, shared by all 4 SMs)
// ============================================================================
reg [15:0] instr_mem [0:31];

integer mi;
initial begin
    for (mi = 0; mi < 32; mi = mi + 1)
        instr_mem[mi] = 16'd0;
end

// ============================================================================
// Configuration registers (per SM)
// ============================================================================
reg [31:0] sm_clkdiv    [0:3];
reg [31:0] sm_execctrl  [0:3];
reg [31:0] sm_shiftctrl [0:3];
reg [31:0] sm_pinctrl   [0:3];

// Default reset values per RP2040 spec
integer si;
initial begin
    for (si = 0; si < 4; si = si + 1) begin
        sm_clkdiv[si]    = 32'h0001_0000; // INT=1, FRAC=0 → tick every cycle
        sm_execctrl[si]  = 32'h0001_f000; // WRAP_TOP=31 [16:12], WRAP_BOTTOM=0 [11:7]
        sm_shiftctrl[si] = 32'h0000_0000;
        sm_pinctrl[si]   = 32'h0000_0000;
    end
end

// ============================================================================
// CTRL register fields
// ============================================================================
reg [3:0]  sm_enable_r;       // CTRL[3:0]
// CLKDIV_RESTART and SM_RESTART are written as one-shot pulses; we generate
// single-cycle pulses from a write to CTRL.

reg [3:0]  sm_restart_pulse;
reg [3:0]  sm_clkdiv_restart_pulse;

// ============================================================================
// IRQ flags (8-bit register, shared across SMs)
// ============================================================================
reg [7:0]  irq_flags;

// Per-SM IRQ set/clr wires
wire [7:0] sm_irq_set [0:3];
wire [7:0] sm_irq_clr [0:3];

// ============================================================================
// FDEBUG sticky bits (W1C from CPU, set by SM combinational outputs)
// ============================================================================
reg [3:0]  fdebug_rxstall;
reg [3:0]  fdebug_rxunder;
reg [3:0]  fdebug_txover;
reg [3:0]  fdebug_txstall;

// SM debug outputs
wire [3:0] sm_txstall_out;
wire [3:0] sm_txover_out;
wire [3:0] sm_rxunder_out;
wire [3:0] sm_rxstall_out;

// ============================================================================
// Force-exec (SM_INSTR write)
// ============================================================================
reg [15:0] sm_exec_instr [0:3];
reg [3:0]  sm_exec_vld;   // one-cycle pulse

// ============================================================================
// FIFO signals
// ============================================================================
// TX FIFO (CPU→SM): push from CPU, pop from SM
wire        tx_push   [0:3];
wire [31:0] tx_wdata  [0:3];
wire        tx_full   [0:3];
wire        tx_pop    [0:3];
wire [31:0] tx_rdata  [0:3];
wire        tx_empty  [0:3];
wire [3:0]  tx_level  [0:3];

// RX FIFO (SM→CPU): push from SM, pop from CPU
wire        rx_push   [0:3];
wire [31:0] rx_wdata  [0:3];
wire        rx_full   [0:3];
wire        rx_pop    [0:3];
wire [31:0] rx_rdata  [0:3];
wire        rx_empty  [0:3];
wire [3:0]  rx_level  [0:3];

// FJOIN configuration
wire tx_fjoin [0:3];
wire rx_fjoin [0:3];

// FJOIN_TX: TX is 8-deep, RX is disabled (acts as always-full → push stalls, no rx_pop)
// FJOIN_RX: RX is 8-deep, TX is disabled (acts as always-empty → pull stalls)
assign tx_fjoin[0] = sm_shiftctrl[0][30];
assign tx_fjoin[1] = sm_shiftctrl[1][30];
assign tx_fjoin[2] = sm_shiftctrl[2][30];
assign tx_fjoin[3] = sm_shiftctrl[3][30];

assign rx_fjoin[0] = sm_shiftctrl[0][31];
assign rx_fjoin[1] = sm_shiftctrl[1][31];
assign rx_fjoin[2] = sm_shiftctrl[2][31];
assign rx_fjoin[3] = sm_shiftctrl[3][31];

// TX FIFO push from AHB (write to TXFn)
// Only push when not doing a FJOIN_RX (which disables TX FIFO)
reg tx_push_r [0:3];
reg [31:0] tx_wdata_r [0:3];

assign tx_push[0]  = tx_push_r[0]  && !rx_fjoin[0];
assign tx_push[1]  = tx_push_r[1]  && !rx_fjoin[1];
assign tx_push[2]  = tx_push_r[2]  && !rx_fjoin[2];
assign tx_push[3]  = tx_push_r[3]  && !rx_fjoin[3];
assign tx_wdata[0] = tx_wdata_r[0];
assign tx_wdata[1] = tx_wdata_r[1];
assign tx_wdata[2] = tx_wdata_r[2];
assign tx_wdata[3] = tx_wdata_r[3];

// RX FIFO pop from AHB (read from RXFn)
// Only pop when not doing a FJOIN_TX (which disables RX FIFO — acts as always-full)
reg rx_pop_r [0:3];

assign rx_pop[0] = rx_pop_r[0] && !tx_fjoin[0];
assign rx_pop[1] = rx_pop_r[1] && !tx_fjoin[1];
assign rx_pop[2] = rx_pop_r[2] && !tx_fjoin[2];
assign rx_pop[3] = rx_pop_r[3] && !tx_fjoin[3];

// SM→RX FIFO push: disabled when FJOIN_TX (SM can't push to RX in TX-join mode)
wire [3:0] sm_rx_push_w;
wire [3:0] sm_rx_full_w;
wire sm_rx_push_real [0:3];
wire sm_rx_full_real [0:3];

genvar gi;
generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : fifo_join_rx
        assign sm_rx_push_real[gi] = rx_push[gi] && !tx_fjoin[gi];
        // If FJOIN_TX, RX appears full to SM (so SM stalls on PUSH)
        assign sm_rx_full_real[gi] = tx_fjoin[gi] ? 1'b1 : rx_full[gi];
    end
endgenerate

// SM→TX FIFO pop: disabled when FJOIN_RX (TX appears empty to SM)
wire sm_tx_pop_real  [0:3];
wire sm_tx_empty_real[0:3];

generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : fifo_join_tx
        assign sm_tx_pop_real[gi]   = tx_pop[gi] && !rx_fjoin[gi];
        assign sm_tx_empty_real[gi] = rx_fjoin[gi] ? 1'b1 : tx_empty[gi];
    end
endgenerate

// ============================================================================
// FIFO instantiation (8 total: 4 TX + 4 RX)
// ============================================================================
generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : fifo_inst
        pio_fifo u_tx_fifo (
            .clk   (clk),
            .rst_n (rst_n),
            .fjoin (tx_fjoin[gi]),
            .push  (tx_push[gi]),
            .wdata (tx_wdata[gi]),
            .full  (tx_full[gi]),
            .pop   (sm_tx_pop_real[gi]),
            .rdata (tx_rdata[gi]),
            .empty (tx_empty[gi]),
            .level (tx_level[gi])
        );

        pio_fifo u_rx_fifo (
            .clk   (clk),
            .rst_n (rst_n),
            .fjoin (rx_fjoin[gi]),
            .push  (sm_rx_push_real[gi]),
            .wdata (rx_wdata[gi]),
            .full  (rx_full[gi]),
            .pop   (rx_pop[gi]),
            .rdata (rx_rdata[gi]),
            .empty (rx_empty[gi]),
            .level (rx_level[gi])
        );
    end
endgenerate

// ============================================================================
// SM GPIO outputs
// ============================================================================
wire [31:0] sm_gpio_out [0:3];
wire [31:0] sm_gpio_oe  [0:3];

// GPIO output priority mux: SM3 highest priority
// For each bit: highest-numbered SM with OE wins
assign gpio_out[31:0] =
    (sm_gpio_oe[3] & sm_gpio_out[3]) |
    (~sm_gpio_oe[3] & sm_gpio_oe[2] & sm_gpio_out[2]) |
    (~sm_gpio_oe[3] & ~sm_gpio_oe[2] & sm_gpio_oe[1] & sm_gpio_out[1]) |
    (~sm_gpio_oe[3] & ~sm_gpio_oe[2] & ~sm_gpio_oe[1] & sm_gpio_oe[0] & sm_gpio_out[0]);

assign gpio_oe = sm_gpio_oe[0] | sm_gpio_oe[1] | sm_gpio_oe[2] | sm_gpio_oe[3];

// ============================================================================
// SM status outputs
// ============================================================================
wire [4:0]  sm_pc_out     [0:3];
wire [15:0] sm_instr_out  [0:3];
wire        sm_exec_stalled[0:3];

// ============================================================================
// SM instantiation (4 state machines)
// ============================================================================
generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : sm_inst
        pio_sm #(.SM_IDX(gi)) u_sm (
            .clk             (clk),
            .rst_n           (rst_n),
            .enable          (sm_enable_r[gi]),
            .restart         (sm_restart_pulse[gi]),
            .clkdiv_restart  (sm_clkdiv_restart_pulse[gi]),
            .clkdiv          (sm_clkdiv[gi]),
            .execctrl        (sm_execctrl[gi]),
            .shiftctrl       (sm_shiftctrl[gi]),
            .pinctrl         (sm_pinctrl[gi]),
            .instr_mem       (instr_mem),
            .tx_pop          (tx_pop[gi]),
            .tx_rdata        (tx_rdata[gi]),
            .tx_empty        (sm_tx_empty_real[gi]),
            .rx_push         (rx_push[gi]),
            .rx_wdata        (rx_wdata[gi]),
            .rx_full         (sm_rx_full_real[gi]),
            .gpio_in         (gpio_in),
            .gpio_out        (sm_gpio_out[gi]),
            .gpio_oe         (sm_gpio_oe[gi]),
            .irq_flags       (irq_flags),
            .irq_set         (sm_irq_set[gi]),
            .irq_clr         (sm_irq_clr[gi]),
            .exec_instr      (sm_exec_instr[gi]),
            .exec_vld        (sm_exec_vld[gi]),
            .exec_stalled    (sm_exec_stalled[gi]),
            .pc_out          (sm_pc_out[gi]),
            .instr_out       (sm_instr_out[gi]),
            .txstall         (sm_txstall_out[gi]),
            .txover          (sm_txover_out[gi]),
            .rxunder         (sm_rxunder_out[gi]),
            .rxstall         (sm_rxstall_out[gi])
        );
    end
endgenerate

// ============================================================================
// IRQ flags register
// ============================================================================
// Updated each clock:
//   - SM set/clr requests
//   - CPU W1C (0x030)
//   - CPU IRQ_FORCE (0x034)

assign irq_out = irq_flags[3:0];

// We combine SM irq_set/clr; handle below in sequential block

// ============================================================================
// Read data mux (combinational)
// ============================================================================
reg [31:0] hrdata_r;

// FSTAT, FLEVEL, FDEBUG fields
wire [31:0] fstat_val  = {4'd0, rx_empty[3], rx_empty[2], rx_empty[1], rx_empty[0],
                          4'd0, rx_full[3],  rx_full[2],  rx_full[1],  rx_full[0],
                          4'd0, tx_empty[3], tx_empty[2], tx_empty[1], tx_empty[0],
                          4'd0, tx_full[3],  tx_full[2],  tx_full[1],  tx_full[0]};

wire [31:0] fdebug_val = {4'd0, fdebug_rxstall, 4'd0, fdebug_rxunder,
                          4'd0, fdebug_txover,   4'd0, fdebug_txstall};

wire [31:0] flevel_val = {rx_level[3], tx_level[3],
                          rx_level[2], tx_level[2],
                          rx_level[1], tx_level[1],
                          rx_level[0], tx_level[0]};

wire [31:0] dbg_cfginfo = 32'h0020_0404; // IMEM_SIZE=32[23:16], SM_COUNT=4[11:8], FIFO_DEPTH=4[3:0]

always @(*) begin
    hrdata_r = 32'd0;
    case (reg_addr)
        // CTRL read: [11:8]=CLKDIV_RESTART(always 0 on read), [7:4]=SM_RESTART(0), [3:0]=SM_ENABLE
        12'h000: hrdata_r = {20'd0, 4'd0, 4'd0, sm_enable_r};
        12'h004: hrdata_r = fstat_val;
        12'h008: hrdata_r = fdebug_val;
        12'h00C: hrdata_r = flevel_val;
        // TXF0-3: WO, read as 0
        12'h010: hrdata_r = 32'd0;
        12'h014: hrdata_r = 32'd0;
        12'h018: hrdata_r = 32'd0;
        12'h01C: hrdata_r = 32'd0;
        // RXF0-3: pop on read
        12'h020: hrdata_r = rx_rdata[0];
        12'h024: hrdata_r = rx_rdata[1];
        12'h028: hrdata_r = rx_rdata[2];
        12'h02C: hrdata_r = rx_rdata[3];
        12'h030: hrdata_r = {24'd0, irq_flags};
        12'h034: hrdata_r = 32'd0; // IRQ_FORCE WO
        12'h038: hrdata_r = 32'd0; // INPUT_SYNC_BYPASS stub
        12'h03C: hrdata_r = gpio_out;
        12'h040: hrdata_r = gpio_oe;
        12'h044: hrdata_r = dbg_cfginfo;
        // INSTR_MEM[0..31] at 0x048..0x0C4
        default: begin
            if (reg_addr >= 12'h048 && reg_addr <= 12'h0C4) begin
                hrdata_r = {16'd0, instr_mem[5'((reg_addr - 12'h048) >> 2)]};
            end else begin
                // Per-SM registers
                // SM0: 0x0C8, SM1: 0x0E0, SM2: 0x0F8, SM3: 0x110
                if      (reg_addr >= 12'h0C8 && reg_addr <= 12'h0DC) hrdata_r = sm_reg_read(0, reg_addr - 12'h0C8);
                else if (reg_addr >= 12'h0E0 && reg_addr <= 12'h0F4) hrdata_r = sm_reg_read(1, reg_addr - 12'h0E0);
                else if (reg_addr >= 12'h0F8 && reg_addr <= 12'h10C) hrdata_r = sm_reg_read(2, reg_addr - 12'h0F8);
                else if (reg_addr >= 12'h110 && reg_addr <= 12'h124) hrdata_r = sm_reg_read(3, reg_addr - 12'h110);
                else hrdata_r = 32'd0;
            end
        end
    endcase
end

// SM register read helper function
function automatic [31:0] sm_reg_read;
    input integer sm;
    input [11:0]  offset;
    case (offset)
        12'h00: sm_reg_read = sm_clkdiv[sm];
        12'h04: sm_reg_read = sm_execctrl[sm];
        12'h08: sm_reg_read = sm_shiftctrl[sm];
        12'h0C: sm_reg_read = {27'd0, sm_pc_out[sm]};
        12'h10: sm_reg_read = {16'd0, sm_instr_out[sm]};
        12'h14: sm_reg_read = sm_pinctrl[sm];
        default: sm_reg_read = 32'd0;
    endcase
endfunction

assign hrdata = hrdata_r;
assign hready = 1'b1;
assign hresp  = 1'b0;

// ============================================================================
// RX FIFO pop on read (combinational)
// ============================================================================
always @(*) begin
    rx_pop_r[0] = 1'b0;
    rx_pop_r[1] = 1'b0;
    rx_pop_r[2] = 1'b0;
    rx_pop_r[3] = 1'b0;
    if (do_read) begin
        case (reg_addr)
            12'h020: rx_pop_r[0] = 1'b1;
            12'h024: rx_pop_r[1] = 1'b1;
            12'h028: rx_pop_r[2] = 1'b1;
            12'h02C: rx_pop_r[3] = 1'b1;
            default: ;
        endcase
    end
end

// ============================================================================
// Write logic (sequential, registered)
// ============================================================================
always @(posedge clk or negedge rst_n) begin
    integer i;
    if (!rst_n) begin
        sm_enable_r          <= 4'd0;
        sm_restart_pulse     <= 4'd0;
        sm_clkdiv_restart_pulse <= 4'd0;
        irq_flags            <= 8'd0;
        fdebug_rxstall       <= 4'd0;
        fdebug_rxunder       <= 4'd0;
        fdebug_txover        <= 4'd0;
        fdebug_txstall       <= 4'd0;
        sm_exec_vld          <= 4'd0;

        for (i = 0; i < 4; i = i + 1) begin
            sm_clkdiv[i]    <= 32'h0001_0000;
            sm_execctrl[i]  <= 32'h0001_f000;
            sm_shiftctrl[i] <= 32'h0000_0000;
            sm_pinctrl[i]   <= 32'h0000_0000;
            sm_exec_instr[i]<= 16'd0;
            tx_push_r[i]    <= 1'b0;
            tx_wdata_r[i]   <= 32'd0;
        end

        for (i = 0; i < 32; i = i + 1)
            instr_mem[i] <= 16'd0;

    end else begin
        // Clear one-shot pulses each cycle
        sm_restart_pulse        <= 4'd0;
        sm_clkdiv_restart_pulse <= 4'd0;
        sm_exec_vld             <= 4'd0;
        tx_push_r[0]            <= 1'b0;
        tx_push_r[1]            <= 1'b0;
        tx_push_r[2]            <= 1'b0;
        tx_push_r[3]            <= 1'b0;

        // Update IRQ flags from SM set/clr
        for (i = 0; i < 4; i = i + 1) begin
            irq_flags <= (irq_flags | sm_irq_set[i]) & ~sm_irq_clr[i];
        end

        // Latch FDEBUG sticky bits from SM outputs
        fdebug_txstall <= fdebug_txstall | sm_txstall_out;
        fdebug_txover  <= fdebug_txover  | sm_txover_out;
        fdebug_rxunder <= fdebug_rxunder | sm_rxunder_out;
        fdebug_rxstall <= fdebug_rxstall | sm_rxstall_out;

        // AHB write decoding
        if (do_write) begin
            case (reg_addr)
                // -------------------------------------------------------
                // CTRL
                // -------------------------------------------------------
                12'h000: begin
                    sm_enable_r             <= hwdata[3:0];
                    sm_restart_pulse        <= hwdata[7:4];
                    sm_clkdiv_restart_pulse <= hwdata[11:8];
                end

                // -------------------------------------------------------
                // FDEBUG (W1C)
                // -------------------------------------------------------
                12'h008: begin
                    fdebug_txstall <= fdebug_txstall & ~hwdata[3:0];
                    fdebug_txover  <= fdebug_txover  & ~hwdata[11:8];
                    fdebug_rxunder <= fdebug_rxunder & ~hwdata[19:16];
                    fdebug_rxstall <= fdebug_rxstall & ~hwdata[27:24];
                end

                // -------------------------------------------------------
                // TXF0..TXF3 (WO: push to TX FIFO)
                // -------------------------------------------------------
                12'h010: begin tx_push_r[0] <= 1'b1; tx_wdata_r[0] <= hwdata; end
                12'h014: begin tx_push_r[1] <= 1'b1; tx_wdata_r[1] <= hwdata; end
                12'h018: begin tx_push_r[2] <= 1'b1; tx_wdata_r[2] <= hwdata; end
                12'h01C: begin tx_push_r[3] <= 1'b1; tx_wdata_r[3] <= hwdata; end

                // -------------------------------------------------------
                // IRQ (W1C)
                // -------------------------------------------------------
                12'h030: begin
                    irq_flags <= irq_flags & ~hwdata[7:0];
                end

                // -------------------------------------------------------
                // IRQ_FORCE (WO, force-set)
                // -------------------------------------------------------
                12'h034: begin
                    irq_flags <= irq_flags | hwdata[7:0];
                end

                // -------------------------------------------------------
                // INPUT_SYNC_BYPASS (stub: ignore writes)
                // -------------------------------------------------------
                12'h038: ; // no effect

                // -------------------------------------------------------
                // INSTR_MEM[0..31]
                // -------------------------------------------------------
                default: begin
                    if (reg_addr >= 12'h048 && reg_addr <= 12'h0C4) begin
                        instr_mem[5'((reg_addr - 12'h048) >> 2)] <= hwdata[15:0];
                    end else begin
                        // Per-SM registers
                        // SM0
                        if (reg_addr >= 12'h0C8 && reg_addr <= 12'h0DC) begin
                            case (reg_addr - 12'h0C8)
                                12'h00: sm_clkdiv[0]    <= hwdata;
                                12'h04: sm_execctrl[0]  <= hwdata;
                                12'h08: sm_shiftctrl[0] <= hwdata;
                                12'h0C: ; // ADDR RO
                                12'h10: begin // INSTR write = force exec
                                    sm_exec_instr[0] <= hwdata[15:0];
                                    sm_exec_vld[0]   <= 1'b1;
                                end
                                12'h14: sm_pinctrl[0] <= hwdata;
                                default: ;
                            endcase
                        end
                        // SM1
                        else if (reg_addr >= 12'h0E0 && reg_addr <= 12'h0F4) begin
                            case (reg_addr - 12'h0E0)
                                12'h00: sm_clkdiv[1]    <= hwdata;
                                12'h04: sm_execctrl[1]  <= hwdata;
                                12'h08: sm_shiftctrl[1] <= hwdata;
                                12'h0C: ; // ADDR RO
                                12'h10: begin
                                    sm_exec_instr[1] <= hwdata[15:0];
                                    sm_exec_vld[1]   <= 1'b1;
                                end
                                12'h14: sm_pinctrl[1] <= hwdata;
                                default: ;
                            endcase
                        end
                        // SM2
                        else if (reg_addr >= 12'h0F8 && reg_addr <= 12'h10C) begin
                            case (reg_addr - 12'h0F8)
                                12'h00: sm_clkdiv[2]    <= hwdata;
                                12'h04: sm_execctrl[2]  <= hwdata;
                                12'h08: sm_shiftctrl[2] <= hwdata;
                                12'h0C: ; // ADDR RO
                                12'h10: begin
                                    sm_exec_instr[2] <= hwdata[15:0];
                                    sm_exec_vld[2]   <= 1'b1;
                                end
                                12'h14: sm_pinctrl[2] <= hwdata;
                                default: ;
                            endcase
                        end
                        // SM3
                        else if (reg_addr >= 12'h110 && reg_addr <= 12'h124) begin
                            case (reg_addr - 12'h110)
                                12'h00: sm_clkdiv[3]    <= hwdata;
                                12'h04: sm_execctrl[3]  <= hwdata;
                                12'h08: sm_shiftctrl[3] <= hwdata;
                                12'h0C: ; // ADDR RO
                                12'h10: begin
                                    sm_exec_instr[3] <= hwdata[15:0];
                                    sm_exec_vld[3]   <= 1'b1;
                                end
                                12'h14: sm_pinctrl[3] <= hwdata;
                                default: ;
                            endcase
                        end
                    end
                end
            endcase
        end // do_write
    end // not reset
end

endmodule
