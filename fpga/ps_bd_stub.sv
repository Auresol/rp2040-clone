// Synthesis black-box stub for ps_bd block design.
// Provides port declarations so synthesis can elaborate ps_bd_wrapper.
// The actual PS hard block is mapped by Vivado during implementation
// when it processes the BD file (synth_checkpoint_mode None).

`timescale 1 ps / 1 ps
`default_nettype none

(* black_box *)
module ps_bd (
    output wire pl_clk0_0,
    output wire pl_resetn0_0
);
endmodule
