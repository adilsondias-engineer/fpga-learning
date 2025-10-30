# Simple FIFO Buffer

A synchronous First-In, First-Out (FIFO) buffer demonstrating memory management, pointer arithmetic, and flow control - fundamental building blocks for packet buffering and data streaming in trading systems.

## Overview

A FIFO (First-In, First-Out) buffer is a fundamental data structure in digital systems that stores data in order and retrieves it in the same order. Think of it like a queue at a store - the first person in line gets served first. FIFOs are critical for managing data flow between components operating at different speeds or handling burst traffic.

**This is a simulation-only project** - no hardware interface yet. The focus is on understanding the core FIFO logic and memory management. Hardware integration comes in Project 4.

## Trading System Relevance

**FIFOs are everywhere in trading infrastructure:**

- **Packet Buffers:** Store incoming market data during processing bursts
- **Order Queues:** Manage pending orders waiting for execution
- **Clock Domain Crossing:** Safely transfer data between different clock domains
- **Rate Matching:** Handle data arriving faster than it can be processed
- **Message Buffering:** Queue messages between pipeline stages

**Real-world example:** When market data arrives at 10 Gbps but your parser processes at 5 Gbps, a FIFO prevents packet loss during traffic bursts.

## Hardware

- **Target Board:** Xilinx Arty A7-100T
- **FPGA:** Artix-7 XC7A100T
- **Clock:** 100 MHz (simulation)
- **Interface:** Simulation only (no physical I/O)

## Design Specifications

### Parameters

- **Data Width:** 8 bits (configurable via generic)
- **Depth:** 16 entries (configurable via generic, must be power of 2)
- **Memory Type:** Inferred (synthesizer chooses distributed RAM or BRAM)

### Interface Signals

**Inputs:**

- `clk` - System clock
- `rst` - Synchronous reset
- `wr_en` - Write enable (store data)
- `rd_en` - Read enable (retrieve data)
- `data_in[7:0]` - Data to write

**Outputs:**

- `data_out[7:0]` - Data being read
- `full` - FIFO full flag (cannot write)
- `empty` - FIFO empty flag (cannot read)
- `count[4:0]` - Number of entries currently in FIFO (0-16)

### Operational Rules

1. **Write when not full:** Data written when `wr_en=1` AND `full=0`
2. **Read when not empty:** Data read when `rd_en=1` AND `empty=0`
3. **Ignored operations:** Write attempts when full are ignored; read attempts when empty are ignored
4. **Order preservation:** Data comes out in the exact order it went in (FIFO property)

## Architecture

### Memory Structure

```
Internal Memory Array (16 x 8-bit):
┌─────────┐
│ Entry 0 │ ← rd_ptr points here when reading oldest data
├─────────┤
│ Entry 1 │
├─────────┤
│ Entry 2 │
├─────────┤
│   ...   │
├─────────┤
│ Entry 15│ ← wr_ptr points here when writing new data
└─────────┘

Pointers wrap around:
After Entry 15, next is Entry 0 (circular buffer)
```

### Key Components

**1. Memory Array**

```vhdl
type memory_type is array (0 to DEPTH-1) of STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
signal memory : memory_type;
```

- Synthesizes to distributed RAM or Block RAM
- 16 locations × 8 bits = 128 bits total storage

**2. Write Pointer**

```vhdl
signal wr_ptr : unsigned(3 downto 0);
```

- Points to next write location
- Increments after each write
- Wraps from 15 back to 0

**3. Read Pointer**

```vhdl
signal rd_ptr : unsigned(3 downto 0);
```

- Points to next read location
- Increments after each read
- Wraps from 15 back to 0

**4. Counter**

```vhdl
signal fifo_count : unsigned(4 downto 0);
```

- Tracks number of valid entries (0-16)
- Increments on write, decrements on read
- Used to generate `full` and `empty` flags

### State Management

**Full Detection:**

```vhdl
full <= '1' when fifo_count = DEPTH else '0';
```

- FIFO full when all 16 entries occupied
- Prevents overwrites

**Empty Detection:**

```vhdl
empty <= '1' when fifo_count = 0 else '0';
```

- FIFO empty when no valid data
- Prevents reading garbage

**Counter Update Logic:**

```
Write only (wr_en=1, rd_en=0):     count = count + 1
Read only  (rd_en=1, wr_en=0):     count = count - 1
Both       (wr_en=1, rd_en=1):     count = count (no change)
Neither    (wr_en=0, rd_en=0):     count = count (no change)
```

## Files

```
Project_3_FIFO/
├── src/
│   └── fifo.vhd              # Core FIFO logic
│   └── fifo_tb.vhd           # Comprehensive testbench
├── simulation
|   └── fifo_tb_behav_test_4_and_8_failing.wcfg #wave form
|
└── README.md                 # This file
```

