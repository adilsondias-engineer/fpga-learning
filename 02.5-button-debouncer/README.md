# Button Debouncer - Dual Button LED Control

A robust button handler with separate ON/OFF buttons, demonstrating synchronization, debouncing, and edge detection - critical concepts for reliable FPGA designs.

## Overview

Physical buttons are electrically noisy - they "bounce" when pressed, creating multiple transitions instead of a clean on/off signal. Additionally, asynchronous signals crossing into the FPGA clock domain can cause metastability. This project implements a complete solution to both problems using **two independent buttons** for dedicated ON/OFF control.

## Hardware

- **Board:** Xilinx Arty A7-100T
- **FPGA:** Artix-7 XC7A100T
- **Clock:** 100 MHz system clock
- **Input:**
  - BTN0 (D9) - ON button
  - BTN1 (C9) - OFF button
- **Output:** LD0 (H5) - single LED

## What It Does

- Press BTN0 (ON button) - LED turns ON
- Press BTN1 (OFF button) - LED turns OFF

**Key Features:**

- Separate dedicated buttons for ON and OFF control
- One button press = One action (no multiple triggers from bouncing)
- Safe handling of asynchronous external signals
- Reliable operation regardless of press duration
- Production-ready debounce implementation
- Independent debouncing for each button

## Design Architecture

The design uses a 4-stage pipeline **for each button**:

```
Physical Buttons (ON/OFF)
    |
STAGE 1: Synchronizers (3 flip-flops each)
    | (Prevents metastability)
STAGE 2: Debouncers (20ms filter each)
    | (Removes mechanical bouncing)
STAGE 3: Edge Detectors (one per button)
    | (Triggers once per press, not continuous)
STAGE 4: LED Control Logic
    |
Clean, reliable output
```

### Stage 1: Synchronizer (Per Button)

```vhdl
-- Three-stage shift register for metastability protection
signal btn_on_sync : std_logic_vector(2 downto 0) := "000";
signal btn_off_sync : std_logic_vector(2 downto 0) := "000";

process(clk)
begin
    if rising_edge(clk) then
        btn_on_sync <= btn_on_sync(1 downto 0) & btn_in(0);
        btn_off_sync <= btn_off_sync(1 downto 0) & btn_in(1);
    end if;
end process;
```

**Why 3 stages?**

- Stage 1-2: Allows metastable signals to settle
- Stage 3: Clean, synchronized signal for logic use
- MTBF (Mean Time Between Failures) >> system lifetime

### Stage 2: Debouncer (Independent for Each Button)

```vhdl
constant DEBOUNCE_TIME : integer := 2_000_000;  -- 20ms at 100MHz
signal deboung_on_counter : unsigned(20 downto 0) := (others => '0');
signal deboung_off_counter : unsigned(20 downto 0) := (others => '0');
```

Each button has its own debounce counter. Requires signal to be stable for 20ms before accepting state change.

**Why 20ms?**

- Typical button bounce: 5-50ms
- 20ms filters out all mechanical noise
- Trade-off: responsiveness vs reliability

### Stage 3: Edge Detector (Per Button)

```vhdl
-- ON button edge detection
if btn_on_stable = '1' and btn_on_prev = '0' then
    btn_on_rising_edge <= '1';
end if;
btn_on_prev <= btn_on_stable;

-- OFF button edge detection
if btn_off_stable = '1' and btn_off_prev = '0' then
    btn_off_rising_edge <= '1';
end if;
btn_off_prev <= btn_off_stable;
```

**Critical:** Order matters! Reading before writing ensures correct edge detection.

### Stage 4: LED Control Logic

```vhdl
if btn_on_rising_edge = '1' and btn_off_rising_edge = '0' then
    led_state <= '1';  -- Turn ON
elsif btn_off_rising_edge = '1' and btn_on_rising_edge = '0' then
    led_state <= '0';  -- Turn OFF
else
    led_state <= led_state;  -- Maintain current state
end if;
```

