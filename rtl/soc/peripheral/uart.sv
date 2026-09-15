// uart.sv — AHB-Lite UART peripheral (8N1, TX+RX, configurable baud).
// Register layout compatible with ARM PL011 (subset).
//
// Base address: caller-defined (decoder handles base; offsets below are relative).
//
// Register map (byte offset from base):
//   0x000  UARTDR     [11:0]  write[7:0] = enqueue TX FIFO
//                              read[7:0]  = dequeue RX FIFO
//                              read[11]   = overrun error (OE)
//                              read[10:8] = 0 (BE/PE/FE not implemented)
//   0x018  UARTFR     [7:3]   flags (read-only)
//                               [7] TXFE — TX FIFO empty
//                               [6] RXFF — RX FIFO full
//                               [5] TXFF — TX FIFO full
//                               [4] RXFE — RX FIFO empty
//                               [3] BUSY — transmitter active
//   0x024  UARTIBRD   [15:0]  integer baud-rate divisor (cycles per bit)
//   0x028  UARTFBRD   [5:0]   fractional baud-rate divisor (6-bit accumulator)
//   0x02C  UARTLCR_H  [7:0]   line control (accepted; 8N1 hardwired)
//   0x030  UARTCR     [15:0]  control: [0]=UARTEN, [8]=TXE, [9]=RXE,
//                               [11]=RTSEn, [14]=CTSEn, [15]=LBE (loopback)
//   0x034  UARTIFLS   [5:0]   FIFO level select: [5:3]=RXIFLSEL, [2:0]=TXIFLSEL
//   0x038  UARTIMSC   [10:0]  interrupt mask: [10]=OE, [6]=RT, [5]=TX, [4]=RX
//   0x03C  UARTRIS    [10:0]  raw interrupt status (read-only)
//   0x040  UARTMIS    [10:0]  masked interrupt status (read-only)
//   0x044  UARTICR    [10:0]  interrupt clear (write-1-to-clear for latched bits)
//   0x048  UARTDMACR  [2:0]   DMA control: [2]=DMAONERR, [1]=TXDMAE, [0]=RXDMAE
//
// Not implemented (out of scope):
//   0x004  UARTRSR/ECR        — error status mirror of DR[11:8]; redundant
//   0x020  UARTILPR           — IrDA low-power counter; no IR support
//   0xFE0  UARTPeriphID0-3    — PL011 identification constants (TODO: add later)
//   0xFF0  UARTPCellID0-3     — PrimeCell identification constants (TODO: add later)
//
// Interrupt sources not implemented (permanently zero):
//   Bit 9  BEIM  — break error (no break detection)
//   Bit 8  PEIM  — parity error (8N1 hardwired, no parity)
//   Bit 7  FEIM  — framing error (not tracked)
//   Bits 3:0     — modem interrupts (RI/DCD/DSR/CTS edge; legacy RS-232)
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

    // DMA requests (active high, active when FIFO can accept/provide data)
    output wire        uart_tx_dreq,
    output wire        uart_rx_dreq,

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
localparam [5:0] ADDR_IFLS  = 6'h0D; // 0x034
localparam [5:0] ADDR_IMSC  = 6'h0E; // 0x038
localparam [5:0] ADDR_RIS   = 6'h0F; // 0x03C
localparam [5:0] ADDR_MIS   = 6'h10; // 0x040
localparam [5:0] ADDR_ICR   = 6'h11; // 0x044
localparam [5:0] ADDR_DMACR = 6'h12; // 0x048

// ---------------------------------------------------------------------------
// Configuration registers

reg [15:0] ibrd;    // baud divisor (cycles per bit)
reg  [5:0] fbrd;    // fractional baud divisor
reg  [7:0] lcr_h;   // line control — accepted, 8N1 hardwired
reg [15:0] cr;      // [0]=UARTEN, [8]=TXE, [9]=RXE, [11]=RTSEn, [14]=CTSEn, [15]=LBE
reg  [5:0] ifls;    // [5:3]=RXIFLSEL, [2:0]=TXIFLSEL
reg  [2:0] dmacr;   // [2]=DMAONERR, [1]=TXDMAE, [0]=RXDMAE

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

wire [FIFO_AW:0] tx_level = tx_wptr - tx_rptr;

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

wire [FIFO_AW:0] rx_level = rx_wptr - rx_rptr;

