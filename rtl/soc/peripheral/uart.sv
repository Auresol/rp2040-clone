// uart.sv — AHB-Lite UART peripheral (8N1, TX+RX, configurable baud).
// Register layout compatible with ARM PL011 (subset).
//
// Base address: caller-defined (decoder handles base; offsets below are relative).
//
// Register map (byte offset from base):
//   0x000  UARTDR   [7:0]   write = enqueue TX FIFO; read = dequeue RX FIFO
//   0x018  UARTFR   [7:3]   flags (read-only)
//                             [7] TXFE — TX FIFO empty
//                             [6] RXFF — RX FIFO full
//                             [5] TXFF — TX FIFO full
//                             [4] RXFE — RX FIFO empty
//                             [3] BUSY — transmitter active
//   0x024  UARTIBRD [15:0]  integer baud-rate divisor (cycles per bit)
//   0x028  UARTFBRD [5:0]   fractional baud-rate divisor (6-bit accumulator)
//   0x02C  UARTLCR_H[7:0]   line control (accepted; 8N1 hardwired)
//   0x030  UARTCR   [15:0]  control: [0]=UARTEN, [8]=TXE, [9]=RXE,
//                             [11]=RTSEn, [14]=CTSEn, [15]=LBE (loopback)
//   0x038  UARTIMSC [10:0]  interrupt mask: [5]=TXIM, [4]=RXIM
//   0x03C  UARTRIS  [10:0]  raw interrupt status (read-only)
//   0x040  UARTMIS  [10:0]  masked interrupt status (read-only)
//   0x044  UARTICR  [10:0]  interrupt clear (write-1-to-clear; level IRQs auto-clear)
//
// Baud rate: set IBRD = clk_hz / baud_rate
//   e.g. 125 MHz / 115200 ≈ 1085 for FPGA; use small value (e.g. 10) in sim.
//
// AHB pipeline: address phase registers htrans/hwrite/haddr; data phase captures
// hwdata for writes and returns hrdata combinationally for reads.