Explicit ON/OFF control with priority handling (only one button action processed per cycle).

## Files

```
02.5-button-debouncer/
├── src/
│   ├── button_debouncer.vhd      # Main design with Generic for timing
│   └── button_debouncer_tb.vhd   # Comprehensive testbench
├── constraints/
│   └── Arty-A7-100-Master.xdc    # Pin assignments and timing
└── README.md                      # This file
```

## Design Parameters

| Parameter           | Value   | Configurable  | Notes                        |
| ------------------- | ------- | ------------- | ---------------------------- |
| Clock Frequency     | 100 MHz | No            | System clock                 |
| Debounce Time       | 20 ms   | Yes (Generic) | Adjustable via DEBOUNCE_TIME |
| Synchronizer Stages | 3       | No            | Industry standard (per btn)  |
| Simulation Debounce | 2 μs    | Yes (Generic) | For fast simulation          |
| Number of Buttons   | 2       | No            | ON and OFF                   |

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

- TEST 1: ON button press (LED turns on)
- TEST 2: OFF button press (LED turns off)
- TEST 3: Button bounce simulation (rapid noise filtered correctly)
- TEST 4: Multiple distinct presses (alternating ON/OFF sequences)

**Test Results:** All 4 tests pass with proper initialization.

## Key Signals for Waveform Analysis

Add these to waveform viewer to see each stage:

```tcl
# ON Button Path
add_wave {/button_debouncer_tb/btn_in_tb(0)}              # Raw ON button input
add_wave {/button_debouncer_tb/uut/btn_on_sync}           # ON synchronizer stages
add_wave {/button_debouncer_tb/uut/deboung_on_counter}    # ON debounce timer
add_wave {/button_debouncer_tb/uut/btn_on_stable}         # ON debounced signal
add_wave {/button_debouncer_tb/uut/btn_on_rising_edge}    # ON edge pulse

# OFF Button Path
add_wave {/button_debouncer_tb/btn_in_tb(1)}              # Raw OFF button input
add_wave {/button_debouncer_tb/uut/btn_off_sync}          # OFF synchronizer stages
add_wave {/button_debouncer_tb/uut/deboung_off_counter}   # OFF debounce timer
add_wave {/button_debouncer_tb/uut/btn_off_stable}        # OFF debounced signal
add_wave {/button_debouncer_tb/uut/btn_off_rising_edge}   # OFF edge pulse

# Output
add_wave {/button_debouncer_tb/led_out_tb}                # LED output
```

## Hardware Testing

### Pin Assignments

| Signal   | FPGA Pin | Board Label | Function     |
| -------- | -------- | ----------- | ------------ |
| clk      | E3       | CLK100MHZ   | System clock |
| btn_in(0)| D9       | BTN0        | ON button    |
| btn_in(1)| C9       | BTN1        | OFF button   |
| led_out  | H5       | LD0         | LED output   |

### Expected Behavior

1. Power on - LED off
2. Press BTN0 (ON) - LED turns on
3. Release BTN0 - LED stays on
4. Press BTN0 again - LED stays on (already on)
5. Press BTN1 (OFF) - LED turns off
6. Release BTN1 - LED stays off
7. Rapid button presses - Each press registers once (no double-triggers)

### Troubleshooting

**LED doesn't change:**

- Check correct buttons: BTN0 (D9) for ON, BTN1 (C9) for OFF
- Verify XDC constraints loaded
- Check bitstream programmed successfully

**LED changes multiple times per press:**

- Debounce time too short (increase DEBOUNCE_TIME)
- Check Generic is using default value (2_000_000)

**LED changes randomly:**

