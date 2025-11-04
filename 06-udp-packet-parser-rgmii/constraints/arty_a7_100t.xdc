####################################################################################
## Project 6: UDP Packet Parser - Phase 1A
## Constraints File for Xilinx Arty A7-100T
##
## Pin assignments for:
##   - 100 MHz system clock
##   - Ethernet RGMII interface (RTL8211E PHY)
##   - LEDs and buttons
##   - RGB LEDs
####################################################################################

####################################################################################
## Clock Signal (100 MHz)
####################################################################################
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { CLK }];

####################################################################################
## Reset Button (BTN0)
####################################################################################
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { ck_rst }];

####################################################################################
## LEDs (LD0-LD3)
####################################################################################
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

####################################################################################
## RGB LEDs (LD4, LD5)
####################################################################################
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports { led0_r }];
set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33 } [get_ports { led0_g }];
set_property -dict { PACKAGE_PIN E1  IOSTANDARD LVCMOS33 } [get_ports { led0_b }];

set_property -dict { PACKAGE_PIN G3  IOSTANDARD LVCMOS33 } [get_ports { led1_r }];
set_property -dict { PACKAGE_PIN J4  IOSTANDARD LVCMOS33 } [get_ports { led1_g }];
set_property -dict { PACKAGE_PIN G4  IOSTANDARD LVCMOS33 } [get_ports { led1_b }];

####################################################################################
## Ethernet PHY (RTL8211E-VL) - RGMII Interface
####################################################################################

## Receive Path (PHY -> FPGA)
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[0] }];
set_property -dict { PACKAGE_PIN E17 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[1] }];
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[2] }];
set_property -dict { PACKAGE_PIN G17 IOSTANDARD LVCMOS33 } [get_ports { eth_rxd[3] }];
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 } [get_ports { eth_rx_clk }];
set_property -dict { PACKAGE_PIN G16 IOSTANDARD LVCMOS33 } [get_ports { eth_rx_ctl }];

## Transmit Path (FPGA -> PHY)
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 } [get_ports { eth_txd[0] }];
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports { eth_txd[1] }];
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports { eth_txd[2] }];
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { eth_txd[3] }];
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { eth_tx_clk }];
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports { eth_tx_ctl }];

## PHY Reset (active low)
set_property -dict { PACKAGE_PIN C16 IOSTANDARD LVCMOS33 } [get_ports { eth_rst_n }];

####################################################################################
## Timing Constraints
####################################################################################

## System Clock (100 MHz)
create_clock -period 10.000 -name sys_clk [get_ports CLK]

## Ethernet RX Clock (125 MHz from PHY)
## This is an input clock from external PHY
create_clock -period 8.000 -name eth_rx_clk [get_ports eth_rx_clk]

## Set input delay for RGMII receive signals (relative to eth_rx_clk)
## RGMII spec: +/- 0.5ns setup/hold window
set_input_delay -clock [get_clocks eth_rx_clk] -max 2.0 [get_ports {eth_rxd[*] eth_rx_ctl}]
set_input_delay -clock [get_clocks eth_rx_clk] -min 0.0 [get_ports {eth_rxd[*] eth_rx_ctl}]

## Set output delay for RGMII transmit signals (Phase 2)
set_output_delay -clock [get_clocks eth_rx_clk] -max 2.0 [get_ports {eth_txd[*] eth_tx_ctl}]
set_output_delay -clock [get_clocks eth_rx_clk] -min 0.0 [get_ports {eth_txd[*] eth_tx_ctl}]

## Clock domain crossing (125 MHz eth_rx_clk -> 100 MHz sys_clk)
## Allow some additional time for CDC paths
set_max_delay -from [get_clocks eth_rx_clk] -to [get_clocks sys_clk] 10.000
set_max_delay -from [get_clocks sys_clk] -to [get_clocks eth_rx_clk] 8.000

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

# Generated clock from MMCM (TX clock)
create_generated_clock -name eth_tx_clk_gen \
    -source [get_pins mmcm_tx_clock/CLKIN1] \
    -multiply_by 10 -divide_by 8 \
    [get_pins mmcm_tx_clock/CLKOUT0]