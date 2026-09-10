// spi.sv — AHB-Lite SPI master peripheral (PL022-compatible subset).
//
// Register map (byte offset from base):
//   0x000  SSPCR0    [15:0]  [15:8]=SCR, [7]=SPH, [6]=SPO, [3:0]=DSS
//   0x004  SSPCR1    [3:0]   [1]=SSE, [0]=LBM
//   0x008  SSPDR     [15:0]  TX/RX data FIFO
//   0x00C  SSPSR     [4:0]   [4]=BSY [3]=RFF [2]=RNE [1]=TNF [0]=TFE
//   0x010  SSPCPSR   [7:0]   prescaler (even, 2–254)
//   0x014  SSPIMSC   [3:0]   interrupt mask
//   0x018  SSPRIS    [3:0]   raw interrupt status
//   0x01C  SSPMIS    [3:0]   masked interrupt status
//   0x020  SSPICR    [1:0]   interrupt clear
//
// SCK = clk / (CPSR * (1 + SCR))
// Frame size: DSS+1 bits (4–16), MSB first.
// CS_N asserted automatically during transfer.

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

    // DMA request (active when RX FIFO non-empty)
    output wire        spi_dreq
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

localparam [3:0] ADDR_CR0  = 4'h0; // 0x000
localparam [3:0] ADDR_CR1  = 4'h1; // 0x004
localparam [3:0] ADDR_DR   = 4'h2; // 0x008
localparam [3:0] ADDR_SR   = 4'h3; // 0x00C
localparam [3:0] ADDR_CPSR = 4'h4; // 0x010
localparam [3:0] ADDR_IMSC = 4'h5; // 0x014
localparam [3:0] ADDR_RIS  = 4'h6; // 0x018
localparam [3:0] ADDR_MIS  = 4'h7; // 0x01C
localparam [3:0] ADDR_ICR  = 4'h8; // 0x020

// ---------------------------------------------------------------------------
// Configuration registers

reg [15:0] cr0;    // [15:8] SCR, [7] CPHA, [6] CPOL, [3:0] DSS
reg [3:0]  cr1;    // [1] SSE (enable), [0] LBM (loopback)
reg [7:0]  cpsr;   // clock prescaler (even, 2-254)
reg [3:0]  imsc;   // interrupt mask

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

assign spi_dreq = !rx_empty;
wire [FIFO_AW-1:0] rx_widx = rx_wptr[FIFO_AW-1:0];
wire [FIFO_AW-1:0] rx_ridx = rx_rptr[FIFO_AW-1:0];

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
        imsc    <= 4'h0;
        tx_wptr <= '0;
    end else if (active_r && hwrite_r) begin
        case (reg_addr_r)
            ADDR_CR0:  cr0  <= hwdata[15:0];
            ADDR_CR1:  cr1  <= hwdata[3:0];
            ADDR_DR: begin
                if (!tx_full) begin
                    tx_mem[tx_widx] <= hwdata[15:0];
                    tx_wptr         <= tx_wptr + 1;
                end
            end
            ADDR_CPSR: cpsr <= hwdata[7:0];
            ADDR_IMSC: imsc <= hwdata[3:0];
            ADDR_ICR:  ;    // level IRQs auto-clear
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

wire [FIFO_AW:0] tx_level = tx_wptr - tx_rptr;
wire [FIFO_AW:0] rx_level = rx_wptr - rx_rptr;

wire [3:0] ris = {tx_level <= (FIFO_DEPTH / 2),   // [3] TXRIS — TX half-empty
                  rx_level >= (FIFO_DEPTH / 2),    // [2] RXRIS — RX half-full
                  1'b0,                             // [1] RTRIS (not implemented)
                  1'b0};                            // [0] RORRIS (not implemented)
wire [3:0] mis = ris & imsc;

// ---------------------------------------------------------------------------
// AHB read data (combinational)

assign hrdata = (reg_addr_r == ADDR_CR0)  ? {16'h0, cr0}              :
                (reg_addr_r == ADDR_CR1)  ? {28'h0, cr1}              :
                (reg_addr_r == ADDR_DR)   ? {16'h0, rx_mem[rx_ridx]}  :
                (reg_addr_r == ADDR_SR)   ? sspsr                      :
                (reg_addr_r == ADDR_CPSR) ? {24'h0, cpsr}              :
                (reg_addr_r == ADDR_IMSC) ? {28'h0, imsc}              :
                (reg_addr_r == ADDR_RIS)  ? {28'h0, ris}               :
                (reg_addr_r == ADDR_MIS)  ? {28'h0, mis}               :
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
