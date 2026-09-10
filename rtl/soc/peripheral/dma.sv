// dma.sv — 4-channel DMA controller with AHB-Lite slave + master ports.
//
// Each channel: READ_ADDR, WRITE_ADDR, TRANS_COUNT, CTRL.
// Channels are DREQ-paced (or free-running if dreq_sel=none).
// Round-robin scheduling among active channels.
//
// Register map (byte offset from base):
//   Channel N (stride = 0x10):
//     0x00 + N*0x10  READ_ADDR    [31:0]  source address
//     0x04 + N*0x10  WRITE_ADDR   [31:0]  destination address
//     0x08 + N*0x10  TRANS_COUNT  [31:0]  transfers remaining
//     0x0C + N*0x10  CTRL         [31:0]  channel control
//
//   CTRL fields:
//     [0]      EN          channel enable
//     [1]      INCR_READ   increment read address after each transfer
//     [2]      INCR_WRITE  increment write address after each transfer
//     [4:3]    DATA_SIZE   transfer width: 00=byte, 01=half, 10=word
//     [7:5]    DREQ_SEL    DREQ source (0=none/free-run, 1-7=dreq[0]-dreq[6])
//     [8]      IRQ_EN      fire IRQ when count reaches zero
//
//   Global registers:
//     0x40  IRQ_STATUS  [3:0]  per-channel done flag (write-1-to-clear)
//
// Master port issues single AHB-Lite reads/writes (no burst).
// dma_irq = OR of all (IRQ_STATUS & IRQ_EN) bits.

