# Hardware FIFO Demo (4-bit Version)

Interactive FIFO buffer demonstration on Xilinx Arty A7-100T FPGA with physical button controls and LED visualization.

![Hardware Status](https://img.shields.io/badge/Hardware-Verified-brightgreen)
![FPGA](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7-blue)
![Language](https://img.shields.io/badge/Language-VHDL-orange)

## Overview

This project brings the FIFO buffer from [Project 3](../Project_3_FIFO) to life on real hardware. Users can interact with a working FIFO using physical buttons and switches, with real-time visual feedback through LEDs. This demonstrates the complete FPGA development workflow: simulation → synthesis → implementation → hardware deployment.

**Key Achievement:** This is my first complete system integration project - combining multiple IP blocks (FIFO, debouncer, edge detector) with hardware interfacing to create an interactive demonstration.

## Hardware Platform

- **Board:** Digilent Arty A7-100T
- **FPGA:** Xilinx Artix-7 XC7A100T-1CSG324C
- **Clock:** 100 MHz system clock
- **Resources Used:**
  - LUTs: ~150-200
  - Flip-Flops: ~100-150
  - Max Frequency: >200 MHz (running at 100 MHz)

## Features

✅ **Interactive Controls**

- Push buttons for write, read, and reset operations
- Hardware debouncing for reliable button presses
- Edge detection for single-cycle triggers

✅ **Visual Feedback**

- 4 standard LEDs display FIFO data output (4-bit values: 0x0-0xF)
- RGB LED provides status indication:
  - 🟢 Green = FIFO empty
  - 🔴 Red = FIFO full (16/16 entries)
  - 🔵 Blue = Partially filled (1-15 entries)

✅ **Robust Design**

- Metastability protection on all inputs
- 20ms debounce filtering
- Glitch-free operation

## User Interface

### Physical Controls

┌─────────────────────────────────────┐
│ Arty A7-100T Board │
│ │
│ SW3 SW2 SW1 SW0 ← Data Input │
│ │ │ │ │ (4 bits) │
│ └────┴────┴────┘ │
│ │
│ [BTN2] [BTN1] [BTN0] ← Controls │
│ Reset Read Write │
│ │
│ ● ← RGB Status LED │
│ (RGB0) │
│ │
│ [LD3] [LD2] [LD1] [LD0] │
│ Data Output LEDs │
└─────────────────────────────────────┘

### Button Functions

| Button   | Function | Description                                    |
| -------- | -------- | ---------------------------------------------- |
| **BTN0** | Write    | Store current switch value into FIFO           |
| **BTN1** | Read     | Retrieve next value from FIFO, display on LEDs |
| **BTN2** | Reset    | Clear FIFO (count → 0, status → empty)         |

### Status LED Color Codes

| Color        | Status  | FIFO Count                |
| ------------ | ------- | ------------------------- |
| 🟢 **GREEN** | Empty   | 0 entries                 |
| 🔵 **BLUE**  | Partial | 1-15 entries              |
| 🔴 **RED**   | Full    | 16 entries (max capacity) |

## How to Use

### Basic Operation

**1. Reset the System**
Action: Press BTN2
Result: RGB0 glows GREEN (empty)
LD0-LD3 turn off

```

**2. Write Data to FIFO**
```

Action: Set switches to binary value (e.g., 1010 = 0xA)
Press BTN0
Result: RGB0 changes to BLUE (has data)
Value stored in FIFO

```

**3. Read Data from FIFO**
```

Action: Press BTN1
Result: LD0-LD3 display the value (e.g., 1010)
First value written appears first (FIFO order!)

```

### Test Scenarios

#### Test 1: Single Write/Read
```

1. Reset (BTN2) → GREEN
2. Switches: 0101 (5)
3. Write (BTN0) → BLUE
4. Read (BTN1) → LEDs show: 0101 ✓
5. Read again → GREEN (empty)

```

#### Test 2: FIFO Order Verification
```

1. Reset
2. Write sequence: 0001, 0010, 0011, 0100
3. Read 4 times
4. LEDs display: 0001, 0010, 0011, 0100 (same order!) ✓

```

#### Test 3: Full Condition
```

1. Reset
2. Write 16 different values
3. RGB0 turns RED (full) ✓
4. Attempt 17th write → Ignored (still RED)

```

#### Test 4: Empty Condition
```

1. After filling, read 16 times
2. RGB0 turns GREEN (empty) ✓
3. Attempt another read → LEDs unchanged (no data)

```

#### Test 5: Binary Counter Demo
```

1. Reset
2. Write: 0000, 0001, 0010, 0011, 0100, 0101, 0110, 0111
3. Read 8 times watching LEDs
4. LEDs count up: 0→1→2→3→4→5→6→7 ✓

```

## Architecture

### System Block Diagram
```

User Input
↓
┌──────────────────────────────────────────┐
│ Hardware Interface Layer │
│ │
│ Switches[3:0] ──────────────┐ │
│ │ │
│ BTN0 ──→ Debouncer ──→ Edge │ │
│ BTN1 ──→ Debouncer ──→ Edge ├──→ Ctrl │
│ BTN2 ──→ Debouncer ──→ Edge │ Logic │
│ │ │
└──────────────────────────────┼───────────┘
↓
┌───────────────────────┐
│ FIFO Core │
│ (from Project 3) │
│ │
│ • 4-bit data width │
│ • 16-entry depth │
│ • Full/Empty flags │
└───────────────────────┘
↓
┌───────────────────────────────────────────┐
│ Output Display │
│ │
│ LEDs[3:0] ←────── data_out │
│ RGB0_R ←────── full │
│ RGB0_G ←────── empty │
│ RGB0_B ←────── partial (Blue logic) │
└───────────────────────────────────────────┘

```

### Component Hierarchy
```

fifo_demo (top-level)
├── debouncer_btn0 (debouncer)
│ └── 3-stage synchronizer + counter
├── debouncer_btn1 (debouncer)
├── debouncer_btn2 (debouncer)
├── edge_det_btn0 (edge_detector)
│ └── Delayed signal comparison
├── edge_det_btn1 (edge_detector)
├── edge_det_btn2 (edge_detector)
└── fifo_inst (fifo)
├── Memory array (16 x 4-bit)
├── Write pointer [3:0]
├── Read pointer [3:0]
└── Count register [4:0]

```

### Signal Flow

**Write Operation:**
```

User presses BTN0
↓
Debouncer (20ms filter)
↓
Edge Detector (rising edge)
↓
FIFO wr_en = 1 (single cycle pulse)
↓
data_in[3:0] ← switches[3:0]
↓
FIFO stores at write pointer location
↓
Write pointer increments
Count increments
Status updates

```

**Read Operation:**
```

User presses BTN1
↓
Debouncer (20ms filter)
↓
Edge Detector (rising edge)
↓
FIFO rd_en = 1 (single cycle pulse)
↓
data_out[3:0] ← memory[read pointer]
↓
Read pointer increments
Count decrements
LEDs update
Status updates

````

## Design Components

### 1. Button Debouncer (Reused from Project 2)

**Purpose:** Eliminate mechanical bounce from physical buttons

**Implementation:**
- 3-stage synchronizer (metastability protection)
- 20ms debounce counter
- Stable output only after sustained state

**Key Parameters:**
```vhdl
CLK_FREQ    : 100 MHz
DEBOUNCE_MS : 20 ms
DEBOUNCE_COUNT : 2,000,000 clock cycles
````

### 2. Edge Detector (Reused from Project 2)

**Purpose:** Generate single-cycle pulse on button press/release

**Implementation:**

```vhdl
rising edge  = sig_in AND (NOT sig_delayed)
falling edge = (NOT sig_in) AND sig_delayed
```

**Why needed:** Without edge detection, holding button would trigger continuous writes/reads

### 3. FIFO Core (Reused from Project 3)

**Purpose:** First-In, First-Out data buffer

**Specifications:**

- Data width: 4 bits (modified from 8-bit for this demo)
- Depth: 16 entries
- Circular buffer (pointers wrap at 15→0)

**Generic modified for 4-bit:**

```vhdl
fifo_inst: fifo
    generic map (
        DATA_WIDTH => 4,   -- Changed from 8
        DEPTH      => 16
    )
```

### 4. Top-Level Wrapper (New)

**Purpose:** System integration and hardware interface

**Responsibilities:**

- Instantiate all components
- Connect signals between modules
- Map to physical I/O pins
- Implement status LED logic

**Status Logic:**

```vhdl
led0_r <= fifo_full;                          -- Red when full
led0_g <= fifo_empty;                         -- Green when empty
led0_b <= not fifo_empty and not fifo_full;  -- Blue when partial
```

## File Structure

```
04-fifo-hardware/
├── src/
│   ├── fifo_hardware.vhd     # Top-level system integration
│   ├── fifo.vhd              # FIFO core (4-bit data width)
│   ├── button_debouncer.vhd  # Button debouncer with sync
│   └── edge_detector.vhd     # Rising/falling edge detection
├── constraints/
│   └── arty_a7_100t.xdc      # Pin assignments and timing
└── README.md                 # This file
```

### Pin Assignments

**Inputs:**

- Clock: E3 (100 MHz differential clock)
- Buttons: D9 (BTN0), C9 (BTN1), B9 (BTN2)
- Switches: A8, C11, C10, A10 (SW0-SW3)

**Outputs:**

- LEDs: H5, J5, T9, T10 (LD0-LD3)
- RGB0: G6 (Red), F6 (Green), E1 (Blue)

## Key Learning Outcomes

### Technical Skills Acquired

✅ **IP Reuse:** Integrated three separate IP blocks into a cohesive system  
✅ **Hardware Interfacing:** Mapped VHDL signals to physical pins  
✅ **Metastability Handling:** Understood importance of synchronizers  
✅ **Flow Control:** Implemented safe buffering with full/empty protection  
✅ **System Integration:** Connected multiple modules with proper signal management  
✅ **Constraints:** Wrote XDC file for pin locations and timing

### FPGA Development Workflow Mastered

```
Design Entry (VHDL)
    ↓
Behavioral Simulation (Optional for this project)
    ↓
Synthesis (RTL → Gates)
    ↓
Implementation (Place & Route)
    ↓
Bitstream Generation
    ↓
Hardware Programming
    ↓
Physical Testing ✓
```

### Real-World Design Principles Applied

**1. Modularity**

- Each component has single responsibility
- Can swap implementations without changing others
- Reusable across projects

**2. Defensive Design**

- Debouncing prevents glitches
- Edge detection prevents unintended operations
- Full/empty flags prevent corruption

**3. User Experience**

- Immediate visual feedback (LEDs + RGB)
- Intuitive controls (one button per function)
- Clear status indication

## Known Limitations

**Current Constraints:**

- 4-bit data width (limited by 4 switches)
- No visual indication of FIFO count (only full/empty/partial)
- Sequential operation (can't read while writing)

**These are addressed in upcoming projects:**

- Project 4B: 8-bit data with breadboard LED expansion
- Project 4C: OLED display showing queue contents and count
- Project 4D: Multiple displays with real-time visualization

## Troubleshooting

### Issue: Button Triggers Multiple Times

**Cause:** Debouncer not working or button held too long  
**Solution:** Verify debouncer instantiated correctly, press and release quickly

### Issue: RGB LED Wrong Color

**Cause:** Pin assignment error or logic inverted  
**Solution:** Check XDC file pins, verify status logic in top-level

### Issue: LEDs Don't Change on Read

**Cause:** FIFO empty (nothing to read)  
**Solution:** Write some data first, or reset and try again

### Issue: Can't Write After 16 Operations

**Cause:** FIFO full (working as designed!)  
**Solution:** Read some data to make space, or reset

## Next Steps

### Immediate Enhancement (Project 4B)

- Add 8 breadboard LEDs via ChipKit connector
- Display full 8-bit data values
- Implement 8-bit FIFO (two 4-bit nibbles)

### Visual Upgrade (Project 4C)

- Add OLED display (I2C interface)
- Show queue contents visually
- Display real-time count and status

### Full Integration (Project 4D)

- Multiple displays simultaneously
- 7-segment display (hex values)
- LED matrix (fill level bar graph)

### Advanced Features

- UART interface for PC control
- Data logging
- Performance counters
- Automated test sequences

## Resources

**Documentation:**

- [Arty A7 Reference Manual](https://digilent.com/reference/programmable-logic/arty-a7/reference-manual)
- [Arty A7 Schematic](https://digilent.com/reference/_media/reference/programmable-logic/arty-a7/arty_a7_sch.pdf)
- [Xilinx 7 Series FPGAs Datasheet](https://www.xilinx.com/support/documentation/data_sheets/ds180_7Series_Overview.pdf)

**Related Projects:**

- [Project 1: Binary Counter](../01-binary-counter-with-reset)
- [Project 2: Button Debouncer](../02-button-bebouncer)
- [Project 3: FIFO Core](../03-fifo)

## Acknowledgments

This project builds on concepts from the classic FPGA learning path, adapted for hands-on hardware demonstration with the Arty A7-100T development board.

---

**Status:** ✅ Completed and verified on hardware  
**Completed:** 30/10/2025
**Last Updated:** 30/10/2025
**Time Invested:** ~10 hours (design, debug, testbench fixes, verification)

**Next Project:** Display expansion with external LEDs and OLED

---

_Part of FPGA Learning Journey - Building trading-relevant skills_