// ---------------------------------------------------------------------------
// FIFO interrupt level select (UARTIFLS) threshold decode
//
// TXIFLSEL: TX interrupt fires when tx_level <= threshold (room in FIFO)
// RXIFLSEL: RX interrupt fires when rx_level >= threshold (data available)
//
// Encoding for 8-deep FIFO:
//   000 = 1/8 → 1    001 = 1/4 → 2    010 = 1/2 → 4 (default)
//   011 = 3/4 → 6    100 = 7/8 → 7

reg [FIFO_AW:0] tx_ifls_threshold;
reg [FIFO_AW:0] rx_ifls_threshold;

always @(*) begin
    case (ifls[2:0])
        3'd0:    tx_ifls_threshold = 1;
        3'd1:    tx_ifls_threshold = 2;
        3'd2:    tx_ifls_threshold = 4;
        3'd3:    tx_ifls_threshold = 6;
        3'd4:    tx_ifls_threshold = 7;
        default: tx_ifls_threshold = 4;
    endcase
end

always @(*) begin
    case (ifls[5:3])
        3'd0:    rx_ifls_threshold = 1;
        3'd1:    rx_ifls_threshold = 2;
        3'd2:    rx_ifls_threshold = 4;
        3'd3:    rx_ifls_threshold = 6;
        3'd4:    rx_ifls_threshold = 7;
        default: rx_ifls_threshold = 4;
    endcase
end

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

