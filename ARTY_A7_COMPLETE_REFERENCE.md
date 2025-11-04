# Arty A7-100 Complete Hardware Reference

**SOURCE:** Official Arty A7 Reference Manual (Arty_A7_Reference_Manual.docx)

**BOARD:** Arty A7-100 (XC7A100T-1CSG324C)

---

## Table of Contents

1. [System Clock](#system-clock)
2. [USB-UART Bridge](#usb-uart-bridge)
3. [GPIO (LEDs, Buttons, Switches)](#gpio)
4. [Ethernet PHY](#ethernet-phy)
5. [PMOD Connectors](#pmod-connectors)
6. [Shield Connector](#shield-connector)
7. [Power Supply](#power-supply)
8. [Pin Assignments (Quick Reference)](#pin-assignments)

---

## System Clock

### Specifications

- **Frequency:** 100 MHz
- **Pin:** E3 (MRCC input on bank 35)
- **Type:** Crystal oscillator
- **Usage:** Drive MMCMs/PLLs to generate various frequencies

### XDC Constraint

```tcl
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { CLK100MHz }]
create_clock -period 10.000 -name sys_clk_pin [get_ports CLK100MHz]
```

### Clock Resources

- 5 Clock Management Tiles (CMTs) on Arty A7-35
- 6 Clock Management Tiles (CMTs) on Arty A7-100
- Each CMT contains: PLL + MMCM
- Use Clocking Wizard IP for clock generation

---

## USB-UART Bridge

### Chip

- **Part:** FTDI FT2232HQ
- **Connector:** J10 (Micro USB)
- **Function:** Dual USB-JTAG and USB-UART

### UART Specifications

- **2-wire serial:** TXD + RXD
- **FPGA Pins:**
  - TX (FPGA → PC): A9
  - RX (FPGA ← PC): D10
- **Status LEDs:**
  - LD10: Transmit activity
  - LD9: Receive activity

### XDC Constraints

```tcl
## USB-UART Interface
set_property -dict { PACKAGE_PIN A9   IOSTANDARD LVCMOS33 } [get_ports { uart_txd_in }]
set_property -dict { PACKAGE_PIN D10  IOSTANDARD LVCMOS33 } [get_ports { uart_rxd_out }]
```

### Key Features

- Separate from JTAG (no interference)
- Requires VCP drivers from www.ftdichip.com
- CK_RST signal connected via JP2 (Microblaze reset support)

### Typical Usage (Project 5)

- **Baud Rate:** 115200
- **Format:** 8N1 (8 data bits, no parity, 1 stop bit)
- **Flow Control:** None

---

## GPIO

### Push Buttons (4x)

**Specifications:**

- **Type:** Momentary switches
- **Logic:** LOW at rest, HIGH when pressed
- **Protection:** Series resistors to prevent shorts

**Pin Assignments:**

```tcl
## Buttons
set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { btn[0] }]  # BTN0
set_property -dict { PACKAGE_PIN C9  IOSTANDARD LVCMOS33 } [get_ports { btn[1] }]  # BTN1
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports { btn[2] }]  # BTN2
set_property -dict { PACKAGE_PIN B8  IOSTANDARD LVCMOS33 } [get_ports { btn[3] }]  # BTN3
```

### Reset Button

**Specifications:**

- **Color:** Red
- **Logic:** HIGH at rest, LOW when pressed
- **Usage:** General purpose or Microblaze reset
- **Connected to:**
  - RST pin on shield connector J7
  - FT2232 via JP2 (optional)

**Pin Assignment:**

```tcl
## Reset Button
set_property -dict { PACKAGE_PIN C2  IOSTANDARD LVCMOS33 } [get_ports { reset_btn }]
```

### Slide Switches (4x)

**Specifications:**

- **Type:** SPDT switches
- **Logic:** Constant HIGH or LOW based on position
- **Protection:** Series resistors

**Pin Assignments:**

```tcl
## Switches
set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports { sw[0] }]  # SW0
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports { sw[1] }]  # SW1
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports { sw[2] }]  # SW2
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports { sw[3] }]  # SW3
```

### Individual LEDs (4x)

**Specifications:**

- **Color:** Green
- **Type:** High-efficiency
- **Connection:** Anode to FPGA via 330Ω resistors
- **Logic:** HIGH = ON, LOW = OFF

**Pin Assignments:**

```tcl
## LEDs
set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led[0] }]  # LED0
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led[1] }]  # LED1
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led[2] }]  # LED2
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led[3] }]  # LED3
```

### Tri-Color RGB LEDs (4x)

**Specifications:**

- **Colors:** Red, Green, Blue per LED
- **Connection:** Cathode-driven through transistor (INVERTED)
- **Logic:** HIGH = LED ON (inverted by transistor)
- **⚠️ WARNING:** Use PWM! Maximum 50% duty cycle recommended
- **Reason:** Direct HIGH = uncomfortably bright

**Pin Assignments:**

```tcl
## RGB LEDs (4 sets, 12 pins total)
set_property -dict { PACKAGE_PIN E1  IOSTANDARD LVCMOS33 } [get_ports { led0_b }]
set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33 } [get_ports { led0_g }]
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports { led0_r }]
set_property -dict { PACKAGE_PIN G4  IOSTANDARD LVCMOS33 } [get_ports { led1_b }]
set_property -dict { PACKAGE_PIN J4  IOSTANDARD LVCMOS33 } [get_ports { led1_g }]
set_property -dict { PACKAGE_PIN G3  IOSTANDARD LVCMOS33 } [get_ports { led1_r }]
set_property -dict { PACKAGE_PIN H4  IOSTANDARD LVCMOS33 } [get_ports { led2_b }]
set_property -dict { PACKAGE_PIN J2  IOSTANDARD LVCMOS33 } [get_ports { led2_g }]
set_property -dict { PACKAGE_PIN J3  IOSTANDARD LVCMOS33 } [get_ports { led2_r }]
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports { led3_b }]
set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports { led3_g }]
set_property -dict { PACKAGE_PIN K1  IOSTANDARD LVCMOS33 } [get_ports { led3_r }]
```

**PWM Example (VHDL):**

```vhdl
-- Generate 1 kHz PWM with 25% duty cycle
process(clk)
    variable counter : integer range 0 to 99999 := 0;
begin
    if rising_edge(clk) then
        counter := counter + 1;
        if counter < 25000 then
            led0_r <= '1';  -- ON for 25% of period
        else
            led0_r <= '0';  -- OFF for 75% of period
        end if;
        if counter = 99999 then
            counter := 0;
        end if;
    end if;
end process;
```

---

## Ethernet PHY

**See separate document:** [ARTY_A7_ETHERNET_SPECS.md](computer:///mnt/user-data/outputs/ARTY_A7_ETHERNET_SPECS.md)

**Quick Summary:**

- **Chip:** TI DP83848J
- **Interface:** MII (NOT RGMII!)
- **Speed:** 10/100 Mbps (NOT Gigabit!)
- **Reference Clock:** FPGA must generate 25 MHz

---

## PMOD Connectors

### Overview

- **Total:** 4 PMOD connectors
- **Pinout:** 2×6 right-angle female (100-mil spacing)
- **Power:** VCC (3.3V) + GND on pins 5,6,11,12
- **Logic:** 8 signal pins per connector
- **Max Current:** 1A per VCC/GND pair
- **⚠️ WARNING:** Do NOT exceed 3.4V on any pin!

### Connector Types

#### Standard PMODs (JA, JB)

- **Protection:** 200Ω series resistors
- **Use Case:** General purpose, lower speed
- **Advantage:** Short-circuit protection
- **Disadvantage:** Limited speed

#### High-Speed PMODs (JC, JD)

- **Protection:** 0Ω shunts (no protection!)
- **Use Case:** Differential signaling, high speed
- **Paired Signals:**
  - Pins 1&2, 3&4, 7&8, 9&10
- **⚠️ WARNING:** No short-circuit protection!

### Pin Assignments

**PMOD JA (Standard):**

```tcl
set_property -dict { PACKAGE_PIN G13  IOSTANDARD LVCMOS33 } [get_ports { ja[0] }]
set_property -dict { PACKAGE_PIN B11  IOSTANDARD LVCMOS33 } [get_ports { ja[1] }]
set_property -dict { PACKAGE_PIN A11  IOSTANDARD LVCMOS33 } [get_ports { ja[2] }]
set_property -dict { PACKAGE_PIN D12  IOSTANDARD LVCMOS33 } [get_ports { ja[3] }]
set_property -dict { PACKAGE_PIN D13  IOSTANDARD LVCMOS33 } [get_ports { ja[4] }]
set_property -dict { PACKAGE_PIN B18  IOSTANDARD LVCMOS33 } [get_ports { ja[5] }]
set_property -dict { PACKAGE_PIN A18  IOSTANDARD LVCMOS33 } [get_ports { ja[6] }]
set_property -dict { PACKAGE_PIN K16  IOSTANDARD LVCMOS33 } [get_ports { ja[7] }]
```

**PMOD JB (Standard):**

```tcl
set_property -dict { PACKAGE_PIN E15  IOSTANDARD LVCMOS33 } [get_ports { jb[0] }]
set_property -dict { PACKAGE_PIN E16  IOSTANDARD LVCMOS33 } [get_ports { jb[1] }]
set_property -dict { PACKAGE_PIN D15  IOSTANDARD LVCMOS33 } [get_ports { jb[2] }]
set_property -dict { PACKAGE_PIN C15  IOSTANDARD LVCMOS33 } [get_ports { jb[3] }]
set_property -dict { PACKAGE_PIN J17  IOSTANDARD LVCMOS33 } [get_ports { jb[4] }]
set_property -dict { PACKAGE_PIN J18  IOSTANDARD LVCMOS33 } [get_ports { jb[5] }]
set_property -dict { PACKAGE_PIN K15  IOSTANDARD LVCMOS33 } [get_ports { jb[6] }]
set_property -dict { PACKAGE_PIN J15  IOSTANDARD LVCMOS33 } [get_ports { jb[7] }]
```

**PMOD JC (High-Speed):**

```tcl
set_property -dict { PACKAGE_PIN U12  IOSTANDARD LVCMOS33 } [get_ports { jc[0] }]
set_property -dict { PACKAGE_PIN V12  IOSTANDARD LVCMOS33 } [get_ports { jc[1] }]
set_property -dict { PACKAGE_PIN V10  IOSTANDARD LVCMOS33 } [get_ports { jc[2] }]
set_property -dict { PACKAGE_PIN V11  IOSTANDARD LVCMOS33 } [get_ports { jc[3] }]
set_property -dict { PACKAGE_PIN U14  IOSTANDARD LVCMOS33 } [get_ports { jc[4] }]
set_property -dict { PACKAGE_PIN V14  IOSTANDARD LVCMOS33 } [get_ports { jc[5] }]
set_property -dict { PACKAGE_PIN T13  IOSTANDARD LVCMOS33 } [get_ports { jc[6] }]
set_property -dict { PACKAGE_PIN U13  IOSTANDARD LVCMOS33 } [get_ports { jc[7] }]
```

**PMOD JD (High-Speed):**

```tcl
set_property -dict { PACKAGE_PIN D4   IOSTANDARD LVCMOS33 } [get_ports { jd[0] }]
set_property -dict { PACKAGE_PIN D3   IOSTANDARD LVCMOS33 } [get_ports { jd[1] }]
set_property -dict { PACKAGE_PIN F4   IOSTANDARD LVCMOS33 } [get_ports { jd[2] }]
set_property -dict { PACKAGE_PIN F3   IOSTANDARD LVCMOS33 } [get_ports { jd[3] }]
set_property -dict { PACKAGE_PIN E2   IOSTANDARD LVCMOS33 } [get_ports { jd[4] }]
set_property -dict { PACKAGE_PIN D2   IOSTANDARD LVCMOS33 } [get_ports { jd[5] }]
set_property -dict { PACKAGE_PIN H2   IOSTANDARD LVCMOS33 } [get_ports { jd[6] }]
set_property -dict { PACKAGE_PIN G2   IOSTANDARD LVCMOS33 } [get_ports { jd[7] }]
```

---

## Power Supply

### Input Options

1. **USB (J10):** 5V via Micro USB
2. **Power Jack (J13):** 7-15V DC, center-positive, 2.1/2.5mm
3. **Battery Pack (J7):** 7-15V DC via VIN pin

### Power Selection

- Automatic switching based on availability
- **Priority:** External > USB
- **Power-Good LED:** LD11 (driven by 3.3V rail)

### Voltage Rails

| Rail    | Voltage | Typical Current | Max Current   |
| ------- | ------- | --------------- | ------------- |
| VCC5V0  | 5.0V    | 1.0A            | 3.0A          |
| VCC3V3  | 3.3V    | 1.5A            | 3.0A          |
| VCC1V8  | 1.8V    | 0.2A            | 1.0A          |
| VCC1V35 | 1.35V   | 0.3A            | 0.6A          |
| VCCINT  | 1.0V    | 1.0A (2.0A)\*   | 1.5A (3.0A)\* |
| VCCBRAM | 1.0V    | 0.1A            | 0.5A          |
| VCCAUX  | 1.8V    | 0.1A            | 0.5A          |

\*Values in parentheses for Arty A7-100

### External Supply Recommendations

- **Voltage:** 12V DC preferred (7-15V range)
- **Current:** 3A minimum
- **Power:** 36W (12V × 3A) recommended
- **Connector:** Coaxial, center-positive, 2.1mm ID

---

## Pin Assignments (Quick Reference)

### Complete Master XDC File

**Source:** https://github.com/Digilent/digilent-xdc

Choose the correct file:

- `Arty-A7-35-Master.xdc` for Arty A7-35
- `Arty-A7-100-Master.xdc` for Arty A7-100

### Most Common Signals Summary

```tcl
## Clock
CLK100MHz: E3

## UART
uart_txd_in:  A9   # FPGA → PC
uart_rxd_out: D10  # FPGA ← PC

## LEDs
led[0:3]: H5, J5, T9, T10

## RGB LEDs
led0_r/g/b: G6, F6, E1
led1_r/g/b: G3, J4, G4
led2_r/g/b: J3, J2, H4
led3_r/g/b: K1, H6, K2

## Buttons
btn[0:3]: D9, C9, B9, B8
reset:    C2

## Switches
sw[0:3]: A8, C11, C10, A10
```

---

## Critical Notes & Lessons Learned

### 1. Always Check Documentation First!

**Mistake:** Implementing RGMII for Ethernet when board uses MII
**Time Lost:** 2+ hours
**Lesson:** Read official manual BEFORE writing any code

### 2. RGB LED Brightness

**Issue:** Driving RGB LEDs to steady HIGH = uncomfortably bright
**Solution:** Use PWM with max 50% duty cycle
**Reference:** Section 9.1 of manual

### 3. High-Speed PMOD Protection

**Issue:** JC and JD have NO series resistors (0Ω shunts)
**Risk:** No short-circuit protection
**Solution:** Use JA/JB for general purpose, JC/JD only for high-speed differential

### 4. Reset Button Logic

**Important:** Reset button is HIGH at rest, LOW when pressed
**Opposite of:** Regular buttons (LOW at rest)

### 5. UART Signal Names

**Perspective:** From PC/DTE point of view
**TX (A9):** FPGA transmits TO PC
**RX (D10):** FPGA receives FROM PC

---

## Additional Resources

- **Official Manual:** Arty_A7_Reference_Manual.docx (this file!)
- **Master XDC:** https://github.com/Digilent/digilent-xdc
- **Resource Center:** https://digilent.com/reference/programmable-logic/arty-a7/start
- **Tutorials:** Available on Resource Center
- **Support:** Digilent Forum - forum.digilent.com

---

**Last Updated:** November 4, 2025  
**Document Version:** 1.0  
**Based on:** Arty A7 Reference Manual Rev. E
