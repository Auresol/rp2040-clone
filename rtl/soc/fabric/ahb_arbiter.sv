// 2-master, 1-slave AHB-Lite arbiter.
//
// Arbitration policy:
//   - Only one master requesting: that master wins immediately.
//   - Both masters requesting (contested): round-robin — each master gets
//     one transaction, then the other gets a turn.
//   - Back-to-back: allowed only when the other master is NOT also requesting.
//     The moment the other master starts requesting, the current master gives
//     up the bus after completing its current transaction.
//
// This ensures neither master can starve the other.  M0 wins the very first
// contested cycle after reset (last_winner initialises to M1), giving Core 0
// a natural "first mover" advantage for single-core workloads.
//
// Non-granted master sees hready=0 (stalled). AHB spec requires the master
// to hold its address-phase signals stable while stalled, so when it finally
// gets the grant its address is still live and forwarded to the slave.

`default_nettype none

module ahb_arbiter (
    input  wire        clk,
    input  wire        rst_n,

    // Master 0 (wins first contested cycle after reset)
    input  wire [31:0] m0_haddr,
    input  wire        m0_hwrite,
    input  wire [1:0]  m0_htrans,
    input  wire [2:0]  m0_hsize,
    input  wire [2:0]  m0_hburst,
    input  wire [3:0]  m0_hprot,
    input  wire        m0_hmastlock,
    input  wire [7:0]  m0_hmaster,
    input  wire [31:0] m0_hwdata,
    output wire [31:0] m0_hrdata,
    output wire        m0_hready,
    output wire        m0_hresp,

    // Master 1
    input  wire [31:0] m1_haddr,
    input  wire        m1_hwrite,
    input  wire [1:0]  m1_htrans,
    input  wire [2:0]  m1_hsize,
    input  wire [2:0]  m1_hburst,
    input  wire [3:0]  m1_hprot,
    input  wire        m1_hmastlock,
    input  wire [7:0]  m1_hmaster,
    input  wire [31:0] m1_hwdata,
    output wire [31:0] m1_hrdata,
    output wire        m1_hready,
    output wire        m1_hresp,

    // Slave port (driven to the downstream slave)
    output wire [31:0] s_haddr,
    output wire        s_hwrite,
    output wire [1:0]  s_htrans,
    output wire [2:0]  s_hsize,
    output wire [2:0]  s_hburst,
    output wire [3:0]  s_hprot,
    output wire        s_hmastlock,
    output wire [7:0]  s_hmaster,
    output wire [31:0] s_hwdata,
    input  wire [31:0] s_hrdata,
    input  wire        s_hready,
    input  wire        s_hresp
);

wire m0_req = m0_htrans[1];  // NONSEQ or SEQ = real transaction
wire m1_req = m1_htrans[1];

// Registered state
reg grant;        // 0 = M0 holds bus, 1 = M1 holds bus
reg busy;         // 1 = address phase sent, data phase not yet complete
reg last_winner;  // who won the last contested arbitration (0=M0, 1=M1)
                  // initialised to 1 so M0 wins the very first contested cycle

// Both masters requesting at the same time.
wire contested = m0_req & m1_req;

// Combinational grant (who grant the privilede):
//   - When busy: hold the current registered grant (pipeline must stay stable).
//   - When idle, only M0 requesting: M0 wins.
//   - When idle, only M1 requesting: M1 wins.
//   - When idle, both requesting: give the bus to the other master (round-robin).
wire arb_grant = busy       ? grant
               : contested  ? ~last_winner
               : m1_req     ? 1'b1
               : 1'b0;

// Current master's next-cycle request (used for back-to-back detection).
wire cur_req = arb_grant ? m1_req : m0_req;

// Is the non-granted master also requesting?
// If so, the current master must yield after this transaction (no back-to-back).
wire other_waiting = arb_grant ? m0_req : m1_req;

// Back-to-back is allowed only when there is no contention.
wire allow_bbtb = cur_req && !other_waiting;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        grant       <= 1'b0;
        busy        <= 1'b0;
        last_winner <= 1'b1;  // M0 wins first contested cycle (~1 = 0)
    end else begin
        grant <= arb_grant;

        // Record the outcome of any contested arbitration decision so that
        // the NEXT contested cycle goes to the other master.
        // Update on: (a) a new contested idle grant, or
        //            (b) end of a transaction while the other master is waiting.
        if ((!busy && contested) ||
            (busy && s_hready && other_waiting))
            last_winner <= arb_grant;

        if (busy) begin
            if (s_hready)
                // Data phase done.  Keep the bus only if current master has
                // more work AND the other master is not waiting.
                busy <= allow_bbtb;
        end else begin
            // Bus idle — go busy as soon as any master requests.
            busy <= m0_req | m1_req;
        end
    end
end

// Mux address-phase and data-phase signals from the granted master to slave.
assign s_haddr    = arb_grant ? m1_haddr    : m0_haddr;
assign s_hwrite   = arb_grant ? m1_hwrite   : m0_hwrite;
assign s_htrans   = arb_grant ? m1_htrans   : m0_htrans;
assign s_hsize    = arb_grant ? m1_hsize    : m0_hsize;
assign s_hburst   = arb_grant ? m1_hburst   : m0_hburst;
assign s_hprot    = arb_grant ? m1_hprot    : m0_hprot;
assign s_hmastlock = arb_grant ? m1_hmastlock : m0_hmastlock;
assign s_hmaster  = arb_grant ? m1_hmaster  : m0_hmaster;
assign s_hwdata   = arb_grant ? m1_hwdata   : m0_hwdata;

// Slave response goes to both masters; only the granted master acts on it
// (the other is stalled by hready=0).
assign m0_hrdata = s_hrdata;
assign m1_hrdata = s_hrdata;
assign m0_hresp  = s_hresp;
assign m1_hresp  = s_hresp;

// Granted master sees the slave's hready. Non-granted master is stalled.
assign m0_hready = (arb_grant == 1'b0) ? s_hready : 1'b0;
assign m1_hready = (arb_grant == 1'b1) ? s_hready : 1'b0;

endmodule
