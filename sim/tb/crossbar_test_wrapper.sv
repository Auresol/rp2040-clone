// crossbar_test_wrapper.sv — wraps either crossbar with 2 masters + 3 slaves
//
// Topology:
//   Master 0 (TB driven) ──┐
//                           ├── Crossbar ──┬── Slave 0: SRAM A (256 words @ 0x0000_0000)
//   Master 1 (TB driven) ──┘               ├── Slave 1: SRAM B (256 words @ 0x1000_0000)
//                                          └── Slave 2: SRAM C (256 words @ 0x2000_0000)
//
// Each slave is a 1 KB SRAM (256 × 32-bit) with 1-cycle AHB-Lite interface.
// A separate testbench memory port allows seeding/inspecting all three SRAMs.
//
// Select crossbar implementation via USE_RP2040 parameter:
//   0 = ahbl_crossbar_strict (libfpga, fixed priority)
//   1 = ahbl_crossbar_rp2040 (priority + round-robin)

`default_nettype none

module crossbar_test_wrapper #(
    parameter USE_RP2040 = 1
) (
    input  wire        clk,
    input  wire        rst_n,

    // Master 0 AHB-Lite interface
    input  wire [31:0] m0_haddr,
    input  wire        m0_hwrite,
    input  wire [1:0]  m0_htrans,
    input  wire [2:0]  m0_hsize,
    input  wire [31:0] m0_hwdata,
    output wire [31:0] m0_hrdata,
    output wire        m0_hready,
    output wire        m0_hresp,

    // Master 1 AHB-Lite interface
    input  wire [31:0] m1_haddr,
    input  wire        m1_hwrite,
    input  wire [1:0]  m1_htrans,
    input  wire [2:0]  m1_hsize,
    input  wire [31:0] m1_hwdata,
    output wire [31:0] m1_hrdata,
    output wire        m1_hready,
    output wire        m1_hresp,

    // Priority (only used by rp2040 crossbar, ignored by strict)
    input  wire [1:0]  master_priority,  // [0]=M0 pri, [1]=M1 pri (1-bit each)

    // Direct memory access port for testbench inspection
    input  wire [1:0]  mem_sel,      // 0=SRAM_A, 1=SRAM_B, 2=SRAM_C
    input  wire [7:0]  mem_addr,     // word address (0–255)
    input  wire        mem_we,
    input  wire [31:0] mem_wdata,
    output reg  [31:0] mem_rdata
);

    localparam N_MASTERS = 2;
    localparam N_SLAVES  = 3;

    // Address map:
    //   Slave 0: 0x0000_0000, mask 0xF000_0000 (matches 0x0xxx_xxxx)
    //   Slave 1: 0x1000_0000, mask 0xF000_0000 (matches 0x1xxx_xxxx)
    //   Slave 2: 0x2000_0000, mask 0xF000_0000 (matches 0x2xxx_xxxx)
    localparam [N_SLAVES*32-1:0] ADDR_MAP  = {32'h2000_0000, 32'h1000_0000, 32'h0000_0000};
    localparam [N_SLAVES*32-1:0] ADDR_MASK = {32'hF000_0000, 32'hF000_0000, 32'hF000_0000};

    // All masters can access all slaves
    localparam [N_MASTERS*N_SLAVES-1:0] CONN_MATRIX   = {N_MASTERS*N_SLAVES{1'b1}};
    localparam [N_SLAVES*N_MASTERS-1:0] CONN_MATRIX_T = {N_SLAVES*N_MASTERS{1'b1}};

    // ----------------------------------------------------------------
    // Pack master signals into crossbar buses
    // ----------------------------------------------------------------

    wire [N_MASTERS-1:0]    src_hready_resp;
    wire [N_MASTERS-1:0]    src_hresp;
    wire [N_MASTERS*32-1:0] src_haddr    = {m1_haddr,  m0_haddr};
    wire [N_MASTERS-1:0]    src_hwrite   = {m1_hwrite, m0_hwrite};
    wire [N_MASTERS*2-1:0]  src_htrans   = {m1_htrans, m0_htrans};
    wire [N_MASTERS*3-1:0]  src_hsize    = {m1_hsize,  m0_hsize};
    wire [N_MASTERS*3-1:0]  src_hburst   = 6'b0;
    wire [N_MASTERS*4-1:0]  src_hprot    = 8'b0;
    wire [N_MASTERS-1:0]    src_hmastlock = 2'b0;
    wire [N_MASTERS*32-1:0] src_hwdata   = {m1_hwdata, m0_hwdata};
    wire [N_MASTERS*32-1:0] src_hrdata;

    assign m0_hrdata = src_hrdata[31:0];
    assign m1_hrdata = src_hrdata[63:32];
    assign m0_hready = src_hready_resp[0];
    assign m1_hready = src_hready_resp[1];
    assign m0_hresp  = src_hresp[0];
    assign m1_hresp  = src_hresp[1];

    // ----------------------------------------------------------------
    // Slave-side crossbar signals
    // ----------------------------------------------------------------

    wire [N_SLAVES-1:0]     dst_hready;
    wire [N_SLAVES-1:0]     dst_hready_resp;
    wire [N_SLAVES-1:0]     dst_hresp;
    wire [N_SLAVES*32-1:0]  dst_haddr;
    wire [N_SLAVES-1:0]     dst_hwrite;
    wire [N_SLAVES*2-1:0]   dst_htrans;
    wire [N_SLAVES*3-1:0]   dst_hsize;
    wire [N_SLAVES*3-1:0]   dst_hburst;
    wire [N_SLAVES*4-1:0]   dst_hprot;
    wire [N_SLAVES-1:0]     dst_hmastlock;
    wire [N_SLAVES*32-1:0]  dst_hwdata;
    wire [N_SLAVES*32-1:0]  dst_hrdata;

    // ----------------------------------------------------------------
    // Crossbar instantiation (parameterised choice)
    // ----------------------------------------------------------------

    generate
    if (USE_RP2040) begin : gen_rp2040
        ahbl_crossbar_rp2040 #(
            .N_MASTERS    (N_MASTERS),
            .N_SLAVES     (N_SLAVES),
            .ADDR_MAP     (ADDR_MAP),
            .ADDR_MASK    (ADDR_MASK),
            .CONN_MATRIX  (CONN_MATRIX),
            .CONN_MATRIX_T(CONN_MATRIX_T)
        ) u_xbar (
            .clk             (clk),
            .rst_n           (rst_n),
            .master_priority (master_priority),
            .src_hready_resp (src_hready_resp),
            .src_hresp       (src_hresp),
            .src_haddr       (src_haddr),
            .src_hwrite      (src_hwrite),
            .src_htrans      (src_htrans),
            .src_hsize       (src_hsize),
            .src_hburst      (src_hburst),
            .src_hprot       (src_hprot),
            .src_hmastlock   (src_hmastlock),
            .src_hwdata      (src_hwdata),
            .src_hrdata      (src_hrdata),
            .dst_hready      (dst_hready),
            .dst_hready_resp (dst_hready_resp),
            .dst_hresp       (dst_hresp),
            .dst_haddr       (dst_haddr),
            .dst_hwrite      (dst_hwrite),
            .dst_htrans      (dst_htrans),
            .dst_hsize       (dst_hsize),
            .dst_hburst      (dst_hburst),
            .dst_hprot       (dst_hprot),
            .dst_hmastlock   (dst_hmastlock),
            .dst_hwdata      (dst_hwdata),
            .dst_hrdata      (dst_hrdata)
        );
    end else begin : gen_strict
        ahbl_crossbar_strict #(
            .N_MASTERS    (N_MASTERS),
            .N_SLAVES     (N_SLAVES),
            .ADDR_MAP     (ADDR_MAP),
            .ADDR_MASK    (ADDR_MASK),
            .CONN_MATRIX  (CONN_MATRIX),
            .CONN_MATRIX_T(CONN_MATRIX_T)
        ) u_xbar (
            .clk             (clk),
            .rst_n           (rst_n),
            .src_hready_resp (src_hready_resp),
            .src_hresp       (src_hresp),
            .src_haddr       (src_haddr),
            .src_hwrite      (src_hwrite),
            .src_htrans      (src_htrans),
            .src_hsize       (src_hsize),
            .src_hburst      (src_hburst),
            .src_hprot       (src_hprot),
            .src_hmastlock   (src_hmastlock),
            .src_hwdata      (src_hwdata),
            .src_hrdata      (src_hrdata),
            .dst_hready      (dst_hready),
            .dst_hready_resp (dst_hready_resp),
            .dst_hresp       (dst_hresp),
            .dst_haddr       (dst_haddr),
            .dst_hwrite      (dst_hwrite),
            .dst_htrans      (dst_htrans),
            .dst_hsize       (dst_hsize),
            .dst_hburst      (dst_hburst),
            .dst_hprot       (dst_hprot),
            .dst_hmastlock   (dst_hmastlock),
            .dst_hwdata      (dst_hwdata),
            .dst_hrdata      (dst_hrdata)
        );
    end
    endgenerate

    // ----------------------------------------------------------------
    // Slave SRAM banks (3 × 256 words, 1-cycle AHB-Lite)
    // ----------------------------------------------------------------

    genvar s;
    generate
    for (s = 0; s < N_SLAVES; s = s + 1) begin : gen_sram

        reg [31:0] mem [0:255];

        // AHB pipeline registers
        wire       active = dst_htrans[s*2 + 1];
        reg        active_r;
        reg        hwrite_r;
        reg  [7:0] word_addr_r;

        always @(posedge clk) begin
            if (dst_hready[s]) begin
                active_r    <= active;
                hwrite_r    <= dst_hwrite[s];
                word_addr_r <= dst_haddr[s*32 + 9 : s*32 + 2];
            end
        end

        // Write (data phase)
        always @(posedge clk) begin
            if (active_r && hwrite_r)
                mem[word_addr_r] = dst_hwdata[s*32 +: 32];  // write-first
        end

        // Read (data phase)
        assign dst_hrdata[s*32 +: 32] = mem[word_addr_r];
        assign dst_hready_resp[s]     = 1'b1;
        assign dst_hresp[s]           = 1'b0;

    end
    endgenerate

    // ----------------------------------------------------------------
    // Testbench direct memory port
    // ----------------------------------------------------------------

    // Write
    always @(posedge clk) begin
        if (mem_we) begin
            case (mem_sel)
                2'd0: gen_sram[0].mem[mem_addr] = mem_wdata;
                2'd1: gen_sram[1].mem[mem_addr] = mem_wdata;
                2'd2: gen_sram[2].mem[mem_addr] = mem_wdata;
                default: ;
            endcase
        end
    end

    // Read
    always @(*) begin
        case (mem_sel)
            2'd0: mem_rdata = gen_sram[0].mem[mem_addr];
            2'd1: mem_rdata = gen_sram[1].mem[mem_addr];
            2'd2: mem_rdata = gen_sram[2].mem[mem_addr];
            default: mem_rdata = 32'hDEAD_BEEF;
        endcase
    end

endmodule
