# Project 4B: 8-bit FIFO with Rotary Encoder Interface

A hardware FIFO implementation on Xilinx Artix-7 FPGA with rotary encoder input, real-time LED visualization, and audio feedback.

![Project Status](https://img.shields.io/badge/status-complete-success)
![FPGA](https://img.shields.io/badge/FPGA-Artix--7-blue)
![Language](https://img.shields.io/badge/language-VHDL-orange)

---

## Overview

This project implements a parameterized 8-bit FIFO (First-In-First-Out) queue on an FPGA with a professional user interface featuring:

- Rotary encoder for value selection (0-255)
- Real-time 8-LED binary visualization
- Audio feedback for all operations
- Dual display modes (edit/read)
- Hardware debouncing and edge detection

**Target Hardware:** Digilent Arty A7-100T Development Board

---

## Features

### Core Functionality

- **8-bit FIFO Queue:** 16-deep parameterized design
- **Rotary Encoder Interface:** Quadrature decoding with metastability protection
- **Dual Display Modes:**
  - Edit Mode: Live preview of selected value
  - Read Mode: Display of FIFO output data
- **Audio Feedback:**
  - Write confirmation: 100ms, 1kHz tone
  - Read confirmation: 50ms, 1kHz tone
  - Status transitions: Variable tones for empty/full states

### Hardware Interface

- **Input:**
  - Rotary encoder (CLK, DT, SW)
  - 4 push buttons (write, read, reset, unused)
- **Output:**
  - 8 external LEDs (8-bit value display)
  - 4 onboard LEDs (lower nibble display)
  - 1 RGB LED (FIFO status: empty/partial/full)
  - Piezo buzzer (5V with transistor driver)

---

## Architecture

### Block Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Top Level                               │
│  ┌────────────┐    ┌──────────────┐    ┌──────────────┐         │
│  │  Rotary    │───▶│   Counter    │───▶│  Display     │───▶LED│
│  │  Encoder   │    │  (8-bit)     │    │  Multiplexer │         │
│  └────────────┘    └──────────────┘    └──────────────┘         │
│        │                    │                    ▲              │
│        │                    │                    │              │
│        ▼                    ▼                    │              │
│  ┌────────────┐    ┌──────────────┐     ───────┴──────┐         │
│  │  Debouncer │    │     FIFO     │───▶│  Read Data   │        │
│  │  + Edge    │───▶│   (16-deep)  │    └──────────────┘        │
│  │  Detector  │    └──────────────┘                             │
│  └────────────┘            │                                    │
│                             │                                   │
│                             ▼                                   │
│                    ┌──────────────┐                             │
│                    │   Buzzer     │───────────────────▶Buzzer
│                    │  Controller  │                             │
│                    └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

### Component Descriptions

#### 1. Rotary Encoder Decoder (`rotary_encoder.vhd`)

- **Purpose:** Quadrature decoding for bidirectional rotation detection
- **Features:**
  - 3-stage synchronizer for metastability protection
  - State machine for accurate edge sequencing
  - Outputs: Single-cycle pulses for CW/CCW rotation
- **Specifications:**
  - Detects both clockwise and counter-clockwise rotation
  - Debounce-free operation (handles mechanical switch noise)
  - Wraps at 0x00 ↔ 0xFF boundaries

#### 2. FIFO Buffer (`fifo.vhd`)

- **Architecture:** Parameterized ring buffer
- **Configuration:**
  - Data width: 8 bits
  - Depth: 16 entries
  - Synchronous read/write
- **Signals:**
  - `full`, `empty`: Status flags
  - `count`: Current occupancy (5-bit)
  - Write-on-full and read-on-empty protected

#### 3. Button Debouncer (`button_debouncer.vhd`)

- **Algorithm:** Counter-based stable state detection
- **Parameters:**
  - Clock frequency: 100 MHz
  - Debounce time: 50ms (configurable)
- **Applied to:** All buttons and encoder switch

#### 4. Edge Detector (`edge_detector.vhd`)

- **Function:** Generates single-cycle pulses on rising/falling edges
- **Use case:** Converts level signals to action triggers

#### 5. Buzzer Controller (`buzzer_controller.vhd`)

- **Modes:**
  - Manual tone generation (1kHz square wave)
  - Status-based beeps (empty/full transitions)
- **Implementation:** Configurable frequency divider

---

## Technical Specifications

| Parameter         | Value                               |
| ----------------- | ----------------------------------- |
| **FPGA Clock**    | 100 MHz                             |
| **Data Width**    | 8 bits                              |
| **FIFO Depth**    | 16 entries                          |
| **Debounce Time** | 50 ms                               |
| **Encoder Type**  | HW-040 rotary encoder (active high) |
| **Logic Levels**  | 3.3V LVCMOS                         |
| **Audio Tone**    | 1 kHz square wave                   |

---

## Pin Assignments (Arty A7-100T)

### Rotary Encoder

| Signal | ChipKit Pin | FPGA Pin | Description                                              |
| ------ | ----------- | -------- | -------------------------------------------------------- |
| CLK    | A11         | A3       | Encoder clock                                            |
| DT     | A10         | A4       | Encoder data                                             |
| SW     | A9          | E5       | Encoder switch (active high, requires external pulldown) |

### LEDs

| Signal       | ChipKit Pins | FPGA Pins                              | Description   |
| ------------ | ------------ | -------------------------------------- | ------------- |
| led_ext[7:0] | IO26-IO33    | U11, V16, M13, R10, R11, R13, R15, P15 | 8-bit display |
| led[3:0]     | Onboard      | H5, J5, T9, T10                        | Lower nibble  |
| RGB LED 0    | Onboard      | G6 (R), F6 (G), E1 (B)                 | Status        |

### Audio

| Signal | ChipKit Pin | FPGA Pin | Description                        |
| ------ | ----------- | -------- | ---------------------------------- |
| buzzer | IO40        | P18      | Via 2N2222 transistor to 5V buzzer |

### Buttons

| Signal | Onboard | FPGA Pin | Function       |
| ------ | ------- | -------- | -------------- |
| btn[0] | BTN0    | D9       | Write (backup) |
| btn[1] | BTN1    | C9       | Read from FIFO |
| btn[2] | BTN2    | B9       | Reset FIFO     |
| btn[3] | BTN3    | B8       | Unused         |

---

## Building the Project

### Prerequisites

- Xilinx Vivado 2020.1 or later
- Digilent Arty A7-100T board
- Micro-USB cable for programming

### Hardware Setup

#### Breadboard Connections

**Rotary Encoder (HW-040):**

```
Encoder to Arty A7
------------------
  +    - 3.3V
  GND  - GND
  CLK  - A11 (Pin A3)
  DT   - A10 (Pin A4)
  SW   - A9  (Pin E5) + 10kΩ pulldown to GND
```

**8 Rainbow LEDs:**

```
Each LED: FPGA IO pin -> 330Ω resistor -> LED anode -> GND
Use color-matched resistors for balanced brightness:
  Bit 7 (RED)    - 680Ω
  Bit 6 (YELLOW) - 470Ω
  Bit 5 (GREEN)  - 330Ω
  Bit 4-0        - 330Ω (or adjust per LED efficiency)
```

**Buzzer Circuit:**

```
FPGA IO40 -> 1kΩ -> 2N2222 Base
                   Collector -> Buzzer+ -> 5V
                   Emitter -> GND
```

**CRITICAL:** HW-040 encoder SW pin requires **external 10kΩ pulldown resistor** to GND.

### Synthesis and Implementation

1. **Create Vivado Project:**

   ```
   Target: xc7a100tcsg324-1 (Arty A7-100T)
   Language: VHDL
   ```

2. **Add Source Files:**

   ```
   src/fifo_hardware_8bit_encoder.vhd    (Top-level)
   src/rotary_encoder.vhd
   src/button_debouncer.vhd
   src/edge_detector.vhd
   src/fifo.vhd
   src/buzzer_controller.vhd
   ```

3. **Add Constraints:**

   ```
   constraints/arty_a7_100t.xdc
   ```

4. **Run Synthesis:**

   ```
   Vivado: Flow -> Run Synthesis
   ```

5. **Run Implementation:**

   ```
   Vivado: Flow -> Run Implementation
   ```

6. **Generate Bitstream:**

   ```
   Vivado: Flow -> Generate Bitstream
   ```

7. **Program Device:**
   ```
   Vivado: Flow -> Open Hardware Manager -> Program Device
   ```

---

## Usage

### Basic Operation

1. **Edit Mode (Default):**

   - Turn encoder knob: Value increments/decrements (0-255)
   - Rainbow LEDs display selected value in real-time
   - No data written yet

2. **Write to FIFO:**

   - Press encoder button (or BTN0)
   - System beeps (100ms confirmation)
   - Value added to FIFO
   - RGB LED updates status

3. **Read from FIFO:**

   - Press BTN1
   - System beeps (50ms confirmation)
   - Rainbow LEDs display read value
   - Automatically switches to read mode

4. **Reset:**
   - Press BTN2
   - FIFO clears
   - Returns to edit mode at 0x00

### Visual Feedback

**RGB LED Status:**

- 🟢 Green: FIFO empty
- 🔵 Blue: FIFO partially filled
- 🔴 Red: FIFO full

**Onboard LEDs:**

- Display lower 4 bits of current value (edit mode) or read value (read mode)

**External 8 LEDs:**

- Binary representation of full 8-bit value
- MSB (bit 7) at top/left, LSB (bit 0) at bottom/right

### Audio Feedback

| Event | Tone  | Duration | When                 |
| ----- | ----- | -------- | -------------------- |
| Write | 1 kHz | 100 ms   | Data written to FIFO |
| Read  | 1 kHz | 50 ms    | Data read from FIFO  |
| Empty | High  | 150 ms   | FIFO becomes empty   |
| Full  | Low   | 200 ms   | FIFO becomes full    |

---

## Example Workflow

```vhdl
-- Write sequence to FIFO
Turn encoder to 0x42
Press encoder button         -- Beep! Written to FIFO
Turn encoder to 0xA5
Press encoder button         -- Beep! Written to FIFO

-- Read sequence back
Press BTN1                   -- Beep! LEDs show 0x42
Press BTN1                   -- Beep! LEDs show 0xA5
Press BTN1                   -- Beep! FIFO now empty (green LED)

-- Mode automatically switches
Turn encoder                 -- Back to edit mode
```

---

## Troubleshooting

### Encoder Switch Not Working

**Symptom:** Rotation works, but button press doesn't trigger write

**Cause:** HW-040 encoder SW is active high and needs external pulldown - checked with multimeter

**Solution:**

1. Add 10kΩ resistor from pin E5 to GND
2. Verify XDC has: `set_property PULLDOWN TRUE [get_ports encoder_sw]`
3. Ensure no signal inversion in code (active high encoder)

### Encoder Counts in Wrong Direction

**Solution:** Swap CLK and DT pin assignments in XDC

### LEDs Too Dim or Bright

**Solution:** Adjust current-limiting resistors:

- Dimmer: Increase resistance (470Ω -> 680Ω)
- Brighter: Decrease resistance (330Ω -> 220Ω)
- Balance colors: Use different values per LED efficiency

### Buzzer Too Quiet

**Cause:** Using 3.3V directly on 5V-rated buzzer

**Solution:** Verify transistor driver circuit is correctly wired with 5V supply

---

## Design Decisions

### Why Rotary Encoder?

- **Professional UI:** Eliminates clunky switch-based input
- **Real-time feedback:** See value before committing
- **Speed:** Faster than entering two nibbles sequentially
- **User experience:** Natural interaction model

### Why Dual Display Modes?

- **Edit mode:** Preview selection before writing
- **Read mode:** Verify FIFO contents
- **Automatic switching:** Reduces user mental overhead

### Why Hardware Debouncing?

- **Reliability:** Mechanical switches bounce 5-50ms
- **Deterministic:** Fixed timing, no guesswork
- **Reusable:** Parameterized component for all buttons

### Why Quadrature Decoding?

- **Accuracy:** Detects direction and magnitude
- **Noise immunity:** State machine filters spurious transitions
- **Metastability protection:** 3-stage synchronizer prevents FPGA clock domain issues

---

## Future Enhancements

### Potential Additions

- [ ] OLED display integration (Project 4C)
- [ ] PWM audio synthesis (musical notes)
- [ ] Serial/UART data logging
- [ ] Multiple FIFO queues with selection
- [ ] Statistics display (min/max/average values)
- [ ] Programmable depth/width via generics
- [ ] Almost-full/almost-empty flags

### Performance Optimizations

- [ ] Pipelined read/write for higher throughput
- [ ] Asynchronous FIFO for clock domain crossing
- [ ] Burst mode operations

---

## License

This project is provided as-is for educational purposes.

---

## Acknowledgments

- **Hardware:** Digilent Arty A7-100T Development Board
- **Tools:** Xilinx Vivado Design Suite
- **Components:** HW-040 Rotary Encoder Module

---

## Project Structure

```
Project_4B/
├── README.md                           # This file
├── src/
│   ├── fifo_hardware_8bit_encoder.vhd # Top-level entity
│   ├── rotary_encoder.vhd             # Quadrature decoder
│   ├── button_debouncer.vhd           # Switch debouncer
│   ├── edge_detector.vhd              # Edge detection
│   ├── fifo.vhd                       # FIFO buffer
│   └── buzzer_controller.vhd          # Audio generation
├── constraints/
│   └── arty_a7_100t.xdc               # Pin assignments and timing
├── docs/
│   └── pictures
│
└── simulation/
    └── tb_fifo_hardware_8bit_encoder.vhd                    # Testbench (optional)
```

---

## Contact

For questions or contributions, please open an issue on GitHub.

---

**Built with:** VHDL, Vivado, VS Code, Arty A7-100T
**Status:** Completed and verified on hardware  
**Completed:** 31/10/2025  
**Last Updated:** 01/11/2025  
**Time Invested:** ~16 hours (design, debug, testbench fixes, verification)

**Next Project:** Display expansion with external LEDs and OLED

---

_Part of FPGA Learning Journey - Building trading-relevant skills_
