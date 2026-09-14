// AHB-Lite NxM Crossbar — Strict Priority (libfpga wrapper)
//
// Thin SystemVerilog wrapper around Hazard3's libfpga ahbl_crossbar.
// Arbitration: fixed strict priority (lower master index wins).
// Drop-in for quick bringup; swap to ahbl_crossbar_rp2040 for fairness.

module ahbl_crossbar_strict #(
    parameter N_MASTERS = 4,
    parameter N_SLAVES  = 10,
    parameter W_ADDR    = 32,
    parameter W_DATA    = 32,

    // Packed address map: ADDR_MAP[slave_i] and ADDR_MASK[slave_i]
    // Match when: (haddr ^ ADDR_MAP[i]) & ADDR_MASK[i] == 0
    parameter [N_SLAVES*W_ADDR-1:0] ADDR_MAP  = '0,
    parameter [N_SLAVES*W_ADDR-1:0] ADDR_MASK = '0,

    // Connectivity matrix: CONN[master][slave] = 1 if connected
    parameter [N_MASTERS*N_SLAVES-1:0] CONN_MATRIX = {N_MASTERS*N_SLAVES{1'b1}},
    parameter [N_SLAVES*N_MASTERS-1:0] CONN_MATRIX_T = {N_SLAVES*N_MASTERS{1'b1}}
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Master ports (directly from CPU / DMA)
    output logic [N_MASTERS-1:0]          src_hready_resp,
    output logic [N_MASTERS-1:0]          src_hresp,
    input  logic [N_MASTERS*W_ADDR-1:0]   src_haddr,
    input  logic [N_MASTERS-1:0]          src_hwrite,
    input  logic [N_MASTERS*2-1:0]        src_htrans,
    input  logic [N_MASTERS*3-1:0]        src_hsize,
    input  logic [N_MASTERS*3-1:0]        src_hburst,
    input  logic [N_MASTERS*4-1:0]        src_hprot,
    input  logic [N_MASTERS-1:0]          src_hmastlock,
    input  logic [N_MASTERS*W_DATA-1:0]   src_hwdata,
    output logic [N_MASTERS*W_DATA-1:0]   src_hrdata,

    // Slave ports (directly to SRAM / peripherals)
    output logic [N_SLAVES-1:0]           dst_hready,
    input  logic [N_SLAVES-1:0]           dst_hready_resp,
    input  logic [N_SLAVES-1:0]           dst_hresp,
    output logic [N_SLAVES*W_ADDR-1:0]    dst_haddr,
    output logic [N_SLAVES-1:0]           dst_hwrite,
    output logic [N_SLAVES*2-1:0]         dst_htrans,
    output logic [N_SLAVES*3-1:0]         dst_hsize,
    output logic [N_SLAVES*3-1:0]         dst_hburst,
    output logic [N_SLAVES*4-1:0]         dst_hprot,
    output logic [N_SLAVES-1:0]           dst_hmastlock,
    output logic [N_SLAVES*W_DATA-1:0]    dst_hwdata,
    input  logic [N_SLAVES*W_DATA-1:0]    dst_hrdata
);

    ahbl_crossbar #(
        .N_MASTERS           (N_MASTERS),
        .N_SLAVES            (N_SLAVES),
        .W_ADDR              (W_ADDR),
        .W_DATA              (W_DATA),
        .ADDR_MAP            (ADDR_MAP),
        .ADDR_MASK           (ADDR_MASK),
        .CONN_MATRIX         (CONN_MATRIX),
        .CONN_MATRIX_TRANSPOSE (CONN_MATRIX_T)
    ) u_xbar (
        .clk              (clk),
        .rst_n            (rst_n),

        .src_hready_resp  (src_hready_resp),
        .src_hresp        (src_hresp),
        .src_haddr        (src_haddr),
        .src_hwrite       (src_hwrite),
        .src_htrans       (src_htrans),
        .src_hsize        (src_hsize),
        .src_hburst       (src_hburst),
        .src_hprot        (src_hprot),
        .src_hmastlock    (src_hmastlock),
        .src_hwdata       (src_hwdata),
        .src_hrdata       (src_hrdata),

        .dst_hready       (dst_hready),
        .dst_hready_resp  (dst_hready_resp),
        .dst_hresp        (dst_hresp),
        .dst_haddr        (dst_haddr),
        .dst_hwrite       (dst_hwrite),
        .dst_htrans       (dst_htrans),
        .dst_hsize        (dst_hsize),
        .dst_hburst       (dst_hburst),
        .dst_hprot        (dst_hprot),
        .dst_hmastlock    (dst_hmastlock),
        .dst_hwdata       (dst_hwdata),
        .dst_hrdata       (dst_hrdata)
    );

endmodule
