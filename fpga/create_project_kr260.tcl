# create_project_kr260.tcl — creates Vivado project for rvsoc_top on Kria KR260
# Usage: vivado -mode batch -source fpga/create_project_kr260.tcl
# Run from repo root: /data/rp2040-clone

set REPO_ROOT [pwd]
set PROJECT_NAME rvsoc_kr260
set PROJECT_DIR $REPO_ROOT/fpga/vivado_kr260

# Create project
create_project $PROJECT_NAME $PROJECT_DIR -part xck26-sfvc784-2LV-c -force

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

# KR260-specific FPGA top wrapper
read_verilog -sv $REPO_ROOT/fpga/fpga_top_kr260.sv

# -----------------------------------------------------------------------
# Constraints
add_files -fileset constrs_1 $REPO_ROOT/fpga/kr260.xdc

# -----------------------------------------------------------------------
# Include path for Hazard3 .vh headers
set_property include_dirs $REPO_ROOT/rtl/core/hazard3/hdl [current_fileset]

# Set top module
set_property top fpga_top_kr260 [current_fileset]
update_compile_order -fileset sources_1

# -----------------------------------------------------------------------
# Synthesis
launch_runs synth_1
wait_on_run synth_1

# Synthesis reports
open_run synth_1
report_utilization                                                  -file $PROJECT_DIR/utilization_synth.rpt
report_utilization -hierarchical -hierarchical_depth 6              -file $PROJECT_DIR/utilization_synth_hier.rpt
puts "=== Synthesis done. Reports: utilization_synth.rpt, utilization_synth_hier.rpt ==="

# Implementation (place & route)
launch_runs impl_1 -to_step route_design
wait_on_run impl_1

# Implementation reports
open_run impl_1
report_utilization                                                  -file $PROJECT_DIR/utilization_impl.rpt
report_utilization -hierarchical -hierarchical_depth 6              -file $PROJECT_DIR/utilization_impl_hier.rpt
report_timing_summary                                               -file $PROJECT_DIR/timing.rpt
puts "=== Implementation done. Reports written to $PROJECT_DIR ==="

# Bitstream
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
puts "=== Bitstream written to $PROJECT_DIR/rvsoc_kr260.runs/impl_1/fpga_top.bit ==="
