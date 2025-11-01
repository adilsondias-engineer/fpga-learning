## This file is a general .xdc for the Arty A7-100 Rev. D
## Project 4B - 8-bit FIFO with Rotary Encoder
## CORRECTED PIN MAPPINGS verified against Arty-A7-100-Master.xdc

## Clock signal (100 MHz)
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk]

## Buttons
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
set_property -dict {PACKAGE_PIN B9 IOSTANDARD LVCMOS33} [get_ports {btn[2]}]
set_property -dict {PACKAGE_PIN B8 IOSTANDARD LVCMOS33} [get_ports {btn[3]}]

## Onboard LEDs (show lower 4 bits of current value)
set_property -dict {PACKAGE_PIN H5  IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5  IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

## RGB LED 0 (Status indicators)
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports led0_r]
set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS33} [get_ports led0_g]
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports led0_b]

## ============================================================================
## ROTARY ENCODER - CORRECTED WIRING
## ============================================================================
## User wired to ChipKit ANALOG pins A9, A10, A11 (inner analog header)
##
## Encoder CLK -> ChipKit A11 [analog pin 11] -> FPGA pin A3
set_property -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports encoder_a]

## Encoder DT  -> ChipKit A10 [analog pin 10] -> FPGA pin A4
set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports encoder_b]

## Encoder SW  -> ChipKit A9  [analog pin 9]  -> FPGA pin E5
set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33} [get_ports encoder_sw]
## multimeter testing shows encoder switch connects to 3.3v when pressed
set_property PULLDOWN TRUE [get_ports encoder_sw] ## Use PULLDOWN since switch connects to 3.3v(HIGH) when pressed - ACTIVE HIGH
## low 0 when not pressed, high 1 when pressed
## ============================================================================

## ============================================================================
## EXTERNAL 8-BIT RAINBOW LED DISPLAY
## ============================================================================
## Connect to ChipKit digital IO pins 26-33 (inner digital header)
##
## Bit 7 (MSB) - RED LED
set_property -dict {PACKAGE_PIN U11 IOSTANDARD LVCMOS33} [get_ports {led_ext[7]}]

## Bit 6 - YELLOW LED
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {led_ext[6]}]

## Bit 5 - GREEN LED
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports {led_ext[5]}]

## Bit 4 - LIGHT GREEN LED
set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS33} [get_ports {led_ext[4]}]

## Bit 3 - LIGHT BLUE LED
set_property -dict {PACKAGE_PIN R11 IOSTANDARD LVCMOS33} [get_ports {led_ext[3]}]

## Bit 2 - BLUE LED
set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports {led_ext[2]}]

## Bit 1 - WHITE LED
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33} [get_ports {led_ext[1]}]

## Bit 0 (LSB) - CLEAR LED
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports {led_ext[0]}]

## ============================================================================
## BUZZER (Piezo Speaker)
## ============================================================================
## Connect to ChipKit IO40 (inner digital header)
set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports buzzer]

## ============================================================================
## Configuration and Bitstream Settings
## ============================================================================
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
#set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
## ============================================================================
## Timing Constraints for Asynchronous Inputs
## ============================================================================
## Rotary encoder inputs are asynchronous - set as false paths
set_false_path -from [get_ports encoder_a]
set_false_path -from [get_ports encoder_b]
set_false_path -from [get_ports encoder_sw]


## Button inputs are also asynchronous
set_false_path -from [get_ports btn[*]]

## ============================================================================
## CORRECTED Pin Assignment Notes
## ============================================================================
## ChipKit Analog Pin Mapping (User's Wiring):
##   A9  (ChipKit analog pin 9)  = FPGA pin E5  -> encoder_sw
##   A10 (ChipKit analog pin 10) = FPGA pin A4  -> encoder_b (DT)
##   A11 (ChipKit analog pin 11) = FPGA pin A3  -> encoder_a (CLK)
##
## ChipKit Inner Digital IO Mapping (Rainbow LEDs):
##   IO26 (ck_io26) = FPGA pin U11 -> led_ext[7] RED
##   IO27 (ck_io27) = FPGA pin V16 -> led_ext[6] YELLOW
##   IO28 (ck_io28) = FPGA pin M13 -> led_ext[5] GREEN
##   IO29 (ck_io29) = FPGA pin R10 -> led_ext[4] LT.GREEN
##   IO30 (ck_io30) = FPGA pin R11 -> led_ext[3] LT.BLUE
##   IO31 (ck_io31) = FPGA pin R13 -> led_ext[2] BLUE
##   IO32 (ck_io32) = FPGA pin R15 -> led_ext[1] WHITE
##   IO33 (ck_io33) = FPGA pin P15 -> led_ext[0] CLEAR
##   IO40 (ck_io40) = FPGA pin P18 -> buzzer
##
## ============================================================================
## PREVIOUS ERRORS FIXED:
## ============================================================================
## ❌ OLD (WRONG): encoder_a -> V12  (This is Pmod JC pin, not analog A11!)
## ✅ NEW (RIGHT): encoder_a -> A3   (ChipKit analog pin A11)
##
## ❌ OLD (WRONG): encoder_b -> W16  (This pin DOESN'T EXIST on Arty A7-100T!)
## ✅ NEW (RIGHT): encoder_b -> A4   (ChipKit analog pin A10)
##
## ❌ OLD (WRONG): encoder_sw -> J15 (This is Pmod JB pin, not analog A9!)
## ✅ NEW (RIGHT): encoder_sw -> E5  (ChipKit analog pin A9)
##
## Also updated LED pins from outer digital header (IO0-IO7) to inner digital
## header (IO26-IO33) for better physical layout on board.
## ============================================================================
