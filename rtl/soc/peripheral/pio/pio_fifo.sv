// pio_fifo.sv — PIO synchronous FIFO
//
// Internally 8 entries deep (3-bit ptr, 4-bit cnt).
// fjoin=0: effective depth 4 (RP2040 default per-direction FIFO)
// fjoin=1: effective depth 8 (joined mode)
//
// push is ignored when full; pop is ignored when empty.

`default_nettype none

module pio_fifo (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        fjoin,      // 0=4-deep threshold, 1=8-deep threshold
    input  wire        push,
    input  wire [31:0] wdata,
    output wire        full,
    input  wire        pop,
    output wire [31:0] rdata,
    output wire        empty,
    output wire [3:0]  level       // 0..8
);

// Storage
reg [31:0] mem [0:7];

// Pointers and count (extra bit on ptrs for full/empty disambiguation not needed
// because we track cnt explicitly)
reg [2:0] wptr;
reg [2:0] rptr;
reg [3:0] cnt;

wire do_push = push && !full;
wire do_pop  = pop  && !empty;

assign full  = (cnt >= (fjoin ? 4'd8 : 4'd4));
assign empty = (cnt == 4'd0);
assign level = cnt;
assign rdata = mem[rptr];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wptr <= 3'd0;
        rptr <= 3'd0;
        cnt  <= 4'd0;
    end else begin
        if (do_push) begin
            mem[wptr] <= wdata;
            wptr      <= wptr + 3'd1;
        end
        if (do_pop) begin
            rptr <= rptr + 3'd1;
        end
        case ({do_push, do_pop})
            2'b10:   cnt <= cnt + 4'd1;
            2'b01:   cnt <= cnt - 4'd1;
            default: cnt <= cnt;
        endcase
    end
end

endmodule
