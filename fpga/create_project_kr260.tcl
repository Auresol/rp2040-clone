# create_project_kr260.tcl — Vivado non-project mode build for KR260
# Clock: PS FCLK0 via block design (100 MHz, set by U-Boot/Linux)
# Usage: vivado -mode batch -source fpga/create_project_kr260.tcl
# Run from repo root: /data/rp2040-clone

set REPO_ROOT [pwd]
set PROJECT_DIR $REPO_ROOT/fpga/vivado_kr260

# Remove stale .Xil temp directory — a partial .Xil left by a crashed run causes
# "Failed to open .../realtime/tmp/genlib.*" errors during synthesis optimization.
file delete -force [file join $REPO_ROOT .Xil]

set FIRMWARE_MEM [expr {[info exists env(FIRMWARE_MEM)] ? $env(FIRMWARE_MEM) : ""}]

# -----------------------------------------------------------------------
# Create in-memory project
create_project -in_memory -part xck26-sfvc784-2LV-c
file mkdir $PROJECT_DIR

# -----------------------------------------------------------------------
# Block design: minimal PS for FCLK0 (100 MHz) and PL reset
# -----------------------------------------------------------------------

create_bd_design -dir $PROJECT_DIR "ps_bd"

set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* zynq_ultra_ps_e_0]
set_property -dict [list \
    CONFIG.PSU__FPGA_PL0_ENABLE                {1}   \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__USE__M_AXI_GP0                 {0}   \
    CONFIG.PSU__USE__M_AXI_GP1                 {0}   \
    CONFIG.PSU__USE__M_AXI_GP2                 {0}   \
] $ps

# Export FCLK0 and PL reset as BD top-level ports.
# External port names will be pl_clk0_0 and pl_resetn0_0.
make_bd_pins_external [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]
make_bd_pins_external [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0]

validate_bd_design
save_bd_design

# Generate synthesis Verilog for the BD (ps_bd.v, ps_bd_wrapper.v).
generate_target {synthesis} [get_files {ps_bd.bd}]

# Vivado 2025.2 bug: /etc/os-release content (VERSION_ID, VERSION_CODENAME etc.)
# leaks into generated Verilog file headers without comment markers, causing
# "syntax error near '='".  Strip bare shell variable assignment lines in-place
# before synthesis reads them — the rest of the generated files is valid Verilog 2001.
proc fix_vivado_verilog {fpath} {
    set f [open $fpath r]
    set lines [split [read $f] "\n"]
    close $f
    set fixed {}
    foreach line $lines {
        # Drop lines that are raw shell variable assignments (NAME=value)
        if {![regexp {^[A-Z_]+=} $line]} {
            lappend fixed $line
        }
    }
    set f [open $fpath w]
    puts -nonewline $f [join $fixed "\n"]
    close $f
}
fix_vivado_verilog $PROJECT_DIR/ps_bd/synth/ps_bd.v
fix_vivado_verilog $PROJECT_DIR/ps_bd/hdl/ps_bd_wrapper.v
puts "=== Fixed Vivado 2025.2 /etc/os-release header corruption in generated Verilog ==="

# ps_bd_wrapper.v is NOT added to the fileset by generate_target — read it explicitly.
# Content is valid Verilog 2001 after the fix above, so no -sv needed.
read_verilog $PROJECT_DIR/ps_bd/hdl/ps_bd_wrapper.v

# -----------------------------------------------------------------------
# RTL sources
read_verilog -sv [glob $REPO_ROOT/rtl/soc/*.sv]
read_verilog -sv [glob $REPO_ROOT/rtl/soc/fabric/*.sv]
read_verilog -sv [glob $REPO_ROOT/rtl/soc/memory/*.sv]
read_verilog -sv [glob $REPO_ROOT/rtl/soc/peripheral/*.sv]
read_verilog -sv [glob $REPO_ROOT/rtl/soc/peripheral/pio/*.sv]

# Hazard3 core (plain Verilog)
read_verilog [glob $REPO_ROOT/rtl/core/hazard3/hdl/*.v]
read_verilog [glob $REPO_ROOT/rtl/core/hazard3/hdl/arith/*.v]

# FPGA wrappers (ps_bd_wrapper is auto-generated, already in fileset from generate_target)
read_verilog -sv $REPO_ROOT/fpga/fpga_top_kr260.sv
read_verilog -sv $REPO_ROOT/fpga/kr260_top.sv

# Constraints
read_xdc $REPO_ROOT/fpga/kr260.xdc

# Include path for Hazard3 .vh headers
set_property include_dirs $REPO_ROOT/rtl/core/hazard3/hdl [current_fileset]

# -----------------------------------------------------------------------
# Synthesis
if {$FIRMWARE_MEM ne ""} {
    puts "=== Firmware init: $FIRMWARE_MEM ==="
    synth_design -top kr260_top -part xck26-sfvc784-2LV-c \
        -include_dirs $REPO_ROOT/rtl/core/hazard3/hdl \
        -verilog_define "SRAM_INIT_FILE=\"$FIRMWARE_MEM\""
} else {
    puts "=== No firmware — SRAM will be uninitialized ==="
    synth_design -top kr260_top -part xck26-sfvc784-2LV-c \
        -include_dirs $REPO_ROOT/rtl/core/hazard3/hdl
}

write_checkpoint -force $PROJECT_DIR/post_synth.dcp
report_utilization              -file $PROJECT_DIR/utilization_synth.rpt
report_utilization -hierarchical -hierarchical_depth 6 -file $PROJECT_DIR/utilization_synth_hier.rpt
puts "=== Synthesis done ==="

# -----------------------------------------------------------------------
# Implementation
opt_design
place_design
route_design

write_checkpoint -force $PROJECT_DIR/post_route.dcp
report_utilization              -file $PROJECT_DIR/utilization_impl.rpt
report_utilization -hierarchical -hierarchical_depth 6 -file $PROJECT_DIR/utilization_impl_hier.rpt
report_timing_summary           -file $PROJECT_DIR/timing.rpt
puts "=== Implementation done ==="

# -----------------------------------------------------------------------
# Bitstream
file mkdir $PROJECT_DIR/rvsoc_kr260.runs/impl_1
write_bitstream -force $PROJECT_DIR/rvsoc_kr260.runs/impl_1/fpga_top_kr260.bit
puts "=== Bitstream written to $PROJECT_DIR/rvsoc_kr260.runs/impl_1/fpga_top_kr260.bit ==="
