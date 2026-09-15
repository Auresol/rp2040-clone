// spi.sv — AHB-Lite SPI master peripheral (PL022-compatible subset).
//
// Base address: caller-defined (decoder handles base; offsets below are relative).
//
// Register map (byte offset from base, matches PL022 / RP2040 SSP):
//   0x000  SSPCR0    [15:0]  [15:8]=SCR, [7]=SPH, [6]=SPO, [5:4]=FRF, [3:0]=DSS
//                              FRF: 00=Motorola SPI (only mode supported)
//   0x004  SSPCR1    [3:0]   [1]=SSE (enable), [0]=LBM (loopback)
//   0x008  SSPDR     [15:0]  write = enqueue TX FIFO, read = dequeue RX FIFO
//   0x00C  SSPSR     [4:0]   status (read-only)
//                              [4] BSY — shift engine active
//                              [3] RFF — RX FIFO full
//                              [2] RNE — RX FIFO not empty
//                              [1] TNF — TX FIFO not full
//                              [0] TFE — TX FIFO empty
//   0x010  SSPCPSR   [7:0]   prescaler (even, 2–254)
//   0x014  SSPIFLS   [5:0]   FIFO level select: [5:3]=RXIFLSEL, [2:0]=TXIFLSEL
//   0x018  SSPIMSC   [3:0]   interrupt mask: [3]=TX, [2]=RX, [1]=RT, [0]=ROR
//   0x01C  SSPRIS    [3:0]   raw interrupt status (read-only)
//   0x020  SSPMIS    [3:0]   masked interrupt status (read-only)
//   0x024  SSPICR    [1:0]   interrupt clear (write-1-to-clear for latched bits)
//   0x028  SSPDMACR  [1:0]   DMA control: [1]=TXDMAE, [0]=RXDMAE
//
// Not implemented (out of scope):
//   SSPCR0[5:4] FRF=01       — TI Synchronous Serial Frame format
//   SSPCR0[5:4] FRF=10       — National Semiconductor Microwire format
//   SSPCR1[2]   MS           — slave mode select (master-only)
//   SSPCR1[3]   SOD          — slave output disable (master-only)
//   0xFE0  SSPPeriphID0-3    — PL022 identification constants (TODO: add later)
//   0xFF0  SSPPCellID0-3     — PrimeCell identification constants (TODO: add later)
//
// Interrupt sources not yet implemented (permanently zero):
//   Bit 1  RTRIS  — receive timeout (32 SCK idle with data in RX FIFO)
//   Bit 0  RORRIS — receive overrun (RX write when full; data silently dropped)
//
// Known limitations:
//   - No CS backporch: CS_N deasserts same cycle as last SCK edge (TODO: phase 2)
//   - SSE=0 during active transfer aborts frame instead of completing it
//   - CPSR=0 is undefined (PL022 says UNPREDICTABLE); hardware wraps to slow clock
//
// SCK = clk / (CPSR * (1 + SCR))
// Frame size: DSS+1 bits (4–16), MSB first.
// CS_N asserted automatically during transfer.
//
// AHB pipeline: address phase registers htrans/hwrite/haddr; data phase captures
// hwdata for writes and returns hrdata combinationally for reads.

