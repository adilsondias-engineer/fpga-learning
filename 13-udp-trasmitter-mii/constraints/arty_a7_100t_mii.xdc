####################################################################################
## Arty A7-100 Constraints for MII Ethernet Receiver
## Board: Arty A7-100T (XC7A100T-1CSG324C)
## PHY: TI DP83848J (MII Interface, 10/100 Mbps)
####################################################################################

####################################################################################
## System Clock (100 MHz)
####################################################################################
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { CLK }];

####################################################################################
## Reset Button (BTN0 - active HIGH when pressed)
####################################################################################
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { reset_btn }];
# CPU Reset button (active low)
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports { reset_n }];
# Debug Button (BTN3)
set_property -dict { PACKAGE_PIN B8 IOSTANDARD LVCMOS33 } [get_ports {debug_btn}];

####################################################################################
## MII Ethernet PHY (TI DP83848J)
####################################################################################

## Reference Clock (FPGA generates 25 MHz for PHY)
set_property -dict { PACKAGE_PIN G18  IOSTANDARD LVCMOS33 } [get_ports { eth_ref_clk }];

## PHY Reset (active LOW)
set_property -dict { PACKAGE_PIN C16  IOSTANDARD LVCMOS33 } [get_ports { eth_rstn }];

## MII RX Interface (PHY -> FPGA)
set_property -dict { PACKAGE_PIN F15  IOSTANDARD LVCMOS33 } [get_ports { eth_rx_clk }];
set_property -dict { PACKAGE_PIN G16  IOSTANDARD LVCMOS33 } [get_ports { eth_rx_dv }];
set_property -dict { PACKAGE_PIN D18  IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[0] }];
set_property -dict { PACKAGE_PIN E17  IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[1] }];
set_property -dict { PACKAGE_PIN E18  IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[2] }];
set_property -dict { PACKAGE_PIN G17  IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[3] }];
set_property -dict { PACKAGE_PIN C17  IOSTANDARD LVCMOS33 } [get_ports { eth_rx_er }];

## MII TX Interface (FPGA -> PHY) - Not used but must be constrained
set_property -dict { PACKAGE_PIN H16  IOSTANDARD LVCMOS33 } [get_ports { eth_tx_clk }];
set_property -dict { PACKAGE_PIN H15  IOSTANDARD LVCMOS33 } [get_ports { eth_tx_en }];
set_property -dict { PACKAGE_PIN H14  IOSTANDARD LVCMOS33 } [get_ports { eth_txd[0] }];
set_property -dict { PACKAGE_PIN J14  IOSTANDARD LVCMOS33 } [get_ports { eth_txd[1] }];
set_property -dict { PACKAGE_PIN J13  IOSTANDARD LVCMOS33 } [get_ports { eth_txd[2] }];
set_property -dict { PACKAGE_PIN H17  IOSTANDARD LVCMOS33 } [get_ports { eth_txd[3] }];

## MII Management Interface
set_property -dict { PACKAGE_PIN F16  IOSTANDARD LVCMOS33 } [get_ports { eth_mdc }];
set_property -dict { PACKAGE_PIN K13  IOSTANDARD LVCMOS33 } [get_ports { eth_mdio }];

## MII Status (half-duplex only)
set_property -dict { PACKAGE_PIN D17  IOSTANDARD LVCMOS33 } [get_ports { eth_col }];
set_property -dict { PACKAGE_PIN G14  IOSTANDARD LVCMOS33 } [get_ports { eth_crs }];

####################################################################################
## LEDs
####################################################################################

## Individual LEDs (frame counter)
set_property -dict { PACKAGE_PIN H5   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN J5   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN T9   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN T10  IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

## RGB LEDs (status indicators)
#set_property -dict { PACKAGE_PIN F6   IOSTANDARD LVCMOS33 } [get_ports { led0_g }];  # Activity (green)
#set_property -dict { PACKAGE_PIN G4   IOSTANDARD LVCMOS33 } [get_ports { led1_b }];  # PHY ready (blue)
#set_property -dict { PACKAGE_PIN J3   IOSTANDARD LVCMOS33 } [get_ports { led2_r }];  # Error (red)

# RGB LEDs (LD4 and LD5)
# LD4_R, LD4_G, LD4_B
set_property -dict { PACKAGE_PIN G6 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[2] }];
set_property -dict { PACKAGE_PIN F6 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[1] }];
set_property -dict { PACKAGE_PIN E1 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[0] }];

# LD5_R, LD5_G, LD5_B
set_property -dict { PACKAGE_PIN G3 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[5] }];
set_property -dict { PACKAGE_PIN J4 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[4] }];
set_property -dict { PACKAGE_PIN G4 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[3] }];

#debug led RGB
set_property -dict { PACKAGE_PIN H4 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[6] }]; #IO_L21N_T3_DQS_35 Sch=led2_b
set_property -dict { PACKAGE_PIN J2 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[7] }]; #IO_L22N_T3_35 Sch=led2_g
set_property -dict { PACKAGE_PIN J3 IOSTANDARD LVCMOS33 } [get_ports { led_rgb[8] }]; #IO_L22P_T3_35 Sch=led2_r

