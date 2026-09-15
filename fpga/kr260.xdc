# KR260 (XCK26) constraints for kr260_top
#
# Clock : PS FCLK0 — provided by ps_bd_wrapper (configured for 100 MHz).
#         Vivado generates timing constraints automatically from the block
#         design. No create_clock needed here.
#
# GPIO  : RPi 40-pin header — bank 45 (HDA), VCCO = 3.3V → LVCMOS33.
#         Safe to probe directly with 3.3V/5V logic analyzers.

# ---------------------------------------------------------------------------
# RPi 40-pin header → rpi_gpio[7:0]
# Bank 45 (HDA), VCCO = 3.3V → LVCMOS33. Safe to probe with 3.3V/5V logic analyzer.
# Pin numbers refer to physical RPi header positions.
# Source: Mikeantabian/KR260-XDC io_map.xdc
# ---------------------------------------------------------------------------
# RPi header pin 27 → gpio_out[0]
set_property PACKAGE_PIN AD15    [get_ports {rpi_gpio[0]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {rpi_gpio[0]}]

# RPi header pin 28 → gpio_out[1]
set_property PACKAGE_PIN AD14    [get_ports {rpi_gpio[1]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {rpi_gpio[1]}]

# RPi header pin 3 → gpio_out[2]
set_property PACKAGE_PIN AE15    [get_ports {rpi_gpio[2]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {rpi_gpio[2]}]

# RPi header pin 5 → gpio_out[3]
set_property PACKAGE_PIN AE14    [get_ports {rpi_gpio[3]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {rpi_gpio[3]}]

# RPi header pin 7 → gpio_out[4]
set_property PACKAGE_PIN AG14    [get_ports {rpi_gpio[4]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {rpi_gpio[4]}]

# RPi header pin 29 → gpio_out[5]
set_property PACKAGE_PIN AH14    [get_ports {rpi_gpio[5]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {rpi_gpio[5]}]

# RPi header pin 31 → gpio_out[6]
set_property PACKAGE_PIN AG13    [get_ports {rpi_gpio[6]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {rpi_gpio[6]}]

# RPi header pin 26 → gpio_out[7]
set_property PACKAGE_PIN AH13    [get_ports {rpi_gpio[7]}]
set_property IOSTANDARD  LVCMOS33 [get_ports {rpi_gpio[7]}]
