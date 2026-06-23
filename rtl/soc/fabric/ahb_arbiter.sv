// 2-master, 1-slave AHB-Lite arbiter.
// Master 0 has fixed priority over Master 1.
//
// Grant is combinational when the bus is idle (avoids a 1-cycle gap when
// switching masters). Once a transaction is in-flight (busy=1), the grant
// is held by the registered value so the address+data pipeline stays stable.
//
// Non-granted master sees hready=0 (stalled). AHB spec requires the master
// to hold its address-phase signals stable while stalled, so when it finally
// gets the grant its address is still live and forwarded to the slave.

`default_nettype none

module ahb_arbiter (
    input  wire        clk,
    input  wire        rst_n,

    // Master 0 (higher priority)
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
reg grant;  // 0 = M0 holds bus, 1 = M1 holds bus
reg busy;   // 1 = address phase sent, data phase not yet complete

// Combinational grant:
//   - When not busy: M0 wins if requesting, else M1 if requesting.
//   - When busy: hold the registered grant so the in-flight transaction
//     isn't interrupted.
wire arb_grant = busy ? grant : (~m0_req & m1_req);

// Requesting signal of whichever master currently has the grant.
// Used to detect back-to-back transactions (master keeps the bus).
wire cur_req = arb_grant ? m1_req : m0_req;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        grant <= 1'b0;
        busy  <= 1'b0;
    end else begin
        grant <= arb_grant;
        if (busy) begin
            if (s_hready)
                // Data phase done. Stay busy only if the current master
                // already has the next address phase on the wire (back-to-back).
                busy <= cur_req;
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