**Note:** No constraints file (`.xdc`) needed - this is simulation-only.

## Testbench Coverage

The testbench validates all critical FIFO behaviors:

### Test Scenarios

**Test 1: Reset Behavior**

- Verifies FIFO starts empty after reset
- Checks all pointers and counters initialize to zero

**Test 2: Single Write**

- Writes one data item
- Verifies `empty` flag clears
- Checks count increments to 1

**Test 3: Single Read**

- Reads the written data
- Verifies data integrity (data out matches data in)
- Checks FIFO returns to empty state

**Test 4: Fill Completely**

- Writes 16 items sequentially (0x00 to 0x0F)
- Verifies `full` flag asserts
- Checks count reaches 16

**Test 5: Write When Full**

- Attempts write with FIFO full
- Verifies operation is ignored
- Checks count remains 16

**Test 6: Empty Completely**

- Reads all 16 items
- Verifies data order preserved (FIFO property)
- Checks `empty` flag asserts

**Test 7: Simultaneous Read/Write**

- Performs concurrent read and write operations
- Verifies count remains stable
- Tests pipeline operation

**Test 8: Pointer Wraparound**

- Writes and reads beyond depth
- Verifies pointers wrap from 15 to 0
- Tests circular buffer behavior

## Running the Simulation

### Setup

1. **Create new Vivado project** (if not already created)
2. **Add source files:**
   - Add `fifo.vhd` to **Design Sources**
   - Add `fifo_tb.vhd` to **Simulation Sources**
3. **Set `fifo_tb` as top module** for simulation

### Execute

1. Click **Run Behavioral Simulation**
2. Wait for simulation to complete
3. Check **Tcl Console** for test results

### Expected Console Output

```
TEST 1: Reset behavior
TEST 2: Write single item
TEST 3: Read single item
TEST 4: Fill FIFO (16 writes)
TEST 5: Write when full (should be ignored)
TEST 6: Empty FIFO (16 reads)
TEST 7: Simultaneous read and write
TEST 8: Pointer wraparound test
All tests completed successfully!
```

**Any assertion failures indicate a bug in the design.**

## Waveform Analysis

### Key Signals to Observe

Add these signals to your waveform viewer:

**Control Signals:**

- `clk` - Clock (reference for all operations)
- `rst` - Reset pulse
- `wr_en` - Write enable
- `rd_en` - Read enable

**Data Signals:**

- `data_in[7:0]` - Hex display recommended
- `data_out[7:0]` - Hex display recommended

**Status Signals:**

- `full` - Should assert when count=16
- `empty` - Should assert when count=0
- `count[4:0]` - Decimal display recommended

**Internal Signals (if visible):**

- `wr_ptr[3:0]` - Write pointer position
- `rd_ptr[3:0]` - Read pointer position
- `memory` - Memory array contents

### What to Look For

**During Test 4 (Fill FIFO):**

```
Waveform pattern:
wr_en:    ___┌─┐_┌─┐_┌─┐_┌─┐___  (16 pulses)
data_in:  ───┤0├─┤1├─┤2├─┤3├───  (counting up)
count:    ──0─1──2──3──4──...─16 (increments)
full:     ────────────────────┌─  (asserts at 16)
wr_ptr:   ──0─1──2──3──4──...─0  (wraps around)
```

**During Test 6 (Empty FIFO):**

```
Waveform pattern:
rd_en:    ___┌─┐_┌─┐_┌─┐_┌─┐___  (16 pulses)
data_out: ───┤0├─┤1├─┤2├─┤3├───  (same order as input!)
count:    ─16─15─14─13─12─...─0  (decrements)
empty:    ─────────────────────┌─ (asserts at 0)
rd_ptr:   ──0─1──2──3──4──...─0  (wraps around)
```

**During Test 7 (Simultaneous R/W):**

```
Waveform pattern:
wr_en:    ___┌─┐___  (write)
rd_en:    ___┌─┐___  (read at same time)
count:    ──1───1──  (stays constant)
```

## Resources

- **Xilinx UG473:** 7 Series Memory Resources User Guide
- **Xilinx UG901:** Vivado Design Suite Synthesis User Guide (FIFO inference)

---

**Completed:** 30/10/2025
**Last Updated:** 30/10/2025
**Time Invested:** ~6 hours (design, debug, testbench fixes, verification)
**Key Learning:**
✅ **FIFO Architecture:** How circular buffers work  
✅ **Memory Management:** Pointer arithmetic and wraparound  
✅ **Flow Control:** Using full/empty flags  
✅ **Data Integrity:** Preserving order in buffers  
✅ **Testbench Design:** Comprehensive verification methodology  
✅ **Resource Inference:** How HDL maps to hardware

---

_Part of FPGA Learning Journey - Building trading-relevant skills_
