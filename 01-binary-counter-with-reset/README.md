# Binary Counter with Synchronous Reset

My first complete FPGA design - binary counter with button-controlled reset.

## Overview
4-bit binary counter displayed on LEDs, counting from 0-15 at 1 Hz. Reset button clears counter to zero.

## Hardware
- **Board:** Xilinx Arty A7-100T
- **FPGA:** Artix-7 XC7A100T
- **Resources Used:** 
  - LUTs: 42
  - Flip-Flops: 32
  - Clock: 100 MHz (system clock)

## Features
- Clock division from 100 MHz to 1 Hz
- Synchronous reset (glitch-free)
- Generic parameter for simulation speed adjustment
- Comprehensive testbench with multiple test scenarios

## Design Concepts
- **Clock Management:** Clock divider using counter
- **Reset Handling:** Synchronous reset on button press
- **Binary Representation:** Visual counting on 4 LEDs
- **Parameterization:** Generic for hardware/simulation flexibility

## Files
- `binary_counter.vhd` - Main design
- `binary_counter_tb.vhd` - Testbench with reset scenarios
- `arty_a7_100t.xdc` - Pin constraints

## Simulation
Testbench includes:
- Normal counting operation
- Reset during operation
- Multiple reset pulses
- Counting resume verification

Run with fast simulation (`COUNT_MAX = 99`) for quick verification.

## Hardware Demo
[Link to video or embed]

LEDs display binary count (LSB to MSB):
- LED[0]: Toggles every 1 second
- LED[1]: Toggles every 2 seconds
- LED[2]: Toggles every 4 seconds  
- LED[3]: Toggles every 8 seconds

## What I Learned
- Complete FPGA development workflow
- Testbench patterns for stimulus generation
- Waveform debugging techniques
- XDC syntax for single signals vs vectors
- Synchronous vs asynchronous reset trade-offs
- Generic parameters for design flexibility

## Next Steps
- Add count direction control (up/down)
- Variable speed control with switches
- 7-segment display output
- Multiple independent counters

## Trading Relevance
**Counter circuits** are fundamental in trading FPGAs for:
- Packet counting and statistics
- Hardware timestamping (nanosecond precision)
- Rate limiting and flow control
- Performance measurement

---

**Status:** ✅ Hardware Verified  
**Complexity:** Beginner  
**Time to Complete:** 4-6 hours (including debugging)