# KR260 (XCK26) constraints for fpga_top_kr260
# All PL I/O on KD240 carrier: bank 66, VCCO = 1.8V → LVCMOS18
#
# PINS TO VERIFY before generating bitstream:
#   clk_25mhz : Check KD240 schematic for the 25 MHz reference routed to J2 pin 7
#               SOM240_1_D4 is typically PACKAGE_PIN H4 (bank 66) — confirm in Vivado I/O planner
#   reset     : User push button on KD240 carrier — check KD240 schematic for push button pin
#               Common candidate: SOM240_1_A20 = PACKAGE_PIN C6 (bank 66) — confirm
#   pmod[0:7] : PMOD J7 on KD240. Data pins (skipping power/gnd):
#               J7 pin 1 = SOM240_1_C17 = PACKAGE_PIN E5  (bank 66) → pmod[0]
#               J7 pin 2 = SOM240_1_C18 = PACKAGE_PIN D5  (bank 66) → pmod[1]
#               J7 pin 3 = SOM240_1_C19 = PACKAGE_PIN D6  (bank 66) → pmod[2]
#               J7 pin 4 = SOM240_1_C20 = PACKAGE_PIN C5  (bank 66) → pmod[3]
#               J7 pin 7 = SOM240_1_D17 = PACKAGE_PIN F4  (bank 66) → pmod[4]
#               J7 pin 8 = SOM240_1_D18 = PACKAGE_PIN E4  (bank 66) → pmod[5]
#               J7 pin 9 = SOM240_1_D19 = PACKAGE_PIN D4  (bank 66) → pmod[6]
#               J7 pin 10= SOM240_1_D20 = PACKAGE_PIN C4  (bank 66) → pmod[7]
#
# To verify: open Vivado → I/O Planning view after synthesis, check the
# package diagram. AMD also provides kr260_starter_kit_master.xdc in the
# board files (Boards → KR260 → Master Constraints).
#
# VRP pins that MUST NOT be used: G4, W9, AD6

# ---------------------------------------------------------------------------
# Clock: 25 MHz reference from KD240 RPi header J2 pin 7
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN H4      [get_ports clk_25mhz]
set_property IOSTANDARD  LVCMOS18 [get_ports clk_25mhz]
create_clock -period 40.000 -name clk_25mhz [get_ports clk_25mhz]

# GCIO and BUFG are in different clock regions — demote to warning.
# MMCM PLL loop filter absorbs the extra jitter on the 25 MHz input path.
# Remove once a proper clock pin / PS FCLK approach is in place.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_25mhz_IBUF_inst/O]

# 100 MHz generated clock (from MMCM output, for timing analysis)
create_generated_clock -name clk_100 \
    -source [get_pins bufg_clkin/O] \
    -multiply_by 4 \
    [get_pins mmcm_inst/CLKOUT0]

# ---------------------------------------------------------------------------
# PMOD J7 data pins → gpio_out[5:0]
# Only the 6 pins confirmed valid on xck26-sfvc784-2LV-c.
# C5 (pmod[3] orig), F4 (pmod[4] orig), C6 (reset) rejected by Vivado —
# not valid IO sites on this package. Verify against KD240 schematic when
# doing a full pin-out pass.
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN E5      [get_ports {pmod[0]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {pmod[0]}]

set_property PACKAGE_PIN D5      [get_ports {pmod[1]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {pmod[1]}]

set_property PACKAGE_PIN D6      [get_ports {pmod[2]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {pmod[2]}]

set_property PACKAGE_PIN E4      [get_ports {pmod[3]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {pmod[3]}]

set_property PACKAGE_PIN D4      [get_ports {pmod[4]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {pmod[4]}]

set_property PACKAGE_PIN C4      [get_ports {pmod[5]}]
set_property IOSTANDARD  LVCMOS18 [get_ports {pmod[5]}]
