# Project 6: UDP Packet Parser (RGMII) - ABANDONED

**Status:** DISCONTINUED - HARDWARE INTERFACE MISMATCH

---

## Project Discontinuation

Project discontinued due to incorrect interface selection. Implementation used RGMII (Reduced Gigabit Media Independent Interface) when hardware requires MII (Media Independent Interface).

### Root Cause

Hardware verification was insufficient prior to implementation. The Arty A7 Reference Manual clearly specifies:

> "The Arty A7 includes a Texas Instruments 10/100 Ethernet PHY (TI part number DP83848J) paired with an RJ-45 Ethernet jack with integrated magnetics and indicator LEDs. The TI PHY uses the MII interface and supports 10/100 Mb/s."

---

## Technical Analysis

| Specification       | RGMII (Implemented) | MII (Required)     | Impact                 |
| ------------------- | ------------------- | ------------------ | ---------------------- |
| **Speed**           | 1000 Mbps           | 10/100 Mbps        | Interface incompatible |
| **Protocol**        | RGMII               | MII                | Wrong physical layer   |
| **Clock Source**    | FPGA -> PHY (TX)     | PHY -> FPGA (TX/RX) | Incorrect architecture |
| **Clock Frequency** | 125 MHz             | 25 MHz             | 5× frequency error     |
| **Data Sampling**   | DDR (both edges)    | SDR (rising edge)  | Wrong timing           |
| **Pin Count**       | ~12                 | ~18                | Incorrect pinout       |

---

## Interface Specifications

### RGMII (Implemented - Incorrect)

```
Interface: Reduced Gigabit Media Independent Interface
Maximum Speed: 1000 Mbps
Data Width: 4-bit DDR (sampled on both clock edges)
Clock Frequency: 125 MHz
Clock Direction: FPGA drives TX_CLK, PHY provides RX_CLK
Reference Clock: None required
Pin Count: ~12 signals
Compatibility: Gigabit Ethernet PHYs only
```

### MII (Required - Correct)

```
Interface: Media Independent Interface
Maximum Speed: 100 Mbps (10 Mbps optional)
Data Width: 4-bit SDR (sampled on rising edge only)
Clock Frequency: 25 MHz (100 Mbps mode)
Clock Direction: PHY provides both TX_CLK and RX_CLK
Reference Clock: 25 MHz from FPGA required
Pin Count: ~18 signals
Compatibility: DP83848J PHY (10/100 Mbps)
```

**Hardware Incompatibility:** The DP83848J PHY does not support RGMII protocol.

---

## Files in This Directory

This directory contains the **incorrect RGMII implementation**:

- `src/rgmii_rx.vhd` - RGMII receiver (wrong for Arty A7)
- `src/mac_rx.vhd` - MAC parser (reusable, but needs MII input)
- `src/stats_counter.vhd` - Statistics counter (reusable)
- `constraints/arty_a7_100t.xdc` - Constraints with wrong pin assignments

**WARNING: DO NOT USE THESE FILES WITH ARTY A7!**

They are kept here for educational purposes only.

---

## What Can Be Reused

Some modules can be adapted for MII:

**Can reuse with modifications:**

- MAC frame parser logic (byte-level processing)
- Statistics counter (no changes needed)
- General architecture concepts

**Cannot reuse:**

- RGMII receiver (DDR sampling, wrong protocol)
- Clock generation (wrong frequencies)
- Pin constraints (wrong pins for wrong signals)

---

## Correct Implementation

**See the correct MII implementation:**

```
../06-udp-parser-mii/
```

The MII version:

- Uses correct interface (MII not RGMII)
- Correct clock architecture (PHY provides clocks)
- Generates 25 MHz reference clock for PHY
- Proper pin assignments from official docs
- Single Data Rate (simpler than DDR!)
- Actually works with Arty A7 hardware

---

## Process Improvement

### Issue Identified

Inadequate hardware verification during project initialization led to incompatible interface selection.

### Corrected Development Process

1. Review board reference manual and identify PHY specifications
2. Verify PHY datasheet for supported interfaces
3. Confirm pin assignments via official constraint files
4. Validate clock architecture requirements
5. Begin implementation

### Documentation Sources

Hardware specifications were available in public documentation:

1. **Arty A7 Reference Manual** - Section 6: Ethernet PHY

   - Interface type clearly specified (MII)
   - PHY part number listed (DP83848J)
   - Speed limitations documented (10/100 Mbps)

2. **Master XDC Constraint File** - GitHub repository

   - All 18 MII signal pins defined
   - Pin locations and standards specified

3. **DP83848J Datasheet** - Texas Instruments
   - MII timing specifications
   - 25 MHz reference clock requirement
   - Protocol details

### Time Investment Analysis

- Implementation: 2 hours
- Debug cycles: 1.5 hours
- Issue identification: 15 minutes
- **Total: 4 hours**

Documentation review (30 minutes) would have prevented this development cycle.

---

## Project Metrics

### Implementation Statistics

- **VHDL Source Code:** ~600 lines

  - RGMII receiver: ~150 lines
  - MAC parser: ~150 lines
  - Top-level integration: ~200 lines
  - Constraint file: ~100 lines

- **Development Time:** 4 hours total
  - Research (insufficient): 15 minutes
  - RGMII implementation: 2 hours
  - Debug and verification: 1.5 hours
  - Root cause analysis: 15 minutes

### Deliverables

- Non-functional RGMII implementation
- Improved development process documentation
- Hardware verification checklist

---

## Correct Implementation

**Project Location:** `../06-udp-parser-mii/`

The corrected implementation features:

- MII interface (hardware compatible)
- 25 MHz reference clock generation
- PHY-provided data clocks
- Verified pin assignments
- Functional frame reception

---

## Key Takeaway

Hardware verification must precede implementation. Comprehensive documentation review during project initialization prevents architectural incompatibilities.

---

## Repository Status

**Status:** Discontinued
**Date Discontinued:** November 4, 2025  
**Reason:** Hardware interface incompatibility (RGMII vs MII)  
**Replacement:** See `../06-udp-parser-mii/`  
**Archive Purpose:** Development process documentation
**Completed:** November 3, 2025  
**Last Updated:** November 4, 2025  
**Hardware:** Xilinx Arty A7-100T (XC7A100T-1CSG324C)

---

_Part of FPGA Learning Journey - Building trading-relevant hardware skills_
