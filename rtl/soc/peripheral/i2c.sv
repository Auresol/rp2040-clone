// i2c.sv — AHB-Lite I2C master peripheral.
//
// Register map (byte offset from base):
//   0x00  CON       [0]     enable
//   0x04  TAR       [6:0]   7-bit target address
//   0x08  DATA_CMD  write:  [7:0]=data, [8]=CMD(0=wr,1=rd), [9]=STOP, [10]=RESTART
//                   read:   [7:0]=received data (RX FIFO pop)
//   0x0C  SCL_HCNT  [15:0]  SCL high-period clock count
//   0x10  SCL_LCNT  [15:0]  SCL low-period clock count
//   0x14  STATUS    [5:0]   flags (read-only)
//   0x18  IMSC      [2:0]   interrupt mask
//   0x1C  RIS       [2:0]   raw interrupt status
//   0x20  MIS       [2:0]   masked interrupt status
//
// Open-drain interface: scl_oe/sda_oe = 1 pulls line low, 0 releases.
// Clock stretching: waits for scl_i to go high before counting SCL high period.
// Auto-STOP on FIFO underrun.

`default_nettype none

module i2c (
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

    // I2C open-drain interface
    output wire        scl_oe,    // 1 = pull SCL low
    input  wire        scl_i,     // SCL pin state
    output wire        sda_oe,    // 1 = pull SDA low
    input  wire        sda_i,     // SDA pin state

    // Interrupt
    output wire        i2c_irq
);

// ---------------------------------------------------------------------------
// Input synchronizers (2-stage metastability guard)

reg [1:0] scl_sync, sda_sync;
wire scl_in = scl_sync[1];
wire sda_in = sda_sync[1];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scl_sync <= 2'b11;
        sda_sync <= 2'b11;
    end else begin
        scl_sync <= {scl_sync[0], scl_i};
        sda_sync <= {sda_sync[0], sda_i};
    end
end

// ---------------------------------------------------------------------------
// AHB pipeline registers

wire active = htrans[1];
reg  active_r, hwrite_r;
reg  [5:2] reg_addr_r;

always @(posedge clk) begin
    active_r   <= active;
    hwrite_r   <= hwrite;
    reg_addr_r <= haddr[5:2];
end

// ---------------------------------------------------------------------------
// Register word-address constants (byte_offset >> 2)

localparam [3:0] ADDR_CON      = 4'h0; // 0x00
localparam [3:0] ADDR_TAR      = 4'h1; // 0x04
localparam [3:0] ADDR_DATA_CMD = 4'h2; // 0x08
localparam [3:0] ADDR_SCL_HCNT = 4'h3; // 0x0C
localparam [3:0] ADDR_SCL_LCNT = 4'h4; // 0x10
localparam [3:0] ADDR_STATUS   = 4'h5; // 0x14
localparam [3:0] ADDR_IMSC     = 4'h6; // 0x18
localparam [3:0] ADDR_RIS      = 4'h7; // 0x1C
localparam [3:0] ADDR_MIS      = 4'h8; // 0x20

// ---------------------------------------------------------------------------
// Configuration registers

reg        con_en;
reg [6:0]  tar;
reg [15:0] scl_hcnt;
reg [15:0] scl_lcnt;
reg [2:0]  imsc;

// ---------------------------------------------------------------------------
// TX Command FIFO — 8 entries, 11-bit {restart, stop, cmd, data[7:0]}

localparam FIFO_DEPTH = 8;
localparam FIFO_AW    = 3;

reg [10:0]      cmd_mem [0:FIFO_DEPTH-1];
reg [FIFO_AW:0] cmd_wptr;
reg [FIFO_AW:0] cmd_rptr;

wire cmd_full  = (cmd_wptr[FIFO_AW] != cmd_rptr[FIFO_AW]) &&
                 (cmd_wptr[FIFO_AW-1:0] == cmd_rptr[FIFO_AW-1:0]);
wire cmd_empty = (cmd_wptr == cmd_rptr);
wire [FIFO_AW-1:0] cmd_widx = cmd_wptr[FIFO_AW-1:0];
wire [FIFO_AW-1:0] cmd_ridx = cmd_rptr[FIFO_AW-1:0];

// Combinational read of FIFO front (for dispatch decisions)
wire [10:0] cmd_front = cmd_mem[cmd_ridx];

// ---------------------------------------------------------------------------
// RX Data FIFO — 8 entries, 8-bit

reg [7:0]       rx_mem [0:FIFO_DEPTH-1];
reg [FIFO_AW:0] rx_wptr;
reg [FIFO_AW:0] rx_rptr;

wire rx_full  = (rx_wptr[FIFO_AW] != rx_rptr[FIFO_AW]) &&
                (rx_wptr[FIFO_AW-1:0] == rx_rptr[FIFO_AW-1:0]);
wire rx_empty = (rx_wptr == rx_rptr);
wire [FIFO_AW-1:0] rx_widx = rx_wptr[FIFO_AW-1:0];
wire [FIFO_AW-1:0] rx_ridx = rx_rptr[FIFO_AW-1:0];

// ---------------------------------------------------------------------------
// I2C engine

localparam [3:0] ST_IDLE         = 4'd0;
localparam [3:0] ST_START_HOLD   = 4'd1;  // SDA low, SCL high — hold time
localparam [3:0] ST_START_SCL    = 4'd2;  // SCL goes low after START
localparam [3:0] ST_BIT_LOW      = 4'd3;  // SCL low — drive/release SDA
localparam [3:0] ST_BIT_HIGH     = 4'd4;  // SCL high — sample SDA (RX)
localparam [3:0] ST_ACK_LOW      = 4'd5;  // SCL low — ACK setup
localparam [3:0] ST_ACK_HIGH     = 4'd6;  // SCL high — ACK sample/hold
localparam [3:0] ST_NEXT_CMD     = 4'd7;  // dispatch next FIFO command
localparam [3:0] ST_STOP_SETUP   = 4'd8;  // SDA low, SCL low — prepare
localparam [3:0] ST_STOP_SCL     = 4'd9;  // SCL released, SDA still low
localparam [3:0] ST_STOP_SDA     = 4'd10; // SDA released — STOP complete
localparam [3:0] ST_RESTART_SDA  = 4'd11; // release SDA while SCL low
localparam [3:0] ST_RESTART_SCL  = 4'd12; // release SCL while SDA high
localparam [3:0] ST_RESTART_HOLD = 4'd13; // SDA low while SCL high — restart
localparam [3:0] ST_RESTART_SCL2 = 4'd14; // SCL low after restart

localparam [1:0] BTYPE_ADDR  = 2'd0;
localparam [1:0] BTYPE_WRITE = 2'd1;
localparam [1:0] BTYPE_READ  = 2'd2;

reg [3:0]  state;
reg [15:0] scl_cnt;
reg [3:0]  bit_cnt;
reg [7:0]  shift_reg;
reg        scl_r;        // 1 = pull SCL low
reg        sda_r;        // 1 = pull SDA low
reg        ack_err;      // NACK received (sticky until new transaction)
reg [1:0]  byte_type;

// Current command being processed
reg        cur_cmd;      // 0=write, 1=read
reg        cur_stop;

wire busy = (state != ST_IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state     <= ST_IDLE;
        scl_cnt   <= 16'h0;
        bit_cnt   <= 4'h0;
        shift_reg <= 8'h0;
        scl_r     <= 1'b0;
        sda_r     <= 1'b0;
        ack_err   <= 1'b0;
        byte_type <= BTYPE_ADDR;
        cur_cmd   <= 1'b0;
        cur_stop  <= 1'b0;
        cmd_rptr  <= '0;
        rx_wptr   <= '0;
    end else begin
        case (state)

        // ── Idle ─────────────────────────────────────────────────
        ST_IDLE: begin
            scl_r <= 1'b0;  // release SCL
            sda_r <= 1'b0;  // release SDA
            if (con_en && !cmd_empty) begin
                // Pop first command, start transaction
                cmd_rptr <= cmd_rptr + 1;
                cur_cmd  <= cmd_front[8];
                cur_stop <= cmd_front[9];
                ack_err  <= 1'b0;
                sda_r    <= 1'b1;        // SDA low = START condition
                scl_cnt  <= scl_hcnt;
                state    <= ST_START_HOLD;
            end
        end

        // ── START condition ──────────────────────────────────────
        // SDA is low, SCL is still high — hold for scl_hcnt
        ST_START_HOLD: begin
            sda_r <= 1'b1;  // keep SDA low
            scl_r <= 1'b0;  // SCL still high
            if (scl_cnt == 16'h0) begin
                scl_r   <= 1'b1;             // pull SCL low
                scl_cnt <= scl_lcnt;
                state   <= ST_START_SCL;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // SCL is now low — load address byte and begin sending
        ST_START_SCL: begin
            scl_r <= 1'b1;  // keep SCL low
            sda_r <= 1'b1;  // keep SDA low (will change in BIT_LOW)
            if (scl_cnt == 16'h0) begin
                shift_reg <= {tar, cur_cmd};  // address + R/W
                bit_cnt   <= 4'd7;
                byte_type <= BTYPE_ADDR;
                scl_cnt   <= scl_lcnt;
                state     <= ST_BIT_LOW;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // ── Bit transfer (shared by ADDR, WRITE, READ) ──────────
        // SCL low phase: set SDA for current bit
        ST_BIT_LOW: begin
            scl_r <= 1'b1;  // SCL low
            if (byte_type == BTYPE_READ)
                sda_r <= 1'b0;           // release SDA for slave to drive
            else
                sda_r <= ~shift_reg[7];  // drive bit (inverted: oe=1 pulls low)
            if (scl_cnt == 16'h0) begin
                scl_cnt <= scl_hcnt;
                state   <= ST_BIT_HIGH;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // SCL high phase: sample SDA, advance bit counter
        ST_BIT_HIGH: begin
            scl_r <= 1'b0;  // release SCL (high)
            if (!scl_in) begin
                // Clock stretching — slave holding SCL low, wait
            end else if (scl_cnt == 16'h0) begin
                // Shift register: TX shifts out, RX shifts in
                if (byte_type == BTYPE_READ)
                    shift_reg <= {shift_reg[6:0], sda_in};
                else
                    shift_reg <= {shift_reg[6:0], 1'b0};
                if (bit_cnt == 4'h0) begin
                    // All 8 bits done → ACK phase
                    scl_cnt <= scl_lcnt;
                    state   <= ST_ACK_LOW;
                end else begin
                    bit_cnt <= bit_cnt - 4'd1;
                    scl_cnt <= scl_lcnt;
                    state   <= ST_BIT_LOW;
                end
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // ── ACK/NACK ─────────────────────────────────────────────
        // SCL low: set up SDA for ACK
        ST_ACK_LOW: begin
            scl_r <= 1'b1;  // SCL low
            if (byte_type == BTYPE_READ)
                // We're the receiver — drive ACK (low) or NACK (release)
                sda_r <= cur_stop ? 1'b0 : 1'b1; // NACK if last, ACK otherwise
            else
                // We sent data — release SDA for slave's ACK
                sda_r <= 1'b0;
            if (scl_cnt == 16'h0) begin
                scl_cnt <= scl_hcnt;
                state   <= ST_ACK_HIGH;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // SCL high: sample or hold ACK
        ST_ACK_HIGH: begin
            scl_r <= 1'b0;  // release SCL
            if (!scl_in) begin
                // Clock stretching
            end else if (scl_cnt == 16'h0) begin
                case (byte_type)
                    BTYPE_ADDR: begin
                        if (sda_in) begin
                            // NACK — slave not responding
                            ack_err <= 1'b1;
                            sda_r   <= 1'b1;    // pull SDA low for STOP
                            scl_cnt <= scl_lcnt;
                            state   <= ST_STOP_SETUP;
                        end else if (!cur_cmd) begin
                            // ACK, write mode — send data byte
                            // cur_data was stored in cmd_front[7:0] at pop time
                            // but we used shift_reg for address. We need the data.
                            // Re-read from the stored command... actually we need
                            // to have saved cur_data. Let me use a register.
                            shift_reg <= cur_data;
                            bit_cnt   <= 4'd7;
                            byte_type <= BTYPE_WRITE;
                            scl_cnt   <= scl_lcnt;
                            state     <= ST_BIT_LOW;
                        end else begin
                            // ACK, read mode — receive data byte
                            bit_cnt   <= 4'd7;
                            byte_type <= BTYPE_READ;
                            scl_cnt   <= scl_lcnt;
                            state     <= ST_BIT_LOW;
                        end
                    end
                    BTYPE_WRITE: begin
                        if (sda_in) begin
                            // NACK from slave
                            ack_err <= 1'b1;
                            sda_r   <= 1'b1;
                            scl_cnt <= scl_lcnt;
                            state   <= ST_STOP_SETUP;
                        end else if (cur_stop) begin
                            sda_r   <= 1'b1;    // SDA low for STOP
                            scl_cnt <= scl_lcnt;
                            state   <= ST_STOP_SETUP;
                        end else begin
                            scl_cnt <= scl_lcnt;
                            state   <= ST_NEXT_CMD;
                        end
                    end
                    BTYPE_READ: begin
                        // Push received byte to RX FIFO
                        if (!rx_full) begin
                            rx_mem[rx_widx] <= shift_reg;
                            rx_wptr         <= rx_wptr + 1;
                        end
                        if (cur_stop) begin
                            sda_r   <= 1'b1;
                            scl_cnt <= scl_lcnt;
                            state   <= ST_STOP_SETUP;
                        end else begin
                            scl_cnt <= scl_lcnt;
                            state   <= ST_NEXT_CMD;
                        end
                    end
                    default: begin
                        scl_cnt <= scl_lcnt;
                        state   <= ST_STOP_SETUP;
                    end
                endcase
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // ── Next command dispatch ────────────────────────────────
        ST_NEXT_CMD: begin
            scl_r <= 1'b1;  // keep SCL low
            if (!cmd_empty) begin
                cmd_rptr <= cmd_rptr + 1;
                cur_cmd  <= cmd_front[8];
                cur_stop <= cmd_front[9];
                if (cmd_front[10]) begin
                    // RESTART — release SDA first
                    sda_r   <= 1'b0;
                    scl_cnt <= scl_lcnt;
                    state   <= ST_RESTART_SDA;
                end else if (!cmd_front[8]) begin
                    // Write
                    shift_reg <= cmd_front[7:0];
                    bit_cnt   <= 4'd7;
                    byte_type <= BTYPE_WRITE;
                    scl_cnt   <= scl_lcnt;
                    state     <= ST_BIT_LOW;
                end else begin
                    // Read
                    bit_cnt   <= 4'd7;
                    byte_type <= BTYPE_READ;
                    scl_cnt   <= scl_lcnt;
                    state     <= ST_BIT_LOW;
                end
            end else begin
                // FIFO empty — auto-STOP
                sda_r   <= 1'b1;
                scl_cnt <= scl_lcnt;
                state   <= ST_STOP_SETUP;
            end
        end

        // ── STOP condition ───────────────────────────────────────
        // SDA low, SCL low — prepare
        ST_STOP_SETUP: begin
            scl_r <= 1'b1;  // SCL low
            sda_r <= 1'b1;  // SDA low
            if (scl_cnt == 16'h0) begin
                scl_cnt <= scl_hcnt;
                state   <= ST_STOP_SCL;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // Release SCL, SDA stays low
        ST_STOP_SCL: begin
            scl_r <= 1'b0;  // release SCL (high)
            sda_r <= 1'b1;  // keep SDA low
            if (!scl_in) begin
                // Clock stretching
            end else if (scl_cnt == 16'h0) begin
                scl_cnt <= scl_hcnt;
                state   <= ST_STOP_SDA;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // Release SDA — STOP complete
        ST_STOP_SDA: begin
            scl_r <= 1'b0;  // SCL high
            sda_r <= 1'b0;  // release SDA (high) = STOP
            if (scl_cnt == 16'h0) begin
                state <= ST_IDLE;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // ── RESTART (repeated START) ─────────────────────────────
        // Release SDA while SCL still low
        ST_RESTART_SDA: begin
            scl_r <= 1'b1;  // SCL low
            sda_r <= 1'b0;  // release SDA (high)
            if (scl_cnt == 16'h0) begin
                scl_cnt <= scl_hcnt;
                state   <= ST_RESTART_SCL;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // Release SCL while SDA high
        ST_RESTART_SCL: begin
            scl_r <= 1'b0;  // release SCL (high)
            sda_r <= 1'b0;  // SDA high
            if (!scl_in) begin
                // Clock stretching
            end else if (scl_cnt == 16'h0) begin
                scl_cnt <= scl_hcnt;
                state   <= ST_RESTART_HOLD;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // Pull SDA low while SCL high — repeated START
        ST_RESTART_HOLD: begin
            scl_r <= 1'b0;  // SCL high
            sda_r <= 1'b1;  // SDA low = START
            if (scl_cnt == 16'h0) begin
                scl_r   <= 1'b1;  // SCL low
                scl_cnt <= scl_lcnt;
                state   <= ST_RESTART_SCL2;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        // SCL low after restart — load new address byte
        ST_RESTART_SCL2: begin
            scl_r <= 1'b1;  // SCL low
            sda_r <= 1'b1;  // SDA low (will change in BIT_LOW)
            if (scl_cnt == 16'h0) begin
                shift_reg <= {tar, cur_cmd};
                bit_cnt   <= 4'd7;
                byte_type <= BTYPE_ADDR;
                scl_cnt   <= scl_lcnt;
                state     <= ST_BIT_LOW;
            end else
                scl_cnt <= scl_cnt - 16'd1;
        end

        default: state <= ST_IDLE;

        endcase
    end
end

// ---------------------------------------------------------------------------
// cur_data register — holds write data from the current command
// Saved at pop time (IDLE or NEXT_CMD), used after address ACK

reg [7:0] cur_data;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cur_data <= 8'h0;
    else if (state == ST_IDLE && con_en && !cmd_empty)
        cur_data <= cmd_front[7:0];
    else if (state == ST_NEXT_CMD && !cmd_empty)
        cur_data <= cmd_front[7:0];
end

// ---------------------------------------------------------------------------
// AHB write handler

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        con_en   <= 1'b0;
        tar      <= 7'h0;
        scl_hcnt <= 16'h0;
        scl_lcnt <= 16'h0;
        imsc     <= 3'h0;
        cmd_wptr <= '0;
    end else if (active_r && hwrite_r) begin
        case (reg_addr_r)
            ADDR_CON:      con_en   <= hwdata[0];
            ADDR_TAR:      tar      <= hwdata[6:0];
            ADDR_DATA_CMD: begin
                if (!cmd_full) begin
                    cmd_mem[cmd_widx] <= hwdata[10:0];
                    cmd_wptr          <= cmd_wptr + 1;
                end
            end
            ADDR_SCL_HCNT: scl_hcnt <= hwdata[15:0];
            ADDR_SCL_LCNT: scl_lcnt <= hwdata[15:0];
            ADDR_IMSC:     imsc     <= hwdata[2:0];
            default: ;
        endcase
    end
end

// ---------------------------------------------------------------------------
// AHB read — RX FIFO dequeue on DATA_CMD read

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rx_rptr <= '0;
    else if (active_r && !hwrite_r && reg_addr_r == ADDR_DATA_CMD && !rx_empty)
        rx_rptr <= rx_rptr + 1;
end

// ---------------------------------------------------------------------------
// Status and interrupt

wire [31:0] status = {26'h0,
                      busy,       // [5] MST_ACTIVE
                      rx_full,    // [4] RFF
                      !rx_empty,  // [3] RFNE — RX FIFO not empty
                      cmd_empty,  // [2] TFE — TX cmd FIFO empty
                      !cmd_full,  // [1] TFNF — TX cmd FIFO not full
                      ack_err};   // [0] NACK_ERR

wire [2:0] ris = {ack_err,     // [2] NACK error
                  !rx_empty,   // [1] RX has data
                  cmd_empty};  // [0] TX empty
wire [2:0] mis = ris & imsc;

// ---------------------------------------------------------------------------
// AHB read data (combinational)

assign hrdata = (reg_addr_r == ADDR_CON)      ? {31'h0, con_en}            :
                (reg_addr_r == ADDR_TAR)      ? {25'h0, tar}               :
                (reg_addr_r == ADDR_DATA_CMD) ? {24'h0, rx_mem[rx_ridx]}   :
                (reg_addr_r == ADDR_SCL_HCNT) ? {16'h0, scl_hcnt}          :
                (reg_addr_r == ADDR_SCL_LCNT) ? {16'h0, scl_lcnt}          :
                (reg_addr_r == ADDR_STATUS)   ? status                      :
                (reg_addr_r == ADDR_IMSC)     ? {29'h0, imsc}              :
                (reg_addr_r == ADDR_RIS)      ? {29'h0, ris}               :
                (reg_addr_r == ADDR_MIS)      ? {29'h0, mis}               :
                                                32'h0;

assign hready = 1'b1;
assign hresp  = 1'b0;

// ---------------------------------------------------------------------------
// Output assignments

assign scl_oe  = scl_r;
assign sda_oe  = sda_r;
assign i2c_irq = |mis;

endmodule
