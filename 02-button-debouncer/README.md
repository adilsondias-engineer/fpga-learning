# Button Debouncer with Metastability Protection

A robust button handler demonstrating synchronization, debouncing, and edge detection - critical concepts for reliable FPGA designs.

## Overview

Physical buttons are electrically noisy - they "bounce" when pressed, creating multiple transitions instead of a clean on/off signal. Additionally, asynchronous signals crossing into the FPGA clock domain can cause metastability. This project implements a complete solution to both problems.

## Hardware

- **Board:** Xilinx Arty A7-100T
- **FPGA:** Artix-7 XC7A100T
- **Clock:** 100 MHz system clock
- **Input:** BTN0 (physical button)
- **Output:** LD0 (single LED)

## What It Does

Press the button → LED toggles ON/OFF

**Key Features:**

- One button press = One toggle (no multiple triggers from bouncing)
- Safe handling of asynchronous external signals
- Reliable operation regardless of press duration
- Production-ready debounce implementation

## Design Architecture

The design uses a 4-stage pipeline:

```
Physical Button
    ↓
STAGE 1: Synchronizer (3 flip-flops)
    ↓ (Prevents metastability)
STAGE 2: Debouncer (20ms filter)
    ↓ (Removes mechanical bouncing)
STAGE 3: Edge Detector
    ↓ (Triggers once per press, not continuous)
STAGE 4: LED Toggle
    ↓
Clean, reliable output
```

### Stage 1: Synchronizer

```vhdl
-- Three-stage shift register for metastability protection
signal btn_sync : STD_LOGIC_VECTOR(2 downto 0) := "000";

process(clk)
begin
    if rising_edge(clk) then
        btn_sync <= btn_sync(1 downto 0) & btn_in;
    end if;
end process;
```

**Why 3 stages?**

- Stage 1-2: Allows metastable signals to settle
- Stage 3: Clean, synchronized signal for logic use
- MTBF (Mean Time Between Failures) >> system lifetime

### Stage 2: Debouncer

```vhdl
constant DEBOUNCE_TIME : integer := 2_000_000;  -- 20ms at 100MHz
```

Requires signal to be stable for 20ms before accepting state change.

**Why 20ms?**

- Typical button bounce: 5-50ms
- 20ms filters out all mechanical noise
- Trade-off: responsiveness vs reliability

### Stage 3: Edge Detector

```vhdl
-- Detect rising edge BEFORE updating previous state
if btn_stable = '1' and btn_prev = '0' then
    btn_rising_edge <= '1';
else
    btn_rising_edge <= '0';
end if;
btn_prev <= btn_stable;
```

**Critical:** Order matters! Reading before writing ensures correct edge detection.

### Stage 4: LED Toggle

```vhdl
if btn_rising_edge = '1' then
    led_state <= not led_state;
end if;
```

Simple state toggle on each detected button press.

## Files

```
02-button-debouncer/
├── src/
│   ├── button_debouncer.vhd      # Main design with Generic for timing
│   └── button_debouncer_tb.vhd   # Comprehensive testbench
├── constraints/
│   └── arty_a7_100t.xdc          # Pin assignments and timing
├── docs/
│   └── waveform_analysis.wcfg     # Simulation showing all stages
└── README.md                      # This file
```

## Design Parameters

| Parameter           | Value   | Configurable  | Notes                        |
| ------------------- | ------- | ------------- | ---------------------------- |
| Clock Frequency     | 100 MHz | No            | System clock                 |
| Debounce Time       | 20 ms   | Yes (Generic) | Adjustable via DEBOUNCE_TIME |
| Synchronizer Stages | 3       | No            | Industry standard            |
| Simulation Debounce | 2 μs    | Yes (Generic) | For fast simulation          |

## Simulation

### Fast Simulation Mode

For rapid testing, use shortened debounce time:

```vhdl
uut: button_debouncer
    generic map (
        DEBOUNCE_TIME => 200  -- 2μs for simulation
    )
```

**Simulation time:** ~150μs (5 seconds on typical PC)

### Full Timing Simulation

For hardware-accurate testing, use default Generic:

```vhdl
uut: button_debouncer
    generic map (
        DEBOUNCE_TIME => 2_000_000  -- 20ms (real hardware timing)
    )
```

**Simulation time:** ~400ms (2-5 minutes on typical PC)

### Running Simulation