`default_nettype none

module dma (
    input  wire        clk,
    input  wire        rst_n,

    // AHB-Lite slave port (CPU configures channels)
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] s_haddr,
    input  wire        s_hwrite,
    input  wire [1:0]  s_htrans,
    input  wire [2:0]  s_hsize,
    input  wire [31:0] s_hwdata,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [31:0] s_hrdata,
    output wire        s_hready,
    output wire        s_hresp,

    // AHB-Lite master port (DMA issues reads/writes)
    output reg  [31:0] m_haddr,
    output reg         m_hwrite,
    output reg  [1:0]  m_htrans,
    output reg  [2:0]  m_hsize,
    output wire [31:0] m_hwdata,
    input  wire [31:0] m_hrdata,
    input  wire        m_hready,
    input  wire        m_hresp,

    // DREQ inputs from peripherals
    input  wire [3:0]  dreq,

    // Interrupt output
    output wire        dma_irq
);

// ---------------------------------------------------------------------------
// Parameters

localparam NUM_CH = 4;

// Channel FSM states
localparam [2:0] ST_IDLE       = 3'd0,
                 ST_READ_ADDR  = 3'd1,
                 ST_READ_DATA  = 3'd2,
                 ST_WRITE_ADDR = 3'd3,
                 ST_WRITE_DATA = 3'd4;

// ---------------------------------------------------------------------------
// AHB slave — address phase pipeline

wire s_active = s_htrans[1];
reg  s_active_r, s_hwrite_r;
reg  [5:2] s_reg_addr_r;

always @(posedge clk) begin
    s_active_r   <= s_active;
    s_hwrite_r   <= s_hwrite;
    s_reg_addr_r <= s_haddr[5:2];
end

// ---------------------------------------------------------------------------
// Channel registers

reg [31:0] ch_read_addr  [0:NUM_CH-1];
reg [31:0] ch_write_addr [0:NUM_CH-1];
reg [31:0] ch_trans_count[0:NUM_CH-1];
reg [31:0] ch_ctrl       [0:NUM_CH-1];
reg [3:0]  irq_status;

// CTRL field extraction helpers
`define CH_EN(c)         ch_ctrl[c][0]
`define CH_INCR_RD(c)    ch_ctrl[c][1]
`define CH_INCR_WR(c)    ch_ctrl[c][2]
`define CH_DATA_SIZE(c)  ch_ctrl[c][4:3]
`define CH_DREQ_SEL(c)   ch_ctrl[c][7:5]
`define CH_IRQ_EN(c)     ch_ctrl[c][8]

// Transfer size in bytes
function [2:0] size_bytes;
    input [1:0] ds;
    case (ds)
        2'b00: size_bytes = 3'd1;
        2'b01: size_bytes = 3'd2;
        2'b10: size_bytes = 3'd4;
        default: size_bytes = 3'd4;
    endcase
endfunction

// Slave decode helpers
wire [1:0] s_ch_sel  = s_reg_addr_r[5:4]; // which channel (0-3)
wire [1:0] s_reg_sel = s_reg_addr_r[3:2]; // which register in channel
wire       s_wr      = s_active_r && s_hwrite_r;

// ---------------------------------------------------------------------------
// Channel scheduling — round-robin among active channels

wire [NUM_CH-1:0] ch_ready;
genvar g;
generate
    for (g = 0; g < NUM_CH; g = g + 1) begin : gen_ready
        wire [2:0] dsel = `CH_DREQ_SEL(g);
        wire dreq_ok = (dsel == 3'd0) ? 1'b1 :    // free-run
                       (dsel <= 3'd4) ? dreq[dsel - 1] : 1'b0;
        assign ch_ready[g] = `CH_EN(g) && (ch_trans_count[g] != 32'h0) && dreq_ok;
    end
endgenerate

reg [1:0] rr_last;     // last channel serviced
reg [1:0] active_ch;   // currently active channel
reg       has_active;   // any channel is running a transfer

// Round-robin picker
reg [1:0] rr_pick;
reg       rr_valid;
always @(*) begin
    rr_valid = 1'b0;
    rr_pick  = 2'd0;
    if (ch_ready[(rr_last + 1) % NUM_CH]) begin
        rr_pick  = (rr_last + 2'd1);
        rr_valid = 1'b1;
    end else if (ch_ready[(rr_last + 2) % NUM_CH]) begin
        rr_pick  = (rr_last + 2'd2);
        rr_valid = 1'b1;
    end else if (ch_ready[(rr_last + 3) % NUM_CH]) begin
        rr_pick  = (rr_last + 2'd3);
        rr_valid = 1'b1;
    end else if (ch_ready[rr_last]) begin
        rr_pick  = rr_last;
        rr_valid = 1'b1;
    end
end

// ---------------------------------------------------------------------------
// Master-side FSM + unified register update
//
// All writes to channel registers happen in this single always block
// to avoid multi-driver conflicts between CPU slave writes and DMA
// internal updates (address increment, count decrement, auto-disable).

reg [2:0]  m_state;
reg [31:0] m_read_buf;

assign m_hwdata = m_read_buf;

// Signal: DMA just completed a transfer beat (write phase done)
wire xfer_done = (m_state == ST_WRITE_DATA) && m_hready;

// Signal: DMA transfer was the last one for this channel
wire xfer_last = xfer_done && (ch_trans_count[active_ch] == 32'd1);

// Signal: CPU is aborting a running channel (disabled it mid-flight)
wire abort = has_active && !`CH_EN(active_ch) && (m_state != ST_IDLE);

integer i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < NUM_CH; i = i + 1) begin
            ch_read_addr[i]   <= 32'h0;
            ch_write_addr[i]  <= 32'h0;
            ch_trans_count[i] <= 32'h0;
            ch_ctrl[i]        <= 32'h0;
        end
        irq_status <= 4'h0;

        m_state    <= ST_IDLE;
        m_haddr    <= 32'h0;
        m_hwrite   <= 1'b0;
        m_htrans   <= 2'b00;
        m_hsize    <= 3'b010;
        m_read_buf <= 32'h0;
        active_ch  <= 2'd0;
        has_active <= 1'b0;
        rr_last    <= 2'd3;
    end else begin
        // --- CPU slave writes (lowest priority, DMA updates override) ---
        if (s_wr) begin
            if (s_reg_addr_r < 4'd10) begin
                case (s_reg_sel)
                    2'd0: ch_read_addr[s_ch_sel]   <= s_hwdata;
                    2'd1: ch_write_addr[s_ch_sel]  <= s_hwdata;
                    2'd2: ch_trans_count[s_ch_sel] <= s_hwdata;
                    2'd3: ch_ctrl[s_ch_sel]        <= s_hwdata;
                endcase
            end else if (s_reg_addr_r == 4'd10) begin
                irq_status <= irq_status & ~s_hwdata[3:0];
            end
        end

        // --- DMA transfer completion updates (overrides CPU if same cycle) ---
        if (xfer_done) begin
            if (`CH_INCR_RD(active_ch))
                ch_read_addr[active_ch] <= ch_read_addr[active_ch] +
                    {29'h0, size_bytes(`CH_DATA_SIZE(active_ch))};
            if (`CH_INCR_WR(active_ch))
                ch_write_addr[active_ch] <= ch_write_addr[active_ch] +
                    {29'h0, size_bytes(`CH_DATA_SIZE(active_ch))};

            ch_trans_count[active_ch] <= ch_trans_count[active_ch] - 32'd1;

            if (xfer_last) begin
                ch_ctrl[active_ch][0] <= 1'b0;  // auto-disable
                if (`CH_IRQ_EN(active_ch))
                    irq_status[active_ch] <= 1'b1;
            end
        end

        // --- Master FSM ---
        case (m_state)
            ST_IDLE: begin
                m_htrans <= 2'b00;
                m_hwrite <= 1'b0;
                if (rr_valid) begin
                    active_ch  <= rr_pick;
                    has_active <= 1'b1;
                    m_state    <= ST_READ_ADDR;
                end else begin
                    has_active <= 1'b0;
                end
            end

            ST_READ_ADDR: begin
                m_haddr  <= ch_read_addr[active_ch];
                m_hwrite <= 1'b0;
                m_htrans <= 2'b10;
                m_hsize  <= {1'b0, `CH_DATA_SIZE(active_ch)};
                m_state  <= ST_READ_DATA;
            end

            ST_READ_DATA: begin
                m_htrans <= 2'b00;
                if (m_hready) begin
                    m_read_buf <= m_hrdata;
                    m_state    <= ST_WRITE_ADDR;
                end
            end

            ST_WRITE_ADDR: begin
                m_haddr  <= ch_write_addr[active_ch];
                m_hwrite <= 1'b1;
                m_htrans <= 2'b10;
                m_hsize  <= {1'b0, `CH_DATA_SIZE(active_ch)};
                m_state  <= ST_WRITE_DATA;
            end

            ST_WRITE_DATA: begin
                m_htrans <= 2'b00;
                m_hwrite <= 1'b0;
                if (m_hready) begin
                    rr_last <= active_ch;
                    m_state <= ST_IDLE;
                end
            end

            default: m_state <= ST_IDLE;
        endcase

        // CPU abort — disable mid-transfer
        if (abort) begin
            m_htrans <= 2'b00;
            m_hwrite <= 1'b0;
            m_state  <= ST_IDLE;
        end
    end
end

// ---------------------------------------------------------------------------
// AHB slave read handler

reg [31:0] s_rdata;
always @(*) begin
    if (s_reg_addr_r < 4'd10) begin
        case (s_reg_sel)
            2'd0: s_rdata = ch_read_addr[s_ch_sel];
            2'd1: s_rdata = ch_write_addr[s_ch_sel];
            2'd2: s_rdata = ch_trans_count[s_ch_sel];
            2'd3: s_rdata = ch_ctrl[s_ch_sel];
        endcase
    end else if (s_reg_addr_r == 4'd10) begin
        s_rdata = {28'h0, irq_status};
    end else begin
        s_rdata = 32'h0;
    end
end

assign s_hrdata = s_rdata;
assign s_hready = 1'b1;
assign s_hresp  = 1'b0;

// ---------------------------------------------------------------------------
// IRQ output

assign dma_irq = |(irq_status & {`CH_IRQ_EN(3), `CH_IRQ_EN(2),
                                  `CH_IRQ_EN(1), `CH_IRQ_EN(0)});

endmodule
