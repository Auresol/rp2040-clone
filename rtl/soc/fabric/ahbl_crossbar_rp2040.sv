// AHB-Lite NxM Crossbar — RP2040-style Priority + Round-Robin
//
// Topology: N splitters (1 per master) × M arbiters (1 per slave)
// Arbitration per slave:
//   1. Highest priority level among requesters wins
//   2. Same priority → round-robin (rotate after each grant)
// Priority levels are runtime-configurable via master_priority input.
//
// Reuses ahbl_splitter + onehot_mux from libfpga for the address-decode
// and data-phase muxing. Only the arbiter is custom.

module ahbl_crossbar_rp2040 #(
    parameter N_MASTERS     = 4,
    parameter N_SLAVES      = 10,
    parameter W_ADDR        = 32,
    parameter W_DATA        = 32,
    parameter N_PRIORITIES  = 2,   // number of priority levels (RP2040 uses 2)

    parameter [N_SLAVES*W_ADDR-1:0] ADDR_MAP  = '0,
    parameter [N_SLAVES*W_ADDR-1:0] ADDR_MASK = '0,

    parameter [N_MASTERS*N_SLAVES-1:0] CONN_MATRIX = {N_MASTERS*N_SLAVES{1'b1}},
    parameter [N_SLAVES*N_MASTERS-1:0] CONN_MATRIX_T = {N_SLAVES*N_MASTERS{1'b1}},

    parameter W_PRIORITY = $clog2(N_PRIORITIES)  // do not override
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Per-master priority level (runtime configurable, from BUS_PRIORITY register)
    // 0 = lowest, N_PRIORITIES-1 = highest
    input  logic [N_MASTERS*W_PRIORITY-1:0] master_priority,

    // Master ports
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

    // Slave ports
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

    // ================================================================
    // Crossbar interconnect wires: splitter[i] <-> arbiter[j]
    // ================================================================

    wire              xbar_hready      [0:N_MASTERS-1][0:N_SLAVES-1];
    wire              xbar_hready_resp [0:N_MASTERS-1][0:N_SLAVES-1];
    wire              xbar_hresp       [0:N_MASTERS-1][0:N_SLAVES-1];
    wire [W_ADDR-1:0] xbar_haddr      [0:N_MASTERS-1][0:N_SLAVES-1];
    wire              xbar_hwrite     [0:N_MASTERS-1][0:N_SLAVES-1];
    wire [1:0]        xbar_htrans     [0:N_MASTERS-1][0:N_SLAVES-1];
    wire [2:0]        xbar_hsize      [0:N_MASTERS-1][0:N_SLAVES-1];
    wire [2:0]        xbar_hburst     [0:N_MASTERS-1][0:N_SLAVES-1];
    wire [3:0]        xbar_hprot      [0:N_MASTERS-1][0:N_SLAVES-1];
    wire              xbar_hmastlock  [0:N_MASTERS-1][0:N_SLAVES-1];
    wire [W_DATA-1:0] xbar_hwdata     [0:N_MASTERS-1][0:N_SLAVES-1];
    wire [W_DATA-1:0] xbar_hrdata     [0:N_MASTERS-1][0:N_SLAVES-1];

    // ================================================================
    // Splitters (1 per master) — reuse libfpga ahbl_splitter
    // ================================================================

    genvar i, j;
    generate
    for (i = 0; i < N_MASTERS; i = i + 1) begin : gen_splitter

        // Flatten splitter <-> crossbar wires for this master
        wire [N_SLAVES-1:0]         split_hready;
        wire [N_SLAVES-1:0]         split_hready_resp;
        wire [N_SLAVES-1:0]         split_hresp;
        wire [N_SLAVES*W_ADDR-1:0]  split_haddr;
        wire [N_SLAVES-1:0]         split_hwrite;
        wire [N_SLAVES*2-1:0]       split_htrans;
        wire [N_SLAVES*3-1:0]       split_hsize;
        wire [N_SLAVES*3-1:0]       split_hburst;
        wire [N_SLAVES*4-1:0]       split_hprot;
        wire [N_SLAVES-1:0]         split_hmastlock;
        wire [N_SLAVES*W_DATA-1:0]  split_hwdata;
        wire [N_SLAVES*W_DATA-1:0]  split_hrdata;

        for (j = 0; j < N_SLAVES; j = j + 1) begin : gen_split_conn
            if (CONN_MATRIX[i * N_SLAVES + j] && CONN_MATRIX_T[j * N_MASTERS + i]) begin : conn
                assign xbar_hready[i][j]                  = split_hready[j];
                assign xbar_haddr[i][j]                   = split_haddr[W_ADDR * j +: W_ADDR];
                assign xbar_hwrite[i][j]                  = split_hwrite[j];
                assign xbar_htrans[i][j]                  = split_htrans[2 * j +: 2];
                assign xbar_hsize[i][j]                   = split_hsize[3 * j +: 3];
                assign xbar_hburst[i][j]                  = split_hburst[3 * j +: 3];
                assign xbar_hprot[i][j]                   = split_hprot[4 * j +: 4];
                assign xbar_hmastlock[i][j]               = split_hmastlock[j];
                assign xbar_hwdata[i][j]                  = split_hwdata[W_DATA * j +: W_DATA];
                assign split_hready_resp[j]               = xbar_hready_resp[i][j];
                assign split_hresp[j]                     = xbar_hresp[i][j];
                assign split_hrdata[W_DATA * j +: W_DATA] = xbar_hrdata[i][j];
            end else begin : disconn
                assign xbar_hready[i][j]                  = 1'b1;
                assign xbar_haddr[i][j]                   = '0;
                assign xbar_hwrite[i][j]                  = 1'b0;
                assign xbar_htrans[i][j]                  = 2'h0;
                assign xbar_hsize[i][j]                   = 3'h0;
                assign xbar_hburst[i][j]                  = 3'h0;
                assign xbar_hprot[i][j]                   = 4'h0;
                assign xbar_hmastlock[i][j]               = 1'b0;
                assign xbar_hwdata[i][j]                  = '0;
                assign split_hready_resp[j]               = 1'b1;
                assign split_hresp[j]                     = 1'b0;
                assign split_hrdata[W_DATA * j +: W_DATA] = '0;
            end
        end

        ahbl_splitter #(
            .N_PORTS   (N_SLAVES),
            .W_ADDR    (W_ADDR),
            .W_DATA    (W_DATA),
            .ADDR_MAP  (ADDR_MAP),
            .ADDR_MASK (ADDR_MASK),
            .CONN_MASK (CONN_MATRIX[i * N_SLAVES +: N_SLAVES])
        ) u_splitter (
            .clk             (clk),
            .rst_n           (rst_n),
            .src_hready      (src_hready_resp[i]),
            .src_hready_resp (src_hready_resp[i]),
            .src_hresp       (src_hresp[i]),
            .src_haddr       (src_haddr[W_ADDR * i +: W_ADDR]),
            .src_hwrite      (src_hwrite[i]),
            .src_htrans      (src_htrans[2 * i +: 2]),
            .src_hsize       (src_hsize[3 * i +: 3]),
            .src_hburst      (src_hburst[3 * i +: 3]),
            .src_hprot       (src_hprot[4 * i +: 4]),
            .src_hmastlock   (src_hmastlock[i]),
            .src_hwdata      (src_hwdata[W_DATA * i +: W_DATA]),
            .src_hrdata      (src_hrdata[W_DATA * i +: W_DATA]),
            .dst_hready      (split_hready),
            .dst_hready_resp (split_hready_resp),
            .dst_hresp       (split_hresp),
            .dst_haddr       (split_haddr),
            .dst_hwrite      (split_hwrite),
            .dst_htrans      (split_htrans),
            .dst_hsize       (split_hsize),
            .dst_hburst      (split_hburst),
            .dst_hprot       (split_hprot),
            .dst_hmastlock   (split_hmastlock),
            .dst_hwdata      (split_hwdata),
            .dst_hrdata      (split_hrdata)
        );
    end
    endgenerate

    // ================================================================
    // Arbiters (1 per slave) — custom priority + round-robin
    // ================================================================

    generate
    for (j = 0; j < N_SLAVES; j = j + 1) begin : gen_arbiter

        // Flatten arbiter <-> crossbar wires for this slave
        wire [N_MASTERS-1:0]         arb_hready;
        wire [N_MASTERS-1:0]         arb_hready_resp;
        wire [N_MASTERS-1:0]         arb_hresp;
        wire [N_MASTERS*W_ADDR-1:0]  arb_haddr;
        wire [N_MASTERS-1:0]         arb_hwrite;
        wire [N_MASTERS*2-1:0]       arb_htrans;
        wire [N_MASTERS*3-1:0]       arb_hsize;
        wire [N_MASTERS*3-1:0]       arb_hburst;
        wire [N_MASTERS*4-1:0]       arb_hprot;
        wire [N_MASTERS-1:0]         arb_hmastlock;
        wire [N_MASTERS*W_DATA-1:0]  arb_hwdata;
        wire [N_MASTERS*W_DATA-1:0]  arb_hrdata;

        for (i = 0; i < N_MASTERS; i = i + 1) begin : gen_arb_conn
            assign arb_hready[i]                     = xbar_hready[i][j];
            assign arb_haddr[W_ADDR * i +: W_ADDR]   = xbar_haddr[i][j];
            assign arb_hwrite[i]                     = xbar_hwrite[i][j];
            assign arb_htrans[2 * i +: 2]            = xbar_htrans[i][j];
            assign arb_hsize[3 * i +: 3]             = xbar_hsize[i][j];
            assign arb_hburst[3 * i +: 3]            = xbar_hburst[i][j];
            assign arb_hprot[4 * i +: 4]             = xbar_hprot[i][j];
            assign arb_hmastlock[i]                  = xbar_hmastlock[i][j];
            assign arb_hwdata[W_DATA * i +: W_DATA]  = xbar_hwdata[i][j];
            assign xbar_hready_resp[i][j]            = arb_hready_resp[i];
            assign xbar_hresp[i][j]                  = arb_hresp[i];
            assign xbar_hrdata[i][j]                 = arb_hrdata[W_DATA * i +: W_DATA];
        end

        ahbl_arbiter_rr #(
            .N_PORTS      (N_MASTERS),
            .W_ADDR       (W_ADDR),
            .W_DATA       (W_DATA),
            .N_PRIORITIES (N_PRIORITIES),
            .CONN_MASK    (CONN_MATRIX_T[j * N_MASTERS +: N_MASTERS])
        ) u_arbiter (
            .clk              (clk),
            .rst_n            (rst_n),
            .master_priority  (master_priority),
            .src_hready       (arb_hready),
            .src_hready_resp  (arb_hready_resp),
            .src_hresp        (arb_hresp),
            .src_haddr        (arb_haddr),
            .src_hwrite       (arb_hwrite),
            .src_htrans       (arb_htrans),
            .src_hsize        (arb_hsize),
            .src_hburst       (arb_hburst),
            .src_hprot        (arb_hprot),
            .src_hmastlock    (arb_hmastlock),
            .src_hwdata       (arb_hwdata),
            .src_hrdata       (arb_hrdata),
            .dst_hready       (dst_hready[j]),
            .dst_hready_resp  (dst_hready_resp[j]),
            .dst_hresp        (dst_hresp[j]),
            .dst_haddr        (dst_haddr[W_ADDR * j +: W_ADDR]),
            .dst_hwrite       (dst_hwrite[j]),
            .dst_htrans       (dst_htrans[2 * j +: 2]),
            .dst_hsize        (dst_hsize[3 * j +: 3]),
            .dst_hburst       (dst_hburst[3 * j +: 3]),
            .dst_hprot        (dst_hprot[4 * j +: 4]),
            .dst_hmastlock    (dst_hmastlock[j]),
            .dst_hwdata       (dst_hwdata[W_DATA * j +: W_DATA]),
            .dst_hrdata       (dst_hrdata[W_DATA * j +: W_DATA])
        );
    end
    endgenerate

endmodule


// ================================================================
// Priority + Round-Robin AHB-Lite Arbiter
// ================================================================
//
// Per-slave arbiter for N masters competing for 1 slave.
//
// Algorithm:
//   1. Stratify requests by priority level
//   2. Select highest active priority level
//   3. Among requesters at that level, round-robin from last_winner+1
//
// Request buffering: if a master's address phase ends (its HREADY went
// high from a different slave) but this arbiter didn't grant it, the
// address-phase signals are captured into a buffer and replayed later.
// This is required by AHB protocol when splitters drive HREADY.

module ahbl_arbiter_rr #(
    parameter N_PORTS      = 4,
    parameter W_ADDR       = 32,
    parameter W_DATA       = 32,
    parameter N_PRIORITIES = 2,
    parameter [N_PORTS-1:0] CONN_MASK = {N_PORTS{1'b1}},
    parameter W_PRIORITY   = $clog2(N_PRIORITIES)  // do not override
) (
    input  wire                        clk,
    input  wire                        rst_n,

    // Priority level for each master
    input  wire [N_PORTS*W_PRIORITY-1:0] master_priority,

    // From masters
    input  wire [N_PORTS-1:0]          src_hready,
    output wire [N_PORTS-1:0]          src_hready_resp,
    output wire [N_PORTS-1:0]          src_hresp,
    input  wire [N_PORTS*W_ADDR-1:0]   src_haddr,
    input  wire [N_PORTS-1:0]          src_hwrite,
    input  wire [N_PORTS*2-1:0]        src_htrans,
    input  wire [N_PORTS*3-1:0]        src_hsize,
    input  wire [N_PORTS*3-1:0]        src_hburst,
    input  wire [N_PORTS*4-1:0]        src_hprot,
    input  wire [N_PORTS-1:0]          src_hmastlock,
    input  wire [N_PORTS*W_DATA-1:0]   src_hwdata,
    output wire [N_PORTS*W_DATA-1:0]   src_hrdata,

    // To slave
    output wire                        dst_hready,
    input  wire                        dst_hready_resp,
    input  wire                        dst_hresp,
    output wire [W_ADDR-1:0]           dst_haddr,
    output wire                        dst_hwrite,
    output wire [1:0]                  dst_htrans,
    output wire [2:0]                  dst_hsize,
    output wire [2:0]                  dst_hburst,
    output wire [3:0]                  dst_hprot,
    output wire                        dst_hmastlock,
    output wire [W_DATA-1:0]           dst_hwdata,
    input  wire [W_DATA-1:0]           dst_hrdata
);

    integer k;

    // ----------------------------------------------------------------
    // Request buffering (same as libfpga arbiter)
    // ----------------------------------------------------------------
    // "actual" = buffered value if valid, else live port signal

    reg  [N_PORTS-1:0]   buf_valid;
    reg  [W_ADDR-1:0]    buf_haddr     [0:N_PORTS-1];
    reg                   buf_hwrite    [0:N_PORTS-1];
    reg  [1:0]            buf_htrans    [0:N_PORTS-1];
    reg  [2:0]            buf_hsize     [0:N_PORTS-1];
    reg  [2:0]            buf_hburst    [0:N_PORTS-1];
    reg  [3:0]            buf_hprot     [0:N_PORTS-1];
    reg                   buf_hmastlock [0:N_PORTS-1];

    reg  [N_PORTS*W_ADDR-1:0] actual_haddr;
    reg  [N_PORTS-1:0]        actual_hwrite;
    reg  [N_PORTS*2-1:0]      actual_htrans;
    reg  [N_PORTS*3-1:0]      actual_hsize;
    reg  [N_PORTS*3-1:0]      actual_hburst;
    reg  [N_PORTS*4-1:0]      actual_hprot;
    reg  [N_PORTS-1:0]        actual_hmastlock;

    always @(*) begin
        for (k = 0; k < N_PORTS; k = k + 1) begin
            if (buf_valid[k]) begin
                actual_haddr    [k*W_ADDR +: W_ADDR] = buf_haddr[k];
                actual_hwrite   [k]                   = buf_hwrite[k];
                actual_htrans   [k*2 +: 2]            = buf_htrans[k];
                actual_hsize    [k*3 +: 3]            = buf_hsize[k];
                actual_hburst   [k*3 +: 3]            = buf_hburst[k];
                actual_hprot    [k*4 +: 4]            = buf_hprot[k];
                actual_hmastlock[k]                   = buf_hmastlock[k];
            end else begin
                actual_haddr    [k*W_ADDR +: W_ADDR] = src_haddr[k*W_ADDR +: W_ADDR];
                actual_hwrite   [k]                   = src_hwrite[k];
                actual_htrans   [k*2 +: 2]            = src_htrans[k*2 +: 2];
                actual_hsize    [k*3 +: 3]            = src_hsize[k*3 +: 3];
                actual_hburst   [k*3 +: 3]            = src_hburst[k*3 +: 3];
                actual_hprot    [k*4 +: 4]            = src_hprot[k*4 +: 4];
                actual_hmastlock[k]                   = src_hmastlock[k];
            end
        end
    end

    // ----------------------------------------------------------------
    // Address-phase arbitration: priority + round-robin
    // ----------------------------------------------------------------

    // Active requests (HTRANS[1] = NONSEQ or SEQ)
    reg [N_PORTS-1:0] mast_req;
    always @(*) begin
        for (k = 0; k < N_PORTS; k = k + 1)
            mast_req[k] = actual_htrans[k*2 + 1] && CONN_MASK[k];
    end

    // Round-robin state
    reg [$clog2(N_PORTS)-1:0] last_winner;

    // Step 1: Stratify requests by priority level
    reg [N_PORTS-1:0]      req_at_level [0:N_PRIORITIES-1];
    reg [N_PRIORITIES-1:0] level_active;

    always @(*) begin
        for (k = 0; k < N_PRIORITIES; k = k + 1) begin: stratify
            integer m;
            req_at_level[k] = '0;
            for (m = 0; m < N_PORTS; m = m + 1) begin
                if (mast_req[m] && master_priority[m*W_PRIORITY +: W_PRIORITY] == k[W_PRIORITY-1:0])
                    req_at_level[k][m] = 1'b1;
            end
            level_active[k] = |req_at_level[k];
        end
    end

    // Step 2: Find highest active priority level
    reg [N_PORTS-1:0] eligible;
    always @(*) begin: select_level
        integer lv;
        eligible = '0;
        for (lv = N_PRIORITIES - 1; lv >= 0; lv = lv - 1) begin
            if (level_active[lv] && eligible == '0)
                eligible = req_at_level[lv];
        end
    end

    // Step 3: Round-robin among eligible masters
    // Split into "after last_winner" and "at or before last_winner",
    // prefer the "after" group to rotate fairly.

    reg [N_PORTS-1:0] mask_upper;  // bits strictly after last_winner
    always @(*) begin
        for (k = 0; k < N_PORTS; k = k + 1)
            mask_upper[k] = (k[$clog2(N_PORTS)-1:0] > last_winner);
    end

    wire [N_PORTS-1:0] req_upper = eligible & mask_upper;
    wire [N_PORTS-1:0] req_lower = eligible & ~mask_upper;

    // Find-first-set for both halves
    wire [N_PORTS-1:0] grant_upper;
    wire [N_PORTS-1:0] grant_lower;

    onehot_priority #(.W_INPUT(N_PORTS)) u_pri_upper (
        .in  (req_upper),
        .out (grant_upper)
    );

    onehot_priority #(.W_INPUT(N_PORTS)) u_pri_lower (
        .in  (req_lower),
        .out (grant_lower)
    );

    // Prefer upper (wraps around); fall back to lower
    wire [N_PORTS-1:0] mast_gnt_a = |req_upper ? grant_upper : grant_lower;

    // Encode winner index for last_winner update
    reg [$clog2(N_PORTS)-1:0] winner_idx;
    always @(*) begin
        winner_idx = '0;
        for (k = 0; k < N_PORTS; k = k + 1)
            if (mast_gnt_a[k])
                winner_idx = k[$clog2(N_PORTS)-1:0];
    end

    // ----------------------------------------------------------------
    // AHB state machine
    // ----------------------------------------------------------------

    reg [N_PORTS-1:0] mast_gnt_d;  // data-phase grant (registered)

    // Slave sees HREADY from the data-phase master
    assign dst_hready = mast_gnt_d ? |(src_hready & mast_gnt_d) : 1'b1;

    // Buffer write enable: master's address phase ends but it wasn't granted
    wire [N_PORTS-1:0] mast_aphase_ends = mast_req & src_hready;
    wire [N_PORTS-1:0] buf_wen = mast_aphase_ends & ~(mast_gnt_a & {N_PORTS{dst_hready}});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mast_gnt_d  <= '0;
            buf_valid   <= '0;
            last_winner <= '0;
            for (k = 0; k < N_PORTS; k = k + 1) begin
                buf_htrans[k]    <= 2'h0;
                buf_haddr[k]     <= '0;
                buf_hwrite[k]    <= 1'b0;
                buf_hsize[k]     <= 3'h0;
                buf_hburst[k]    <= 3'h0;
                buf_hprot[k]     <= 4'h0;
                buf_hmastlock[k] <= 1'b0;
            end
        end else begin
            if (dst_hready) begin
                mast_gnt_d <= mast_gnt_a;
                buf_valid  <= buf_valid & ~mast_gnt_a;
                // Update round-robin pointer on contested grant
                if (|mast_gnt_a)
                    last_winner <= winner_idx;
            end
            for (k = 0; k < N_PORTS; k = k + 1) begin
                if (buf_wen[k]) begin
                    buf_valid[k]     <= 1'b1;
                    buf_htrans[k]    <= src_htrans   [k*2     +: 2];
                    buf_haddr[k]     <= src_haddr    [k*W_ADDR +: W_ADDR];
                    buf_hwrite[k]    <= src_hwrite   [k];
                    buf_hsize[k]     <= src_hsize    [k*3     +: 3];
                    buf_hburst[k]    <= src_hburst   [k*3     +: 3];
                    buf_hprot[k]     <= src_hprot    [k*4     +: 4];
                    buf_hmastlock[k] <= src_hmastlock[k];
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Data-phase passthrough
    // ----------------------------------------------------------------

    wire [N_PORTS-1:0] mast_in_dphase = buf_valid | mast_gnt_d;

    // Ready: idle masters see ready=1; granted masters see slave's ready
    assign src_hready_resp = ~mast_in_dphase | (mast_gnt_d & {N_PORTS{dst_hready_resp}});
    assign src_hresp       = mast_gnt_d & {N_PORTS{dst_hresp}};
    assign src_hrdata      = {N_PORTS{dst_hrdata}};

    // Data-phase mux (write data from granted master)
    onehot_mux #(.W_INPUT(W_DATA), .N_INPUTS(N_PORTS)) u_mux_hwdata (
        .in  (src_hwdata),
        .sel (mast_gnt_d),
        .out (dst_hwdata)
    );

    // Address-phase muxes (from winning master)
    onehot_mux #(.W_INPUT(W_ADDR), .N_INPUTS(N_PORTS)) u_mux_haddr (
        .in  (actual_haddr),
        .sel (mast_gnt_a),
        .out (dst_haddr)
    );

    onehot_mux #(.W_INPUT(1), .N_INPUTS(N_PORTS)) u_mux_hwrite (
        .in  (actual_hwrite),
        .sel (mast_gnt_a),
        .out (dst_hwrite)
    );

    onehot_mux #(.W_INPUT(2), .N_INPUTS(N_PORTS)) u_mux_htrans (
        .in  (actual_htrans),
        .sel (mast_gnt_a),
        .out (dst_htrans)
    );

    onehot_mux #(.W_INPUT(3), .N_INPUTS(N_PORTS)) u_mux_hsize (
        .in  (actual_hsize),
        .sel (mast_gnt_a),
        .out (dst_hsize)
    );

    onehot_mux #(.W_INPUT(3), .N_INPUTS(N_PORTS)) u_mux_hburst (
        .in  (actual_hburst),
        .sel (mast_gnt_a),
        .out (dst_hburst)
    );

    onehot_mux #(.W_INPUT(4), .N_INPUTS(N_PORTS)) u_mux_hprot (
        .in  (actual_hprot),
        .sel (mast_gnt_a),
        .out (dst_hprot)
    );

    onehot_mux #(.W_INPUT(1), .N_INPUTS(N_PORTS)) u_mux_hmastlock (
        .in  (actual_hmastlock),
        .sel (mast_gnt_a),
        .out (dst_hmastlock)
    );

endmodule