`default_nettype none

module spi (
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

    // SPI pins
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs_n,

    // Interrupt
    output wire        spi_irq,

    // DMA requests (active when FIFO threshold met and DMAEx enabled)
    output wire        spi_dreq,
    output wire        spi_dreq_tx
);

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

localparam [3:0] ADDR_CR0    = 4'h0; // 0x000
localparam [3:0] ADDR_CR1    = 4'h1; // 0x004
localparam [3:0] ADDR_DR     = 4'h2; // 0x008
localparam [3:0] ADDR_SR     = 4'h3; // 0x00C
localparam [3:0] ADDR_CPSR   = 4'h4; // 0x010
localparam [3:0] ADDR_IFLS   = 4'h5; // 0x014  interrupt FIFO level select
localparam [3:0] ADDR_IMSC   = 4'h6; // 0x018
localparam [3:0] ADDR_RIS    = 4'h7; // 0x01C
localparam [3:0] ADDR_MIS    = 4'h8; // 0x020
localparam [3:0] ADDR_ICR    = 4'h9; // 0x024
localparam [3:0] ADDR_DMACR  = 4'hA; // 0x028

// ---------------------------------------------------------------------------
// Configuration registers

reg [15:0] cr0;    // [15:8] SCR, [7] CPHA, [6] CPOL, [3:0] DSS
reg [3:0]  cr1;    // [1] SSE (enable), [0] LBM (loopback)
reg [7:0]  cpsr;   // clock prescaler (even, 2-254)
reg [5:0]  ifls;   // [5:3] RXIFLSEL, [2:0] TXIFLSEL — reset 3'b010 each (half)
reg [3:0]  imsc;   // interrupt mask
reg [1:0]  dmacr;  // [1] TXDMAE, [0] RXDMAE

wire [7:0] scr  = cr0[15:8];
wire       cpha = cr0[7];
wire       cpol = cr0[6];
wire [3:0] dss  = cr0[3:0];   // frame_bits = dss + 1
wire       sse  = cr1[1];
wire       lbm  = cr1[0];     // loopback mode

// ---------------------------------------------------------------------------
// TX FIFO — 8 entries, 16-bit wide

localparam FIFO_DEPTH = 8;
localparam FIFO_AW    = 3;

reg [15:0]       tx_mem [0:FIFO_DEPTH-1];
reg [FIFO_AW:0]  tx_wptr;
reg [FIFO_AW:0]  tx_rptr;

wire tx_full  = (tx_wptr[FIFO_AW] != tx_rptr[FIFO_AW]) &&
                (tx_wptr[FIFO_AW-1:0] == tx_rptr[FIFO_AW-1:0]);
wire tx_empty = (tx_wptr == tx_rptr);
wire [FIFO_AW-1:0] tx_widx = tx_wptr[FIFO_AW-1:0];
wire [FIFO_AW-1:0] tx_ridx = tx_rptr[FIFO_AW-1:0];

// ---------------------------------------------------------------------------
// RX FIFO — 8 entries, 16-bit wide

reg [15:0]       rx_mem [0:FIFO_DEPTH-1];
reg [FIFO_AW:0]  rx_wptr;
reg [FIFO_AW:0]  rx_rptr;

wire rx_full  = (rx_wptr[FIFO_AW] != rx_rptr[FIFO_AW]) &&
                (rx_wptr[FIFO_AW-1:0] == rx_rptr[FIFO_AW-1:0]);
wire rx_empty = (rx_wptr == rx_rptr);

wire [FIFO_AW-1:0] rx_widx = rx_wptr[FIFO_AW-1:0];
wire [FIFO_AW-1:0] rx_ridx = rx_rptr[FIFO_AW-1:0];

// ---------------------------------------------------------------------------
// SSPIFLS threshold decode — convert 3-bit selector to entry count
//   000 = 1/8 (1), 001 = 1/4 (2), 010 = 1/2 (4), 011 = 3/4 (6), 100 = 7/8 (7)

wire [2:0] txiflsel = ifls[2:0];
wire [2:0] rxiflsel = ifls[5:3];

reg [FIFO_AW:0] tx_thresh;
always @(*) begin
    case (txiflsel)
        3'd0:    tx_thresh = 4'd1;   // 1/8
        3'd1:    tx_thresh = 4'd2;   // 1/4
        3'd2:    tx_thresh = 4'd4;   // 1/2  (reset default)
        3'd3:    tx_thresh = 4'd6;   // 3/4
        default: tx_thresh = 4'd7;   // 7/8
    endcase
end

reg [FIFO_AW:0] rx_thresh;
always @(*) begin
    case (rxiflsel)
        3'd0:    rx_thresh = 4'd1;   // 1/8
        3'd1:    rx_thresh = 4'd2;   // 1/4
        3'd2:    rx_thresh = 4'd4;   // 1/2  (reset default)
        3'd3:    rx_thresh = 4'd6;   // 3/4
        default: rx_thresh = 4'd7;   // 7/8
    endcase
end

// ---------------------------------------------------------------------------
// DMA request outputs — gated by SSPDMACR enables

wire [FIFO_AW:0] tx_level = tx_wptr - tx_rptr;
wire [FIFO_AW:0] rx_level = rx_wptr - rx_rptr;

assign spi_dreq    = dmacr[0] & (rx_level >= rx_thresh);  // RXDMAE
assign spi_dreq_tx = dmacr[1] & (tx_level <= tx_thresh);  // TXDMAE

// ---------------------------------------------------------------------------
// SPI clock divider — two-stage for multiplication-free half-period generation
//
// Stage 1: prescaler divides clk by CPSR/2
// Stage 2: SCR counter divides prescale ticks by (SCR + 1)
// Result: one sck_tick every CPSR/2 * (SCR+1) clocks = one SCK half-period

reg [7:0] pre_cnt;
reg [7:0] scr_cnt;
reg       busy;

wire pre_tick = busy && (pre_cnt == 8'h0);
wire sck_tick = pre_tick && (scr_cnt == 8'h0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        pre_cnt <= 8'h0;
    else if (!busy)
        pre_cnt <= cpsr[7:1] - 8'd1;       // preload for first tick
    else if (pre_cnt == 8'h0)
        pre_cnt <= cpsr[7:1] - 8'd1;       // reload
    else
        pre_cnt <= pre_cnt - 8'd1;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        scr_cnt <= 8'h0;
    else if (!busy)
        scr_cnt <= scr;                     // preload
    else if (pre_tick) begin
        if (scr_cnt == 8'h0)
            scr_cnt <= scr;                 // reload
        else
            scr_cnt <= scr_cnt - 8'd1;
    end
end

// ---------------------------------------------------------------------------
// SPI shift engine
//
// CPHA=0: MOSI setup before first edge. Leading edge = sample, trailing = shift.
// CPHA=1: Leading edge = shift, trailing = sample.
// bit_cnt counts DSS down to 0 (one per SCK period = two sck_ticks).

reg        sck_r;
reg [15:0] tx_shift;
reg [15:0] rx_shift;
reg [3:0]  bit_cnt;
reg        cs_n_r;
reg        half;          // 0 = leading-edge next, 1 = trailing-edge next
reg        mosi_r;

wire miso_in = lbm ? mosi_r : spi_miso;   // loopback mux
wire [15:0] tx_load = tx_mem[tx_ridx] << (4'd15 - dss);  // left-align data

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy     <= 1'b0;
        cs_n_r   <= 1'b1;
        sck_r    <= 1'b0;
        mosi_r   <= 1'b0;
        tx_shift <= 16'h0;
        rx_shift <= 16'h0;
        bit_cnt  <= 4'h0;
        half     <= 1'b0;
        tx_rptr  <= '0;
        rx_wptr  <= '0;
    end else if (!busy) begin
        sck_r <= cpol;                      // idle SCK level
        if (sse && !tx_empty) begin
            // Start new frame
            cs_n_r   <= 1'b0;
            bit_cnt  <= dss;
            half     <= 1'b0;
            busy     <= 1'b1;
            tx_rptr  <= tx_rptr + 1;
            rx_shift <= 16'h0;
            if (!cpha) begin
                // CPHA=0: setup first bit on MOSI before first clock edge
                mosi_r   <= tx_load[15];
                tx_shift <= {tx_load[14:0], 1'b0};
            end else begin
                tx_shift <= tx_load;
            end
        end
    end else if (sck_tick) begin
        sck_r <= ~sck_r;                    // toggle SCK

        if (!half) begin
            // ── Leading edge ─────────────────────────────────────
            if (!cpha)
                rx_shift <= {rx_shift[14:0], miso_in};      // sample
            else begin
                mosi_r   <= tx_shift[15];                    // shift out
                tx_shift <= {tx_shift[14:0], 1'b0};
            end
            half <= 1'b1;
        end else begin
            // ── Trailing edge ────────────────────────────────────
            if (!cpha) begin
                // CPHA=0: advance MOSI or finish frame
                if (bit_cnt == 4'h0) begin
                    if (!rx_full) begin
                        rx_mem[rx_widx] <= rx_shift;
                        rx_wptr         <= rx_wptr + 1;
                    end
                    if (!tx_empty) begin
                        // Back-to-back: start next frame, keep CS low
                        bit_cnt  <= dss;
                        tx_rptr  <= tx_rptr + 1;
                        rx_shift <= 16'h0;
                        mosi_r   <= tx_load[15];
                        tx_shift <= {tx_load[14:0], 1'b0};
                    end else begin
                        cs_n_r <= 1'b1;
                        busy   <= 1'b0;
                    end
                end else begin
                    mosi_r   <= tx_shift[15];
                    tx_shift <= {tx_shift[14:0], 1'b0};
                    bit_cnt  <= bit_cnt - 4'd1;
                end
            end else begin
                // CPHA=1: sample MISO, then check done
                // Use direct expression since NBA for rx_shift isn't visible yet
                if (bit_cnt == 4'h0) begin
                    if (!rx_full) begin
                        rx_mem[rx_widx] <= {rx_shift[14:0], miso_in};
                        rx_wptr         <= rx_wptr + 1;
                    end
                    if (!tx_empty) begin
                        bit_cnt  <= dss;
                        tx_rptr  <= tx_rptr + 1;
                        rx_shift <= 16'h0;
                        tx_shift <= tx_load;
                    end else begin
                        cs_n_r <= 1'b1;
                        busy   <= 1'b0;
                    end
                end else begin
                    rx_shift <= {rx_shift[14:0], miso_in};
                    bit_cnt  <= bit_cnt - 4'd1;
                end
            end
            half <= 1'b0;
        end
    end
end

// ---------------------------------------------------------------------------
// AHB write handler

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cr0     <= 16'h0;
        cr1     <= 4'h0;
        cpsr    <= 8'h0;
        ifls    <= 6'b010_010;  // reset: TX and RX thresholds at 1/2
        imsc    <= 4'h0;
        dmacr   <= 2'h0;
        tx_wptr <= '0;
    end else if (active_r && hwrite_r) begin
        case (reg_addr_r)
            ADDR_CR0:   cr0   <= hwdata[15:0];
            ADDR_CR1:   cr1   <= hwdata[3:0];
            ADDR_DR: begin
                if (!tx_full) begin
                    tx_mem[tx_widx] <= hwdata[15:0];
                    tx_wptr         <= tx_wptr + 1;
                end
            end
            ADDR_CPSR:  cpsr  <= hwdata[7:0];
            ADDR_IFLS:  ifls  <= hwdata[5:0];
            ADDR_IMSC:  imsc  <= hwdata[3:0];
            ADDR_ICR:   ;     // level IRQs auto-clear (RORRIS/RTRIS clear added later)
            ADDR_DMACR: dmacr <= hwdata[1:0];
            default: ;
        endcase
    end
end

// ---------------------------------------------------------------------------
// AHB read — RX FIFO dequeue on DR read

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        rx_rptr <= '0;
    else if (active_r && !hwrite_r && reg_addr_r == ADDR_DR && !rx_empty)
        rx_rptr <= rx_rptr + 1;
end

// ---------------------------------------------------------------------------
// Status and interrupt

wire [31:0] sspsr = {27'h0,
                     busy,       // [4] BSY
                     rx_full,    // [3] RFF
                     !rx_empty,  // [2] RNE
                     !tx_full,   // [1] TNF
                     tx_empty};  // [0] TFE

wire [3:0] ris = {tx_level <= tx_thresh,    // [3] TXRIS — TX at or below threshold
                  rx_level >= rx_thresh,    // [2] RXRIS — RX at or above threshold
                  1'b0,                     // [1] RTRIS (not yet implemented)
                  1'b0};                    // [0] RORRIS (not yet implemented)
wire [3:0] mis = ris & imsc;

// ---------------------------------------------------------------------------
// AHB read data (combinational)

assign hrdata = (reg_addr_r == ADDR_CR0)   ? {16'h0, cr0}              :
                (reg_addr_r == ADDR_CR1)   ? {28'h0, cr1}              :
                (reg_addr_r == ADDR_DR)    ? {16'h0, rx_mem[rx_ridx]}  :
                (reg_addr_r == ADDR_SR)    ? sspsr                      :
                (reg_addr_r == ADDR_CPSR)  ? {24'h0, cpsr}              :
                (reg_addr_r == ADDR_IFLS)  ? {26'h0, ifls}              :
                (reg_addr_r == ADDR_IMSC)  ? {28'h0, imsc}              :
                (reg_addr_r == ADDR_RIS)   ? {28'h0, ris}               :
                (reg_addr_r == ADDR_MIS)   ? {28'h0, mis}               :
                (reg_addr_r == ADDR_DMACR) ? {30'h0, dmacr}             :
                                             32'h0;

assign hready = 1'b1;
assign hresp  = 1'b0;

// ---------------------------------------------------------------------------
// Output assignments

assign spi_sclk = sck_r;
assign spi_mosi = mosi_r;
assign spi_cs_n = cs_n_r;
assign spi_irq  = |mis;

endmodule