// Pulse high for one cycle when RX byte is successfully pushed to FIFO
reg        rx_byte_pushed;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_state       <= RX_IDLE;
        rx_baud_cnt    <= 16'h0;
        rx_shift       <= 8'h0;
        rx_bit_cnt     <= 3'h0;
        rx_wptr        <= '0;
        rx_frac_acc    <= 6'h0;
        rx_byte_pushed <= 1'b0;
    end else begin
        rx_byte_pushed <= 1'b0;

        case (rx_state)

            RX_IDLE: begin
                if (uarten && rxe && !rx_in) begin
                    rx_baud_cnt <= (ibrd >> 1) - 1;
                    rx_frac_acc <= 6'h0;
                    rx_state    <= RX_START;
                end
            end

            RX_START: begin
                if (rx_baud_cnt == 16'h0) begin
                    if (!rx_in) begin
                        rx_baud_cnt <= ibrd - 1 + {15'b0, rx_frac_next[6]};
                        rx_frac_acc <= rx_frac_next[5:0];
                        rx_bit_cnt  <= 3'd0;
                        rx_state    <= RX_DATA;
                    end else begin
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
                        rx_mem[rx_widx] <= rx_shift;
                        rx_wptr         <= rx_wptr + 1;
                        rx_byte_pushed  <= 1'b1;
                    end
                    // Overrun (rx_in && rx_full) handled by oe_latch below
                    rx_state <= RX_IDLE;
                end else begin
                    rx_baud_cnt <= rx_baud_cnt - 1;
                end
            end

        endcase
    end
end

// ---------------------------------------------------------------------------
// Overrun error latch — set when valid stop bit arrives but RX FIFO is full
// Cleared by writing 1 to UARTICR[10].

wire rx_overrun_event = (rx_state == RX_STOP) && (rx_baud_cnt == 16'h0) &&
                         rx_in && rx_full;

wire icr_write = active_r && hwrite_r && (reg_addr_r == ADDR_ICR);

reg oe_latch;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        oe_latch <= 1'b0;
    else if (icr_write && hwdata[10])
        oe_latch <= 1'b0;
    else if (rx_overrun_event)
        oe_latch <= 1'b1;
end

// ---------------------------------------------------------------------------
// Receive timeout — fires when RX FIFO has data but no new byte arrives
// for 32 bit periods.  Prescales clk by ibrd, then counts 32 bit ticks.
// Cleared by writing 1 to UARTICR[6].

wire rx_fifo_read = active_r && !hwrite_r && (reg_addr_r == ADDR_DR) && !rx_empty;

reg [15:0] rt_baud_cnt;
reg  [5:0] rt_bit_cnt;
reg        rt_latch;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rt_baud_cnt <= 16'h0;
        rt_bit_cnt  <= 6'h0;
        rt_latch    <= 1'b0;
    end else if (icr_write && hwdata[6]) begin
        // ICR clear — reset the entire timeout machine
        rt_latch    <= 1'b0;
        rt_baud_cnt <= 16'h0;
        rt_bit_cnt  <= 6'h0;
    end else if (rx_empty || rx_byte_pushed || rx_fifo_read) begin
        // Reset counter: FIFO drained, new byte arrived, or firmware read DR
        rt_baud_cnt <= 16'h0;
        rt_bit_cnt  <= 6'h0;
    end else if (!rx_empty && !rt_latch) begin
        // Count towards 32 bit-period timeout
        if (rt_baud_cnt >= ibrd - 1) begin
            rt_baud_cnt <= 16'h0;
            if (rt_bit_cnt == 6'd31) begin
                rt_latch <= 1'b1;
            end else begin
                rt_bit_cnt <= rt_bit_cnt + 1;
            end
        end else begin
            rt_baud_cnt <= rt_baud_cnt + 1;
        end
    end
end

// ---------------------------------------------------------------------------
// Interrupt status
//
// RIS bits implemented:
//   [10] OERIS  — overrun error (latched, cleared by ICR)
//   [6]  RTRIS  — receive timeout (latched, cleared by ICR)
//   [5]  TXRIS  — TX FIFO at or below IFLS threshold (level, auto-clears)
//   [4]  RXRIS  — RX FIFO at or above IFLS threshold (level, auto-clears)
//
// Permanently zero: [9:7] BE/PE/FE, [3:0] modem

wire [10:0] ris = {oe_latch,                           // [10] OE
                   3'b0,                                // [9:7] BE/PE/FE
                   rt_latch,                            // [6]  RT
                   (tx_level <= tx_ifls_threshold),     // [5]  TX
                   (rx_level >= rx_ifls_threshold),     // [4]  RX
                   4'b0};                               // [3:0] modem
wire [10:0] mis = ris & imsc;

// ---------------------------------------------------------------------------
// AHB write handler (data phase)

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ibrd    <= 16'd1;
        fbrd    <= 6'h0;
        lcr_h   <= 8'h0;
        cr      <= 16'h0300;  // TXE=1, RXE=1, UARTEN=0
        ifls    <= 6'b010_010; // both 1/2 full (PL011 default)
        imsc    <= 11'h0;
        dmacr   <= 3'h0;
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
            ADDR_IFLS:  ifls  <= hwdata[5:0];
            ADDR_IMSC:  imsc  <= hwdata[10:0];
            ADDR_ICR:   ;     // handled by oe_latch / rt_latch blocks above
            ADDR_DMACR: dmacr <= hwdata[2:0];
            default: ;
        endcase
    end
end

// ---------------------------------------------------------------------------
// AHB read handler — RX FIFO dequeue on DR read

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_rptr <= '0;
    end else if (rx_fifo_read) begin
        rx_rptr <= rx_rptr + 1;
    end
end

// ---------------------------------------------------------------------------
// AHB read data (combinational)

wire [31:0] uartfr = {24'h0,
                      tx_empty,   // [7] TXFE
                      rx_full,    // [6] RXFF
                      tx_full,    // [5] TXFF
                      rx_empty,   // [4] RXFE
                      tx_busy,    // [3] BUSY
                      3'h0};

assign hrdata = (reg_addr_r == ADDR_DR)    ? {20'h0, oe_latch, 3'b0, rx_mem[rx_ridx]} :
                (reg_addr_r == ADDR_FR)    ? uartfr                    :
                (reg_addr_r == ADDR_IBRD)  ? {16'h0, ibrd}             :
                (reg_addr_r == ADDR_FBRD)  ? {26'h0, fbrd}             :
                (reg_addr_r == ADDR_LCR_H) ? {24'h0, lcr_h}            :
                (reg_addr_r == ADDR_CR)    ? {16'h0, cr}               :
                (reg_addr_r == ADDR_IFLS)  ? {26'h0, ifls}             :
                (reg_addr_r == ADDR_IMSC)  ? {21'h0, imsc}             :
                (reg_addr_r == ADDR_RIS)   ? {21'h0, ris}              :
                (reg_addr_r == ADDR_MIS)   ? {21'h0, mis}              :
                (reg_addr_r == ADDR_DMACR) ? {29'h0, dmacr}            :
                                             32'h0;

assign hready = 1'b1;
assign hresp  = 1'b0;

// RTS: deassert (high) when RX FIFO is full — tells sender to stop
assign uart_rts_n = (rtsen && rx_full) ? 1'b1 : 1'b0;

// DMA requests, gated by DMACR enable bits
// DMAONERR: block both channels if any error bit is set in RIS[10:7]
wire dma_err_block = dmacr[2] && (|ris[10:7]);
assign uart_tx_dreq = dmacr[1] && !tx_full  && !dma_err_block;
assign uart_rx_dreq = dmacr[0] && !rx_empty && !dma_err_block;

assign uart_irq = |mis;

endmodule
