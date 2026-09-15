// Manual ps_bd wrapper — replaces Vivado's auto-generated ps_bd_wrapper.v.
//
// Vivado 2025.2 on some Linux distros leaks /etc/os-release content (VERSION_ID,
// VERSION_CODENAME) into generated Verilog file headers without comment markers,
// causing "syntax error near '='" during synthesis.  This clean wrapper avoids
// that bug entirely.
//
// Port names MUST match the BD external port names in ps_bd (created by TCL):
//   pl_clk0_0    — FCLK0 (configured 100 MHz by PS configuration)
//   pl_resetn0_0 — active-low PL reset from PS

`timescale 1 ps / 1 ps
`default_nettype none

module ps_bd_wrapper (
    output wire pl_clk0_0,
    output wire pl_resetn0_0
);

ps_bd ps_bd_i (
    .pl_clk0_0    (pl_clk0_0),
    .pl_resetn0_0 (pl_resetn0_0)
);

endmodule
