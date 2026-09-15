// dma.sv — 4-channel DMA controller with AHB-Lite slave + master ports.
//
// Base address: caller-defined (decoder handles base; offsets below are relative).
//
// 4-channel DMA with round-robin scheduling, DREQ pacing, and auto-disable.
// Each channel performs single-beat AHB-Lite read→write transfers. Channels
// are DREQ-paced (peripheral requests data) or free-running (DREQ_SEL=0).
//
// Register map (byte offset from base):
//   Channel N registers (N=0..3, stride = 0x10):
//     0x00 + N*0x10  READ_ADDR    [31:0]  source address (read/write)
//                                          auto-incremented if INCR_READ=1
//     0x04 + N*0x10  WRITE_ADDR   [31:0]  destination address (read/write)
//                                          auto-incremented if INCR_WRITE=1
//     0x08 + N*0x10  TRANS_COUNT  [31:0]  transfers remaining (read/write)
//                                          decremented after each transfer
//     0x0C + N*0x10  CTRL         [31:0]  channel control (read/write)
//                                          [0]    EN — channel enable
//                                          [1]    INCR_READ — auto-increment source
//                                          [2]    INCR_WRITE — auto-increment dest
//                                          [4:3]  DATA_SIZE — 00=byte, 01=half, 10=word
//                                          [7:5]  DREQ_SEL — 0=free-run, 1..4=dreq[0..3]
//                                          [8]    IRQ_EN — assert IRQ on completion
//                                          [12:9] CHAIN_TO — channel to trigger on
//                                                 completion (>=NUM_CH = no chain)
//                                          [13]   RING_SEL — 0=ring read, 1=ring write
//                                          [17:14] RING_SIZE — log2(ring bytes),
//                                                  0=disabled, e.g. 4=16-byte ring
//
//   Global registers:
//     0x40  IRQ_STATUS  [3:0]  per-channel completion flag (read, write-1-to-clear)
//                               bit N set when channel N TRANS_COUNT reaches 0
//
// Transfer flow:
//   1. CPU writes READ_ADDR, WRITE_ADDR, TRANS_COUNT, CTRL (with EN=1)
//   2. DMA waits for DREQ (or runs immediately if DREQ_SEL=0)
//   3. DMA issues AHB read from READ_ADDR, captures data
//   4. DMA issues AHB write to WRITE_ADDR with captured data
//   5. Addresses incremented, TRANS_COUNT decremented
//   6. When TRANS_COUNT reaches 0: channel auto-disables (EN=0),
//      IRQ_STATUS[N] set if IRQ_EN=1
//   7. Round-robin picks next ready channel
//
// Master port issues single-beat (non-burst) AHB-Lite reads and writes.
// dma_irq = OR of all channels where (IRQ_STATUS[N] & CTRL[N].IRQ_EN).
//
// Not implemented (RP2040 DMA differences):
//   (Chain trigger and ring buffer are now implemented — see CTRL fields above)
//   Byte lane swapping  — RP2040 CTRL has BSWAP for endianness conversion
//   Sniff / CRC         — RP2040 DMA can CRC/checksum data as it flows through
//   CTRL aliases        — RP2040 has CTRL_TRIG (write triggers channel start)
//   Priority levels     — RP2040 has HIGH_PRIORITY bit; we use strict round-robin
//   12 channels         — RP2040 has 12 channels; we have 4
//   Timer pacing        — RP2040 DMA has 4 internal pace timers
//   Channel abort       — RP2040 CHAN_ABORT register for safe mid-transfer abort
//   Debug registers     — RP2040 DBG_CTDREQ / DBG_TCR for debug visibility
//
// Known limitations:
//   - 4 channels only (RP2040 has 12)
//   - Single-beat transfers: no burst mode, one AHB read + one AHB write per beat
//   - DREQ inputs are 4-wide (dreq[3:0]); DREQ_SEL values 5-7 map to nothing
//   - Chain trigger only sets EN on target; does not reload TRANS_COUNT or addresses
//   - Ring buffer wraps address within a power-of-2 window; only one of read/write
//   - CPU can abort a channel by clearing EN, but mid-flight transfers complete
//   - Round-robin is strict: no priority levels
//   - No byte/halfword lane alignment (DATA_SIZE passed to AHB hsize only)
//
// AHB pipeline: address phase registers htrans/hwrite/haddr; data phase captures
// hwdata for writes and returns hrdata combinationally for reads.

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
`define CH_CHAIN_TO(c)   ch_ctrl[c][12:9]
`define CH_RING_SEL(c)   ch_ctrl[c][13]
`define CH_RING_SIZE(c)  ch_ctrl[c][17:14]

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

// Ring-wrap address: increments within a power-of-2 window, upper bits unchanged.
// ring_size = log2(bytes); 0 means disabled (plain increment).
function [31:0] ring_incr;
    input [31:0] addr;
    input [2:0]  incr;
    input [3:0]  ring_size;
    reg [31:0] mask;
    reg [31:0] next;
    begin
        if (ring_size == 4'd0) begin
            ring_incr = addr + {29'h0, incr};
        end else begin
            mask = (32'd1 << ring_size) - 32'd1;
            next = addr + {29'h0, incr};
            ring_incr = (addr & ~mask) | (next & mask);
        end
    end
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
            if (`CH_INCR_RD(active_ch)) begin
                ch_read_addr[active_ch] <= ring_incr(
                    ch_read_addr[active_ch],
                    size_bytes(`CH_DATA_SIZE(active_ch)),
                    `CH_RING_SEL(active_ch) ? 4'd0 : `CH_RING_SIZE(active_ch)
                );
            end
            if (`CH_INCR_WR(active_ch)) begin
                ch_write_addr[active_ch] <= ring_incr(
                    ch_write_addr[active_ch],
                    size_bytes(`CH_DATA_SIZE(active_ch)),
                    `CH_RING_SEL(active_ch) ? `CH_RING_SIZE(active_ch) : 4'd0
                );
            end

            ch_trans_count[active_ch] <= ch_trans_count[active_ch] - 32'd1;

            if (xfer_last) begin
                ch_ctrl[active_ch][0] <= 1'b0;  // auto-disable
                if (`CH_IRQ_EN(active_ch))
                    irq_status[active_ch] <= 1'b1;
                // Chain trigger: enable the target channel
                if (`CH_CHAIN_TO(active_ch) < NUM_CH[3:0])
                    ch_ctrl[`CH_CHAIN_TO(active_ch)[1:0]][0] <= 1'b1;
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
