################################################################################
## MDIO Test Constraints
## Pin assignments and timing constraints for Arty A7-100T MDIO test
################################################################################

################################################################################
## Clock and Reset
################################################################################

# 100 MHz system clock
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { clk_100mhz }];
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports clk_100mhz];

# CPU Reset button (active low)
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports { reset_n }];

################################################################################
## MDIO Interface (DP83848J PHY)
################################################################################

# MDIO clock output (2.5 MHz max)
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 } [get_ports { eth_mdc }];

# MDIO bidirectional data
set_property -dict { PACKAGE_PIN K13 IOSTANDARD LVCMOS33 } [get_ports { eth_mdio }];

################################################################################
## LEDs (Display register values)
################################################################################

# Standard LEDs (4-bit display)
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

# RGB LEDs (LD4 and LD5)
# LD4_R, LD4_G, LD4_B
set_property -dict { PACKAGE_PIN G6 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[2] }];
set_property -dict { PACKAGE_PIN F6 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[1] }];
set_property -dict { PACKAGE_PIN E1 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[0] }];

# LD5_R, LD5_G, LD5_B
set_property -dict { PACKAGE_PIN G3 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[5] }];
set_property -dict { PACKAGE_PIN J4 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[4] }];
set_property -dict { PACKAGE_PIN G4 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[3] }];

################################################################################
## Timing Constraints
################################################################################

# MDIO timing is very relaxed (2.5 MHz, 400ns period)
# MDC is generated internally via clock division from sys_clk
# No need for strict input/output delay constraints since:
# 1. MDC is internally generated (not externally constrained)
# 2. MDIO operates at 2.5 MHz (very slow compared to 100 MHz sys_clk)
# 3. PHY setup/hold times are easily met with internal logic

# Mark MDIO interface as asynchronous to sys_clk
# (internally synchronized by state machine to generated MDC)
set_false_path -to [get_ports { eth_mdc }];
set_false_path -to [get_ports { eth_mdio }];
set_false_path -from [get_ports { eth_mdio }];

# Asynchronous reset path
set_false_path -from [get_ports reset_n];

# LED outputs are asynchronous (no timing requirements)
set_false_path -to [get_ports led[*]];
set_false_path -to [get_ports led_rgb[*]];

################################################################################
## Configuration
################################################################################

# Configuration voltage
set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];