#set_property -dict { PACKAGE_PIN E1    IOSTANDARD LVCMOS33 } [get_ports { led0_b }]; #IO_L18N_T2_35 Sch=led0_b
#set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { led0_g }]; #IO_L19N_T3_VREF_35 Sch=led0_g
#set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { led0_r }]; #IO_L19P_T3_35 Sch=led0_r
#set_property -dict { PACKAGE_PIN G4    IOSTANDARD LVCMOS33 } [get_ports { led1_b }]; #IO_L20P_T3_35 Sch=led1_b
#set_property -dict { PACKAGE_PIN J4    IOSTANDARD LVCMOS33 } [get_ports { led1_g }]; #IO_L21P_T3_DQS_35 Sch=led1_g
#set_property -dict { PACKAGE_PIN G3    IOSTANDARD LVCMOS33 } [get_ports { led1_r }]; #IO_L20N_T3_35 Sch=led1_r
#set_property -dict { PACKAGE_PIN H4    IOSTANDARD LVCMOS33 } [get_ports { led2_b }]; #IO_L21N_T3_DQS_35 Sch=led2_b
#set_property -dict { PACKAGE_PIN J2    IOSTANDARD LVCMOS33 } [get_ports { led2_g }]; #IO_L22N_T3_35 Sch=led2_g
#set_property -dict { PACKAGE_PIN J3    IOSTANDARD LVCMOS33 } [get_ports { led2_r }]; #IO_L22P_T3_35 Sch=led2_r
#set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { led3_b }]; #IO_L23P_T3_35 Sch=led3_b
#set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { led3_g }]; #IO_L24P_T3_35 Sch=led3_g
#set_property -dict { PACKAGE_PIN K1    IOSTANDARD LVCMOS33 } [get_ports { led3_r }]; #IO_L23N_T3_35 Sch=led3_r


## USB-UART Interface
## Note: Xilinx uses confusing naming!
## uart_txd_in is actually RX (PC -> FPGA)
## uart_rxd_out is actually TX (FPGA -> PC)
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_rxd_out]


####################################################################################
## Timing Constraints
####################################################################################

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
set_false_path -from [get_ports reset_btn];

# LED outputs are asynchronous (no timing requirements)
set_false_path -to [get_ports led[*]];
set_false_path -to [get_ports led_rgb[*]];

## System clock (100 MHz)
create_clock -period 10.000 -name sys_clk [get_ports CLK]

## Reference clock (generated by FPGA for PHY)
create_generated_clock -name eth_ref_clk \
    -source [get_pins ref_clock_gen/CLKOUT0] \
    -divide_by 1 \
    [get_ports eth_ref_clk]

## RX clock from PHY (25 MHz for 100 Mbps mode)
create_clock -period 40.000 -name eth_rx_clk [get_ports eth_rx_clk]

## TX clock from PHY (25 MHz for 100 Mbps mode)
create_clock -period 40.000 -name eth_tx_clk [get_ports eth_tx_clk]

## Input delays for MII RX data (relative to eth_rx_clk)
## MII spec: setup/hold window is approximately 10ns
set_input_delay -clock eth_rx_clk -max 10.0 [get_ports {eth_rxd[*] eth_rx_dv eth_rx_er}]
set_input_delay -clock eth_rx_clk -min 0.0 [get_ports {eth_rxd[*] eth_rx_dv eth_rx_er}]

## Output delays for MII TX data (relative to eth_tx_clk)
## MII spec: PHY samples on rising edge with ~10ns setup/hold window
## We drive on falling edge, so we have half cycle (20ns) to meet setup
## Being conservative, allow 5ns for output delay (15ns margin)
set_output_delay -clock eth_tx_clk -max 5.0 [get_ports {eth_txd[*] eth_tx_en}]
set_output_delay -clock eth_tx_clk -min -2.0 [get_ports {eth_txd[*] eth_tx_en}]

## Clock domain crossing constraints
## eth_rx_clk (25 MHz) -> sys_clk (100 MHz) via 2FF synchronizer
set_max_delay -from [get_clocks eth_rx_clk] -to [get_clocks sys_clk] 40.0
set_max_delay -from [get_clocks sys_clk] -to [get_clocks eth_rx_clk] 10.0

## Mark asynchronous clock domains
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks eth_rx_clk] \
    -group [get_clocks eth_tx_clk] \
    -group [get_clocks eth_ref_clk]

## CDC Synchronizer Constraints
## Mark synchronizer flip-flops to prevent optimization and guide placement
set_property ASYNC_REG TRUE [get_cells -hier *ip_valid_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *udp_valid_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *frame_valid_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *ip_checksum_ok_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *ip_version_err_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *ip_ihl_err_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *ip_checksum_err_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *udp_length_err_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *mdio_rst_rxclk_sync*]

## False paths to first stage of synchronizers (metastability allowed here)
set_false_path -to [get_cells -hier *ip_valid_sync1*]
set_false_path -to [get_cells -hier *udp_valid_sync1*]
set_false_path -to [get_cells -hier *frame_valid_sync1*]
set_false_path -to [get_cells -hier *ip_checksum_ok_sync1*]
set_false_path -to [get_cells -hier *ip_version_err_sync1*]
set_false_path -to [get_cells -hier *ip_ihl_err_sync1*]
set_false_path -to [get_cells -hier *ip_checksum_err_sync1*]
set_false_path -to [get_cells -hier *udp_length_err_sync1*]
set_false_path -to [get_cells -hier *mdio_rst_rxclk_sync1*]

####################################################################################
## Configuration
####################################################################################

## Configuration bank voltage
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Bitstream options
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