- Possible metastability (shouldn't happen with 3-stage sync)
- Check clock constraints in XDC

## Process Improvement

### Critical Bug Fixes During Development

**Bug #1: Uninitialized Testbench Signals**

**Original (incorrect):**

```vhdl
signal btn_in_tb : std_logic_vector(1 downto 0);  -- No initialization!
```

**Issue:** Signals start as 'U' (uninitialized), causing metastability propagation through synchronizers.

**Fixed:**

```vhdl
signal btn_in_tb : std_logic_vector(1 downto 0) := "00";  -- Initialize to known state
```

**Lesson:** Always initialize testbench signals to prevent 'U' propagation.

---

**Bug #2: Conflicting Button Presses in Testbench**

**Original (incorrect):**

```vhdl
-- Pressing both buttons simultaneously
btn_in_tb(1) <= '0';
btn_in_tb(0) <= '1';
wait for 3 us;
btn_in_tb(0) <= '0';
btn_in_tb(1) <= '1';  -- Both buttons transitioning together!
```

**Issue:** Both buttons changing state simultaneously creates race conditions and doesn't reflect real usage.

**Fixed:**

```vhdl
-- Press ON button only
btn_in_tb(0) <= '1';
wait for 3 us;
btn_in_tb(0) <= '0';
wait for 5 us;  -- Adequate settling time

-- Then press OFF button only
btn_in_tb(1) <= '1';
wait for 3 us;
btn_in_tb(1) <= '0';
```

**Lesson:** Testbenches should model realistic usage patterns - don't press multiple buttons simultaneously.

---

**Bug #3: Insufficient Settling Time**

**Original:** Wait times of 100ns-500ns between button releases and assertions

**Issue:** Insufficient time for debounce counter to reset and signals to stabilize.

**Fixed:** Increased wait times to 5μs (2.5× debounce period) between operations.

**Lesson:** Testbench timing must account for ALL signal propagation delays, not just the active operation time.

## Performance Metrics

| Metric                | Value           | Notes                                   |
| --------------------- | --------------- | --------------------------------------- |
| **Latency**           | 20-40ms         | Debounce time + synchronizer delay      |
| **Resource Usage**    | ~80 LUTs, ~70 FFs | Doubled for two independent button paths |
| **Maximum Frequency** | >400 MHz        | Single-cycle paths only                 |
| **MTBF**              | >10^10 hours    | With 3-stage synchronizer per button    |

## Advantages of Dual-Button Design

**Compared to toggle button:**

**Explicit control** - No ambiguity about LED state
**Easier testing** - Can directly command desired state
**Real-world applicability** - Many systems use separate ON/OFF controls
**Demonstrates parallelism** - Two independent signal paths
**No state tracking issues** - LED state doesn't depend on previous presses

**Use cases:**

- Power ON/OFF switches (explicit control preferred)
- Motor start/stop buttons (safety - explicit stop)
- System enable/disable controls
- Any application where explicit state control is required

## Future Enhancements

**Potential improvements:**

- [ ] Add reset input for system initialization
- [ ] Configurable debounce time via external input
- [ ] Support for more buttons (scalable array)
- [ ] LED brightness control (PWM output)
- [ ] Button hold detection (different behavior for long press)
- [ ] Priority override (e.g., OFF always takes precedence)
- [ ] LED blink pattern for visual feedback on button press

## Related Projects

- **Project 01:** Binary Counter with Reset - Basic FPGA flow and clock dividers
- **Project 02:** Button Debouncer (Toggle) - Single button toggle implementation

## Resources

**Key Concepts:**

- [Metastability and Synchronizers](https://www.xilinx.com) - Xilinx WP272
- Clock Domain Crossing techniques
- Debouncing algorithms
- Multi-button input handling

## Status

Design complete
Simulation verified (all 4 tests pass)
Synthesis successful
Implementation complete
Hardware verified on Arty A7-100T
Testbench bugs fixed (initialization, timing, button conflicts)

---

**Completed:** 28/10/2025
**Last Updated:** 28/10/2025
**Time Invested:** ~2 hours (design, debug, testbench fixes, verification)
**Key Learning:** Proper signal initialization and realistic testbench patterns are critical for reliable simulation

---

_Part of FPGA Learning Journey - Building trading-relevant skills_