`default_nettype none

module uart (
    input  wire        clk,
    input  wire        rst_n,

    // AHB-Lite slave port
    input  wire [31:0] haddr,
    input  wire        hwrite,
    input  wire [1:0]  htrans,
    input  wire [2:0]  hsize,
    input  wire [31:0] hwdata,
    output wire [31:0] hrdata,
    output wire        hready,
    output wire        hresp,

    // UART pins
    output wire        uart_tx,
    input  wire        uart_rx,

    // Hardware flow control
    output wire        uart_rts_n,  // Request To Send (active low)
    input  wire        uart_cts_n,  // Clear To Send (active low)

    // DMA request
    output wire        uart_dreq,

    // Interrupt
    output wire        uart_irq
);

// ---------------------------------------------------------------------------
// AHB pipeline registers

wire active = htrans[1];
reg  active_r, hwrite_r;
reg  [7:2] reg_addr_r;

always @(posedge clk) begin
    active_r   <= active;
    hwrite_r   <= hwrite;
    reg_addr_r <= haddr[7:2];
end

// ---------------------------------------------------------------------------
// Register word-address constants (byte_offset >> 2)

localparam [5:0] ADDR_DR    = 6'h00; // 0x000
localparam [5:0] ADDR_FR    = 6'h06; // 0x018
localparam [5:0] ADDR_IBRD  = 6'h09; // 0x024
localparam [5:0] ADDR_FBRD  = 6'h0A; // 0x028
localparam [5:0] ADDR_LCR_H = 6'h0B; // 0x02C
localparam [5:0] ADDR_CR    = 6'h0C; // 0x030
localparam [5:0] ADDR_IMSC  = 6'h0E; // 0x038
localparam [5:0] ADDR_RIS   = 6'h0F; // 0x03C
localparam [5:0] ADDR_MIS   = 6'h10; // 0x040
localparam [5:0] ADDR_ICR   = 6'h11; // 0x044

// ---------------------------------------------------------------------------
// Configuration registers

reg [15:0] ibrd;    // baud divisor (cycles per bit)
reg  [5:0] fbrd;    // fractional — accepted, ignored
reg  [7:0] lcr_h;   // line control — accepted, 8N1 hardwired
reg [15:0] cr;      // [0]=UARTEN, [8]=TXE, [9]=RXE

wire uarten = cr[0];
wire txe    = cr[8];
wire rxe    = cr[9];
wire rtsen  = cr[11];  // hardware RTS enable
wire ctsen  = cr[14];  // hardware CTS enable
wire lbe    = cr[15];  // loopback enable

reg [10:0] imsc;   // interrupt mask (PL011 bits [10:0])

// ---------------------------------------------------------------------------
// TX FIFO — 8 entries, 8-bit wide

localparam FIFO_DEPTH = 8;
localparam FIFO_AW    = 3;   // log2(FIFO_DEPTH)

reg [7:0]         tx_mem  [0:FIFO_DEPTH-1];
reg [FIFO_AW:0]   tx_wptr;   // extra bit for full/empty
reg [FIFO_AW:0]   tx_rptr;

wire tx_full  = (tx_wptr[FIFO_AW] != tx_rptr[FIFO_AW]) &&
                (tx_wptr[FIFO_AW-1:0] == tx_rptr[FIFO_AW-1:0]);
wire tx_empty = (tx_wptr == tx_rptr);

wire [FIFO_AW-1:0] tx_widx = tx_wptr[FIFO_AW-1:0];
wire [FIFO_AW-1:0] tx_ridx = tx_rptr[FIFO_AW-1:0];

// ---------------------------------------------------------------------------
// RX FIFO — 8 entries, 8-bit wide

reg [7:0]         rx_mem  [0:FIFO_DEPTH-1];
reg [FIFO_AW:0]   rx_wptr;
reg [FIFO_AW:0]   rx_rptr;

wire rx_full  = (rx_wptr[FIFO_AW] != rx_rptr[FIFO_AW]) &&
                (rx_wptr[FIFO_AW-1:0] == rx_rptr[FIFO_AW-1:0]);
wire rx_empty = (rx_wptr == rx_rptr);

wire [FIFO_AW-1:0] rx_widx = rx_wptr[FIFO_AW-1:0];
wire [FIFO_AW-1:0] rx_ridx = rx_rptr[FIFO_AW-1:0];

// ---------------------------------------------------------------------------
// Fractional baud — accumulate fbrd each bit period, carry adds +1 cycle

reg  [5:0] tx_frac_acc;
reg  [5:0] rx_frac_acc;
wire [6:0] tx_frac_next = tx_frac_acc + fbrd;
wire [6:0] rx_frac_next = rx_frac_acc + fbrd;

// ---------------------------------------------------------------------------
// TX state machine — START + 8 DATA bits (LSB first) + STOP

localparam [1:0] TX_IDLE  = 2'd0;
localparam [1:0] TX_START = 2'd1;
localparam [1:0] TX_DATA  = 2'd2;
localparam [1:0] TX_STOP  = 2'd3;

reg [1:0]  tx_state;
reg [15:0] tx_baud_cnt;
reg [7:0]  tx_shift;
reg [2:0]  tx_bit_cnt;
reg        tx_pin;

wire tx_busy = (tx_state != TX_IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_state    <= TX_IDLE;
        tx_baud_cnt <= 16'h0;
        tx_shift    <= 8'h0;
        tx_bit_cnt  <= 3'h0;
        tx_pin      <= 1'b1;
        tx_rptr     <= '0;
        tx_frac_acc <= 6'h0;
    end else begin
        case (tx_state)

            TX_IDLE: begin
                tx_pin <= 1'b1;
                if (uarten && txe && !tx_empty && !(ctsen && uart_cts_n)) begin
                    tx_shift    <= tx_mem[tx_ridx];
                    tx_rptr     <= tx_rptr + 1;
                    tx_pin      <= 1'b0;           // drive start bit
                    tx_baud_cnt <= ibrd - 1;
                    tx_frac_acc <= 6'h0;            // reset accumulator per byte
                    tx_state    <= TX_START;
                end
            end

            TX_START: begin
                if (tx_baud_cnt == 16'h0) begin
                    tx_pin      <= tx_shift[0];    // first data bit
                    tx_bit_cnt  <= 3'd0;
                    tx_baud_cnt <= ibrd - 1 + {15'b0, tx_frac_next[6]};
                    tx_frac_acc <= tx_frac_next[5:0];
                    tx_state    <= TX_DATA;
                end else begin
                    tx_baud_cnt <= tx_baud_cnt - 1;
                end
            end

            TX_DATA: begin
                if (tx_baud_cnt == 16'h0) begin
                    if (tx_bit_cnt == 3'd7) begin
                        tx_pin      <= 1'b1;       // stop bit
                        tx_baud_cnt <= ibrd - 1 + {15'b0, tx_frac_next[6]};
                        tx_frac_acc <= tx_frac_next[5:0];
                        tx_state    <= TX_STOP;
                    end else begin
                        // non-blocking: reads current tx_bit_cnt, so shift[cnt+1] is next bit
                        tx_pin      <= tx_shift[tx_bit_cnt + 1];
                        tx_bit_cnt  <= tx_bit_cnt + 1;
                        tx_baud_cnt <= ibrd - 1 + {15'b0, tx_frac_next[6]};
                        tx_frac_acc <= tx_frac_next[5:0];
                    end
                end else begin
                    tx_baud_cnt <= tx_baud_cnt - 1;
                end
            end

            TX_STOP: begin
                if (tx_baud_cnt == 16'h0) begin
                    tx_state <= TX_IDLE;
                end else begin
                    tx_baud_cnt <= tx_baud_cnt - 1;
                end
            end

        endcase
    end
end

assign uart_tx = uarten ? tx_pin : 1'b1;

// ---------------------------------------------------------------------------
// RX synchroniser (2-stage metastability guard)
// Loopback: feed tx_pin back into RX path instead of external uart_rx.

wire rx_pin = lbe ? tx_pin : uart_rx;

reg [1:0] rx_sync;
wire rx_in = rx_sync[1];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) rx_sync <= 2'b11;
    else        rx_sync <= {rx_sync[0], rx_pin};
end

// ---------------------------------------------------------------------------
// RX state machine — detect start bit, sample 8 data bits, check stop bit

localparam [1:0] RX_IDLE  = 2'd0;
localparam [1:0] RX_START = 2'd1;
localparam [1:0] RX_DATA  = 2'd2;
localparam [1:0] RX_STOP  = 2'd3;

reg [1:0]  rx_state;
reg [15:0] rx_baud_cnt;
reg [7:0]  rx_shift;
reg [2:0]  rx_bit_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_state    <= RX_IDLE;
        rx_baud_cnt <= 16'h0;
        rx_shift    <= 8'h0;
        rx_bit_cnt  <= 3'h0;
        rx_wptr     <= '0;
        rx_frac_acc <= 6'h0;
    end else begin
        case (rx_state)

            RX_IDLE: begin
                // Wait for falling edge (start bit)
                if (uarten && rxe && !rx_in) begin
                    // Wait half a baud period to sample in the middle of start bit
                    rx_baud_cnt <= (ibrd >> 1) - 1;
                    rx_frac_acc <= 6'h0;            // reset accumulator per byte
                    rx_state    <= RX_START;
                end
            end

            RX_START: begin
                if (rx_baud_cnt == 16'h0) begin
                    if (!rx_in) begin
                        // Valid start bit — now wait full baud periods for data bits
                        rx_baud_cnt <= ibrd - 1 + {15'b0, rx_frac_next[6]};
                        rx_frac_acc <= rx_frac_next[5:0];
                        rx_bit_cnt  <= 3'd0;
                        rx_state    <= RX_DATA;
                    end else begin
                        // Glitch on line — abort
                        rx_state <= RX_IDLE;
                    end
                end else begin
                    rx_baud_cnt <= rx_baud_cnt - 1;
                end
            end

            RX_DATA: begin
                if (rx_baud_cnt == 16'h0) begin
                    rx_shift    <= {rx_in, rx_shift[7:1]};  // LSB first
                    rx_baud_cnt <= ibrd - 1 + {15'b0, rx_frac_next[6]};
                    rx_frac_acc <= rx_frac_next[5:0];
                    if (rx_bit_cnt == 3'd7) begin
                        rx_state <= RX_STOP;
                    end else begin
                        rx_bit_cnt <= rx_bit_cnt + 1;
                    end
                end else begin
                    rx_baud_cnt <= rx_baud_cnt - 1;
                end
            end

            RX_STOP: begin
                if (rx_baud_cnt == 16'h0) begin
                    if (rx_in && !rx_full) begin
                        // Valid stop bit and FIFO has room — push
                        rx_mem[rx_widx] <= rx_shift;
                        rx_wptr         <= rx_wptr + 1;
                    end
                    rx_state <= RX_IDLE;
                end else begin
                    rx_baud_cnt <= rx_baud_cnt - 1;
                end
            end

        endcase
    end
end

// ---------------------------------------------------------------------------
// AHB write handler (data phase)

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ibrd    <= 16'd1;     // div-by-1 default (overridden by firmware)
        fbrd    <= 6'h0;
        lcr_h   <= 8'h0;
        cr      <= 16'h0300;  // TXE=1, RXE=1, UARTEN=0 — safe default
        imsc    <= 11'h0;
        tx_wptr <= '0;
    end else if (active_r && hwrite_r) begin
        case (reg_addr_r)
            ADDR_DR: begin
                if (!tx_full) begin
                    tx_mem[tx_widx] <= hwdata[7:0];
                    tx_wptr         <= tx_wptr + 1;
                end
            end
            ADDR_IBRD:  ibrd  <= hwdata[15:0];
            ADDR_FBRD:  fbrd  <= hwdata[5:0];
            ADDR_LCR_H: lcr_h <= hwdata[7:0];
            ADDR_CR:    cr    <= hwdata[15:0];
            ADDR_IMSC:  imsc  <= hwdata[10:0];
            ADDR_ICR:   ;     // level IRQs auto-clear, no action needed
            default: ;
        endcase
    end
end

// ---------------------------------------------------------------------------
// AHB read handler — RX FIFO dequeue

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_rptr <= '0;
    end else if (active_r && !hwrite_r && reg_addr_r == ADDR_DR && !rx_empty) begin
        rx_rptr <= rx_rptr + 1;
    end
end

// ---------------------------------------------------------------------------
// AHB read data (combinational)

wire [31:0] uartfr = {24'h0,
                      tx_empty,   // [7] TXFE — TX FIFO empty
                      rx_full,    // [6] RXFF — RX FIFO full
                      tx_full,    // [5] TXFF — TX FIFO full
                      rx_empty,   // [4] RXFE — RX FIFO empty
                      tx_busy,    // [3] BUSY — transmitter active
                      3'h0};

wire [10:0] ris = {1'b0,        // [10] OEIM — overrun (not implemented)
                   1'b0,        // [9]  BEIM — break
                   1'b0,        // [8]  PEIM — parity
                   1'b0,        // [7]  FEIM — framing
                   1'b0,        // [6]  RTIM — receive timeout (not implemented)
                   tx_empty,    // [5]  TXIM — TX FIFO empty
                   !rx_empty,   // [4]  RXIM — RX FIFO has data
                   4'b0};       // [3:0] modem (not implemented)
wire [10:0] mis = ris & imsc;

assign hrdata = (reg_addr_r == ADDR_DR)    ? {24'h0, rx_mem[rx_ridx]} :
                (reg_addr_r == ADDR_FR)    ? uartfr                    :
                (reg_addr_r == ADDR_IBRD)  ? {16'h0, ibrd}             :
                (reg_addr_r == ADDR_FBRD)  ? {26'h0, fbrd}             :
                (reg_addr_r == ADDR_LCR_H) ? {24'h0, lcr_h}            :
                (reg_addr_r == ADDR_CR)    ? {16'h0, cr}               :
                (reg_addr_r == ADDR_IMSC)  ? {21'h0, imsc}             :
                (reg_addr_r == ADDR_RIS)   ? {21'h0, ris}              :
                (reg_addr_r == ADDR_MIS)   ? {21'h0, mis}              :
                                             32'h0;

assign hready = 1'b1;
assign hresp  = 1'b0;

// RTS: deassert (high) when RX FIFO is full — tells sender to stop
assign uart_rts_n = (rtsen && rx_full) ? 1'b1 : 1'b0;

// DMA request: asserted when RX FIFO has data
assign uart_dreq = !rx_empty;

assign uart_irq = |mis;

endmodule
