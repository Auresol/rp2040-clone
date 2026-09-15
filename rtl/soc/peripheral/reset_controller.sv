// reset_controller.sv — Per-peripheral reset control with multiple reset sources.
//
// Base address: caller-defined (decoder handles base; offsets below are relative).
//
// Reset sources (active-high pulses, priority high → low):
//   1. POR (power-on reset): resets everything including this controller's logic
//   2. Watchdog timeout:     resets CPU + re-asserts all peripheral resets
//   3. Software chip reset:  same effect as watchdog (CPU writes CHIP_RESET[0]=1)
//
// Register map (byte offset from base):
//   0x00  RESET       [7:0]  per-peripheral reset control (read/write)
//                              1 = held in reset, 0 = released (running)
//                              reset value: 0x00 (FPGA default, all released)
//                              TODO: change to 0xFF for ASIC boot sequence
//   0x04  RESET_DONE  [7:0]  per-peripheral ready status (read-only)
//                              1 = peripheral running, 0 = in reset
//                              currently mirrors ~RESET (combinational inverse)
//                              TODO: add peripheral-ready handshake for ASIC
//   0x08  REASON      [2:0]  reset reason flags (read, write-1-to-clear)
//                              [0] POR     — power-on reset occurred
//                              [1] WDOG    — watchdog timeout occurred
//                              [2] SW      — software chip reset occurred
//                              bits are sticky: accumulate across reset events
//   0x0C  CHIP_RESET  [0]    software chip reset trigger (write-only, reads as 0)
//                              write 1 = full chip reset (CPU + all peripherals)
//                              self-clearing: chip_reset_req pulses for one cycle
//
// Outputs:
//   cpu_rst_n     — active-low CPU reset, asserted on any chip reset, auto-releases
//                   after one cycle (CPU restarts from reset vector)
//   periph_rst_n  — active-low per-peripheral resets, directly driven by ~RESET register
//
// Not implemented (RP2040 differences):
//   WDSEL           — RP2040 selects which peripherals watchdog resets; we reset all
//   PSM (Power State Machine) — RP2040 has sequenced power-up/down; we use simple reg
//   RESET_DONE handshake — should wait for peripheral ready signal, not just ~RESET
//
// Known limitations:
//   - CPU auto-releases from reset after 1 cycle (no firmware-controlled hold)
//   - RESET defaults to 0x00 (FPGA convenience); ASIC should default to 0xFF
//   - RESET_DONE is just ~RESET (no real ready handshake from peripherals)
//   - No reset sequencing: all peripherals release simultaneously
//   - Watchdog and software reset have equal priority (last one wins in same cycle)
//
// AHB pipeline: address phase registers htrans/hwrite/haddr; data phase captures
// hwdata for writes and returns hrdata combinationally for reads.

`default_nettype none

module reset_controller (
    input  wire        clk,
    input  wire        por_n,       // power-on reset (active low, from pin)

    // AHB-Lite slave port
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] haddr,
    input  wire        hwrite,
    input  wire [1:0]  htrans,
    input  wire [2:0]  hsize,
    input  wire [31:0] hwdata,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [31:0] hrdata,
    output wire        hready,
    output wire        hresp,

    // Reset sources
    input  wire        wdog_reset,  // watchdog timeout pulse

    // Reset outputs
    output wire [1:0]  cpu_rst_n,         // per-core CPU reset (active low)
    output wire [7:0]  periph_rst_n       // per-peripheral resets (active low)
);

// ---------------------------------------------------------------------------
// Internal chip-wide reset (POR or watchdog or software)
// This resets the controller's registers but NOT the controller's logic itself
// (only POR does that via por_n).

reg chip_reset_req;
wire chip_rst = !por_n || wdog_reset || chip_reset_req;

// ---------------------------------------------------------------------------
// AHB pipeline

wire active = htrans[1];
reg  active_r, hwrite_r;
reg  [4:2] reg_addr_r;

always @(posedge clk or negedge por_n) begin
    if (!por_n) begin
        active_r   <= 1'b0;
        hwrite_r   <= 1'b0;
        reg_addr_r <= 3'b000;
    end else begin
        active_r   <= active;
        hwrite_r   <= hwrite;
        reg_addr_r <= haddr[4:2];
    end
end

localparam [2:0] ADDR_RESET      = 3'd0,  // 0x00
                 ADDR_RESET_DONE = 3'd1,  // 0x04
                 ADDR_REASON     = 3'd2,  // 0x08
                 ADDR_CHIP_RESET = 3'd3,  // 0x0C
                 ADDR_CPU_RESET  = 3'd4;  // 0x10 — per-core reset [1:0]

// ---------------------------------------------------------------------------
// Registers

reg [7:0] reset_reg;
reg [2:0] reason;

wire wr = active_r && hwrite_r;

always @(posedge clk or negedge por_n) begin
    if (!por_n) begin
        reset_reg      <= 8'h00;    // all peripherals released (FPGA default)
                                    // TODO: change to 8'hFF for ASIC boot sequence
        reason         <= 3'b001;   // POR reason set
        chip_reset_req <= 1'b0;
    end else begin
        chip_reset_req <= 1'b0;

        // Watchdog or software chip reset: re-assert all peripheral resets
        if (wdog_reset) begin
            reset_reg <= 8'hFF;
            reason[1] <= 1'b1;
        end

        if (chip_reset_req) begin
            reset_reg <= 8'hFF;
            reason[2] <= 1'b1;
        end

        // Register writes (lower priority than reset events above,
        // but in practice they never collide — CPU is being reset)
        if (wr) begin
            case (reg_addr_r)
                ADDR_RESET:
                    reset_reg <= hwdata[7:0];
                ADDR_REASON:
                    reason <= reason & ~hwdata[2:0];
                ADDR_CHIP_RESET: begin
                    if (hwdata[0])
                        chip_reset_req <= 1'b1;
                end
                default: ;
            endcase
        end
    end
end

// ---------------------------------------------------------------------------
// Reset outputs

// Per-core CPU reset register.
// Core 0: auto-releases after chip reset (starts running).
// Core 1: held in reset until core 0 explicitly releases it.
reg [1:0] cpu_rst_r;
always @(posedge clk or negedge por_n) begin
    if (!por_n)
        cpu_rst_r <= 2'b11;         // both cores in reset on POR
    else if (wdog_reset || chip_reset_req)
        cpu_rst_r <= 2'b11;         // both cores in reset on chip reset
    else begin
        cpu_rst_r[0] <= 1'b0;      // core 0 auto-releases after 1 cycle
        // core 1 stays in reset until firmware writes CPU_RESET register
        if (wr && reg_addr_r == ADDR_CPU_RESET)
            cpu_rst_r <= hwdata[1:0];
    end
end

assign cpu_rst_n = ~cpu_rst_r;
assign periph_rst_n = ~reset_reg;

// ---------------------------------------------------------------------------
// AHB read

assign hrdata = (reg_addr_r == ADDR_RESET)      ? {24'h0, reset_reg}      :
                (reg_addr_r == ADDR_RESET_DONE)  ? {24'h0, ~reset_reg}     :
                (reg_addr_r == ADDR_REASON)      ? {29'h0, reason}         :
                (reg_addr_r == ADDR_CHIP_RESET)  ? 32'h0                   :
                (reg_addr_r == ADDR_CPU_RESET)   ? {30'h0, cpu_rst_r}      :
                                                   32'h0;

assign hready = 1'b1;
assign hresp  = 1'b0;

endmodule