```tcl
# In Vivado Tcl Console
restart
run all
```

### Test Coverage

The testbench covers:

- ✅ Basic toggle functionality (press → LED changes)
- ✅ Debounce filtering (rapid bounces ignored)
- ✅ Edge detection (held button doesn't continuously trigger)
- ✅ Multiple sequential presses (5 rapid presses all counted)
- ✅ Timing verification (debounce period enforced)

**Test Results:** All 4 tests pass with fast simulation timing.

## Key Signals for Waveform Analysis

Add these to waveform viewer to see each stage:

```tcl
add_wave {/button_debouncer_tb/btn_tb}                    # Raw button input
add_wave {/button_debouncer_tb/uut/btn_sync}              # Synchronizer stages
add_wave {/button_debouncer_tb/uut/debounce_counter}      # Debounce timer
add_wave {/button_debouncer_tb/uut/btn_stable}            # Debounced signal
add_wave {/button_debouncer_tb/uut/btn_rising_edge}       # Edge pulse
add_wave {/button_debouncer_tb/led_tb}                    # LED output
```

## Hardware Testing

### Expected Behavior

1. Power on → LED off
2. Press BTN0 → LED turns on
3. Release BTN0 → LED stays on
4. Press BTN0 again → LED turns off
5. Rapid button presses → Each press toggles LED once (no double-triggers)

### Troubleshooting

**LED doesn't change:**

- Check button is BTN0 (D9 pin)
- Verify XDC constraints loaded
- Check bitstream programmed successfully

**LED changes multiple times per press:**

- Debounce time too short (increase DEBOUNCE_TIME)
- Check Generic is using default value (2_000_000)

**LED changes randomly:**

- Possible metastability (shouldn't happen with 3-stage sync)
- Check clock constraints in XDC

## Lessons Learned

### Bug Fixes During Development

**Bug #1: Edge Detection Order**

**Original (incorrect):**

```vhdl
btn_prev <= btn_stable;  -- Updates first
if btn_stable = '1' and btn_prev = '0' then  -- Reads after
```

**Issue:** Potential evaluation order ambiguity.

**Fixed:**

```vhdl
if btn_stable = '1' and btn_prev = '0' then  -- Read first
    btn_rising_edge <= '1';
end if;
btn_prev <= btn_stable;  -- Update last
```

**Lesson:** In edge detection, always READ before WRITE for clear execution order.

**Bug #2: Insufficient Wait Times in Testbench**

**Original:** Wait times of 500ns-1μs between tests

**Issue:** Insufficient time for debouncer to process button release before next press.

**Fixed:** Increased wait times to 5μs (2.5× debounce period)

**Lesson:** Testbench timing must account for all signal propagation delays.

## Performance Metrics

| Metric                | Value           | Notes                              |
| --------------------- | --------------- | ---------------------------------- |
| **Latency**           | 20-40ms         | Debounce time + synchronizer delay |
| **Resource Usage**    | 42 LUTs, 35 FFs | Minimal footprint                  |
| **Maximum Frequency** | >400 MHz        | Single-cycle paths only            |
| **MTBF**              | >10^10 hours    | With 3-stage synchronizer          |

## Future Enhancements

**Potential improvements:**

- [ ] Add reset input for system initialization
- [ ] Configurable debounce time via external input
- [ ] Multiple button support (array of inputs)
- [ ] Debounce time adaptation based on detected bounce frequency
- [ ] LED brightness control (PWM output)
- [ ] Button hold detection (different behavior for long press)

## Resources

**Key Concepts:**

- [Metastability and Synchronizers](https://www.xilinx.com) - Xilinx WP272
- Clock Domain Crossing techniques
- Debouncing algorithms

**Related Projects:**

- Project 1: Binary Counter (basic FPGA flow)
- Project 2.5: 2 Buttons to handle the LED, 1 button only turn it on and the other button only turn it off

## Status

✅ Design complete
✅ Simulation verified (all tests pass)
✅ Synthesis successful
✅ Implementation complete
✅ Hardware verified on Arty A7-100T
✅ Flash programmed - boots autonomously

---

**Completed:** 28/10/2025
**Time Invested:** ~1.5 hours (design, debug, test, verify)
**Key Learning:** Metastability protection is non-negotiable in production FPGA designs

---

_Part of FPGA Learning Journey - Building trading-relevant skills_
