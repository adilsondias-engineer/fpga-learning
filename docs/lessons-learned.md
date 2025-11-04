## What I Learned so far
### FPGA Development Workflow

- Complete design -> simulation -> synthesis -> implementation -> hardware verification cycle
- Importance of setting correct top module for synthesis vs simulation (different "tops" for different purposes)
- Synthesis is for actual hardware designs only - testbenches cannot be synthesized
- Flash programming for autonomous boot on power-up
- Hardware verification is essential - testbenches complement but don't replace real testing

### Testbench Development

- Procedure placement: VHDL procedures must be declared in architecture declarative region (between architecture and begin), NOT inside processes
- Procedures declared in architecture can only be CALLED from processes, not DEFINED in them
- Self-checking testbenches with assert statements are more effective than manual waveform inspection
- Use shortened timing parameters (Generic mapping) for fast simulation vs hardware-accurate timing
- Reusable test procedures for common operations (encoder rotation, button presses)
- Test boundary conditions rather than exhaustive testing (test 0, 255, midpoint instead of all 256 values)

### Waveform Debugging Techniques

- Monitor multiple signals simultaneously to track data flow
- Use $monitor in testbenches for automatic change logging
- Identify metastability in waveforms (X or unknown states)
- Trace signal propagation through synchronizer chains
- Correlate simulation waveforms with hardware behavior

### Constraint Files (XDC)

- Single signal syntax: [get_ports signal_name]
- Vector syntax: [get_ports {vector_name[*]}] for all bits
- Individual vector bits: [get_ports {vector_name[0]}]
- Clock constraints with create_clock for timing analysis
- Pin mapping updates when changing physical connections (rotary encoder rewiring)

### Digital Design Fundamentals
#### Synchronous vs Asynchronous Reset

- Synchronous reset checked only on clock edge (safer for timing)
- Asynchronous reset responds immediately (better for emergency stops)
- Trade-off: timing closure vs responsiveness
- Most modern designs prefer synchronous reset

### Clock Domain Crossing (CDC)

- Critical: All asynchronous inputs MUST go through synchronizers
- Three-stage synchronizer is industry standard for metastability protection
- MTBF (Mean Time Between Failures) calculation depends on synchronizer stages
- CDC bugs can cause random, hard-to-reproduce failures in production

### Edge Detection

- Bug discovered: Order matters in sequential logic
- Must detect edge BEFORE updating previous state storage
- Ambiguous evaluation order can cause missed edges
- Correct pattern: read -> compare -> update

### Generic Parameters

- Design flexibility through configurable parameters
- DEBOUNCE_TIME for adjustable filtering periods
- FIFO_DEPTH for scalable buffer sizes
- Different values for simulation (fast) vs hardware (accurate)
- Enables IP reuse across different projects

### Component Design Patterns
#### Debouncing

- Mechanical switches bounce for 5-50ms typically
- 20ms debounce period filters all mechanical noise
- Counter-based implementation more reliable than sampling
- Must reset counter on any state change

### FIFO Buffers

- Circular buffer implementation with read/write pointers
- Full/empty flag generation from pointer comparison
- Careful handling of wrap-around conditions
- Synchronous read/write for predictable timing
- Critical for data flow control in streaming systems

### Rotary Encoder Decoding

- Quadrature encoding provides direction information
- Gray code sequence: only one bit changes at a time
- State machine decodes rotation direction
- Debouncing still required for mechanical encoders
- Edge detection on final stable state

### Bug Fixes During Development
#### Synthesis Attempting Testbench (Project 1)

- Error: [Synth 8-27] non-clocking wait statement not supported
- Cause: Testbench added to Design Sources instead of Simulation Sources
- Fix: Set design module as synthesis top, not testbench
- Lesson: Vivado's file organization matters - wrong placement causes cryptic errors

#### VHDL Procedure Syntax Errors (Project 4 Testbench)

- Error: syntax error near procedure and type error near ms
- Cause: Procedures defined inside process instead of architecture
- Fix: Move procedure declarations to architecture declarative region
- Lesson: VHDL has strict scoping rules for procedures

#### Edge Detection Timing (Project 2)

- Issue: LED toggle inconsistent, missed button presses
- Cause: Previous state updated before edge check
- Fix: Reorder to check edge first, then update state
- Lesson: Sequential statement order is critical in processes

#### Testbench Timing Failures (Project 2)

- Issue: Assertions failing despite correct logic
- Cause: Insufficient wait time after button release
- Fix: Increased wait times from 500ns to 5μs
- Lesson: Debouncer needs time to stabilize after input changes

### Hardware Integration Insights

- ChipKit headers provide flexible I/O expansion on Arty A7
- Pull-up resistors often needed for mechanical switches/encoders
- Breadboard connections can be unreliable - check continuity
- Color-coded wiring prevents confusion (red=power, black=ground, etc.)
- Current limiting resistors essential for LEDs (220Ω typical)

### Performance & Timing

- 100MHz system clock = 10ns period
- Timing closure becomes critical at high frequencies
- Setup/hold time violations cause intermittent failures
- Pipelining trades latency for throughput
- Register everything at module boundaries

### Vivado Tool Insights

- Behavioral simulation faster than post-implementation
- Synthesis optimizes away unused logic (can hide bugs)
- Implementation may fail even if synthesis succeeds (placement/routing)
- Critical warnings often indicate real problems
- ILA (Integrated Logic Analyzer) cores enable hardware debugging

### Documentation Best Practices

- Document bugs and fixes - shows learning mindset
- Include waveform screenshots with annotations
- Explain WHY not just WHAT in comments
- Create README with clear project structure
- Add interview talking points for portfolio projects

### Trading System Relevance

- FIFOs essential for packet buffering in network interfaces
- Metastability protection critical for asynchronous market data
- Low latency requires minimal logic levels
- Deterministic timing more important than average case
- Hardware timestamps need synchronized clocks
- Backpressure handling through full/empty flags

###  Key Conceptual Breakthroughs

- "You simulate signals, not physics" - Don't model LED photons or button mechanics
- "Synthesis is for hardware, simulation is for testing" - Testbenches are not synthesizable
- "Every async input is a potential failure point" - Never skip synchronizers
- "Edge detection is a pattern, not a primitive" - Must implement carefully
- "Timing is everything" - One clock cycle can make or break functionality
- "Signal assignments take effect NEXT clock cycle" - Reading immediately after assignment gives old value
- "Multiple processes see the same old values" - Cannot solve race conditions with flags between processes
- "One state machine is better than two" - Unified state machine eliminates inter-process race conditions

---

## Project 05: UART Transmitter with Binary Protocol

### VHDL Timing & Multi-Process Race Conditions

**Critical Discovery:** The most important lesson from this project - understanding VHDL signal timing and why multiple processes can't coordinate via flags.

#### Signal Assignment Timing
- Signal assignments in VHDL take effect at the **END** of the clock cycle
- Reading a signal immediately after assigning it returns the **old value**
- This is fundamental to how VHDL synchronous logic works
- Example:
  ```vhdl
  process(clk)
  begin
      if rising_edge(clk) then
          flag <= '1';           -- Assignment scheduled
          if flag = '1' then     -- Reads OLD value (still '0')!
              -- This won't execute until NEXT cycle
          end if;
      end if;
  end process;
  ```

#### Multi-Process Race Conditions
**Problem:** Two separate processes reading the same signals on the same clock edge will **always** see identical old values.

**Example of the Bug:**
```vhdl
-- Process 1: Protocol parser
process(clk)
begin
    if rising_edge(clk) then
        if rx_valid = '1' and rx_data = START_BYTE then
            protocol_active <= '1';  -- Set flag
            -- Parse protocol...
        end if;
    end if;
end process;

-- Process 2: ASCII echo handler
process(clk)
begin
    if rising_edge(clk) then
        if rx_valid = '1' and protocol_active = '0' then  -- Reads OLD value!
            -- Still sees '0' even though Process 1 set it to '1'
            -- RACE CONDITION: Both processes handle same byte!
        end if;
    end if;
end process;
```

**Why It Fails:**
- Both processes trigger on same rising_edge(clk)
- Both see `protocol_active = '0'` (the old value)
- Both processes execute their logic
- Flag update happens at END of cycle (too late)

**Failed Fix Attempts (4 total):**
1. **Added `protocol_active` flag** - Both processes saw old '0' value
2. **Removed redundant reset** - Same race condition persisted
3. **Checked `protocol_state` directly** - State transitions have 1-cycle delay
4. **Double-check (state AND flag)** - Same fundamental timing issue

**Successful Solution:** Unified State Machine
- Merged both processes into **single process**
- Single process reads `rx_data` and routes immediately
- No inter-process communication = no race condition

```vhdl
process(clk)
begin
    if rising_edge(clk) then
        case state is
            when WAIT_RX =>
                if rx_valid = '1' then
                    -- Check and route in SAME CYCLE
                    if rx_data = START_BYTE then
                        state <= PROTO_WAIT_CMD;  -- Binary protocol
                    else
                        -- Handle as ASCII command
                        case rx_data is
                            when X"52" => -- 'R' Reset
                            when X"49" => -- 'I' Increment
                            -- ... etc
                        end case;
                    end if;
                end if;
        end case;
    end if;
end process;
```

**Why This Works:**
- Single process makes routing decision immediately
- No waiting for signal updates from another process
- `rx_data` examined directly when `rx_valid` arrives
- Correct handling guaranteed in same cycle

**Key Insight:** Architectural problem requires architectural solution. Cannot fix multi-process race conditions with flags or checks - must eliminate the multiple processes.

### Binary Protocol Design (Trading-Style)

Implemented professional binary message protocol similar to exchange protocols (FIX, ITCH, OUCH):

**Message Format:**
```
[START_BYTE][CMD][LENGTH][DATA...][CHECKSUM]
   0xAA      u8    u8      N bytes    u8
```

**Checksum Calculation:**
```
CHECKSUM = CMD ⊕ LENGTH ⊕ DATA[0] ⊕ DATA[1] ⊕ ... ⊕ DATA[N-1]
```

**Protocol State Machine:**
- `WAIT_RX` - Waiting for START_BYTE (0xAA)
- `PROTO_WAIT_CMD` - Reading command byte
- `PROTO_WAIT_LEN` - Reading length byte
- `PROTO_WAIT_DATA` - Reading N data bytes
- `PROTO_WAIT_CSUM` - Validating checksum
- `PROTO_PROCESS` - Executing validated command

**Commands Implemented:**
- `0x01` - Set counter (LENGTH=1, DATA=value)
- `0x02` - Add to counter (LENGTH=1, DATA=value)
- `0x03` - Query counter (LENGTH=0, returns 2-byte hex ASCII)
- `0x04` - Write to FIFO (LENGTH=N, DATA=bytes)
- `0x05` - Read from FIFO (LENGTH=0, transmits all queued data)

**Trading Relevance:**
- **Framing:** START_BYTE enables resynchronization after errors
- **Length-prefixed:** Variable-length messages (like market data updates)
- **Checksums:** Data integrity critical in trading (detects transmission errors)
- **Binary format:** More efficient than ASCII (bandwidth matters)
- **State machine:** Professional approach to protocol parsing

### UART Communication Best Practices

**Baud Rate Generation:**
- 100MHz clock -> 115200 baud
- Clock division: 100,000,000 / 115,200 ≈ 868 cycles per bit
- Mid-bit sampling: Sample at cycle 434 for noise immunity

**Handshake Flags:**
- `tx_busy` flag indicates transmission in progress
- `tx_started` flag for proper wait-for-start-then-complete pattern

**Correct Handshake Pattern:**
```vhdl
when ECHO_TX =>
    if tx_busy = '1' then
        tx_started <= '1';  -- Mark transmission started
    elsif tx_started = '1' and tx_busy = '0' then
        -- Transmission completed
        tx_started <= '0';
        state <= WAIT_RX;
    end if;
```

**Wrong Pattern (Bug):**
```vhdl
when ECHO_TX =>
    if tx_busy = '0' then  -- WRONG! Might read '0' before '1'
        state <= WAIT_RX;  -- Transition too early!
    end if;
```

### RGB LED Pulse Stretching

**Problem:** Brief signals invisible to human eye
- Red LED (`rx_valid`): Only 10ns @ 100MHz - invisible
- Green LED (`tx_busy`): ~87μs per byte - barely visible flash
- Blue LED (idle): Constant - always on (no indication of activity)

**Solution:** 100ms pulse stretchers
```vhdl
-- 100ms @ 100MHz = 10,000,000 cycles
constant LED_STRETCH_TIME : integer := 10_000_000;
signal led_r_stretch : integer range 0 to LED_STRETCH_TIME := 0;

process(clk)
begin
    if rising_edge(clk) then
        -- Stretch rx_valid pulse
        if rx_valid = '1' then
            led_r_stretch <= LED_STRETCH_TIME;  -- Start 100ms timer
        elsif led_r_stretch > 0 then
            led_r_stretch <= led_r_stretch - 1;  -- Count down
        end if;
    end if;
end process;

-- LED assignment
led0_r <= '1' when led_r_stretch > 0 else '0';
```

**Result:**
- Red visible for 100ms when receiving
- Green visible for 100ms when transmitting
- Blue only when truly idle (not receiving/transmitting)
- Clear visual feedback for protocol activity

### Protocol State Management Bug

**Bug:** Query command (`0x03`) only returned 1 hex digit instead of 2.

**Root Cause:** Conditional state check at end of PROTO_PROCESS state:
```vhdl
when PROTO_PROCESS =>
    case protocol_cmd is
        when X"03" =>  -- Query
            tx_data <= nibble_to_hex(value_counter(7 downto 4));
            tx_start <= '1';
            state <= ECHO_TX;  -- Set state to send both digits
        -- ... other commands
    end case;

    -- WRONG: This always executes because state still = PROTO_PROCESS!
    if state = PROTO_PROCESS then
        state <= WAIT_RX;  -- Overwrites the ECHO_TX above!
    end if;
```

**Why It Failed:**
- `state` still holds old value `PROTO_PROCESS` during same cycle
- Condition `state = PROTO_PROCESS` always TRUE
- Overwrites the `state <= ECHO_TX` assignment
- Query command skips sending second hex digit

**Fix:** Explicit state transitions for each command branch
```vhdl
when PROTO_PROCESS =>
    protocol_data_buffer <= (others => '0');  -- Clear buffer

    case protocol_cmd is
        when X"01" =>  -- Set counter
            value_counter <= unsigned(protocol_data_buffer(7 downto 0));
            state <= WAIT_RX;  -- Explicit transition

        when X"03" =>  -- Query counter
            tx_data <= nibble_to_hex(value_counter(7 downto 4));
            tx_start <= '1';
            state <= ECHO_TX;  -- Explicit transition - not overwritten!

        when others =>
            state <= WAIT_RX;
    end case;
```

### Python Test Automation

**Created automated test script** for protocol validation:
```python
import serial

ser = serial.Serial('COM7', 115200)

# Set counter to 0x10
msg = bytes([0xAA, 0x01, 0x01, 0x10, 0x10])
ser.write(msg)

# Query counter (should return "10")
msg = bytes([0xAA, 0x03, 0x00, 0x03])
ser.write(msg)
response = ser.read(2)

if response == b'10':
    print("PASS")
else:
    print(f"FAIL - Got {response}")
```

**Benefits:**
- Faster than manual testing
- Repeatable test cases
- Clear pass/fail criteria
- Regression testing capability
- Validates checksum calculation
- Tests multiple commands in sequence

### Hex Output Conversion

**Implemented nibble-to-ASCII conversion function:**
```vhdl
function nibble_to_hex(nibble : std_logic_vector(3 downto 0))
    return std_logic_vector is
begin
    case nibble is
        when X"0" => return X"30";  -- '0'
        when X"1" => return X"31";  -- '1'
        when X"2" => return X"32";  -- '2'
        -- ... X"3" through X"9"
        when X"A" => return X"41";  -- 'A'
        when X"B" => return X"42";  -- 'B'
        -- ... through X"F" = X"46" ('F')
    end case;
end function;
```

**Usage:**
```vhdl
-- Send high nibble of value_counter as ASCII hex
tx_data <= nibble_to_hex(value_counter(7 downto 4));

-- Example: value_counter = 0x5A
-- High nibble (7 downto 4) = 0x5
-- nibble_to_hex(0x5) = 0x35 = ASCII '5'
-- Low nibble (3 downto 0) = 0xA
-- nibble_to_hex(0xA) = 0x41 = ASCII 'A'
-- Result: "5A" sent to terminal
```

### Multi-Protocol Support

**Designed system to handle two protocols simultaneously:**
1. **Binary Protocol** (efficient, production-style)
   - START_BYTE detection (0xAA)
   - Length-prefixed messages
   - Checksum validation
   - Commands: Set, Add, Query, FIFO operations

2. **ASCII Protocol** (human-readable, debugging)
   - Single-character commands
   - 'R' = Reset, 'I' = Increment, 'D' = Decrement
   - 'Q' = Query (returns hex), 'S' = Status, 'G' = Get FIFO

**Routing Logic:**
```vhdl
if rx_data = START_BYTE then
    state <= PROTO_WAIT_CMD;  -- Binary protocol path
else
    case rx_data is          -- ASCII command path
        when X"52" => -- 'R'
        when X"49" => -- 'I'
        -- ... etc
    end case;
end if;
```

**Benefits:**
- Production binary protocol for efficiency
- ASCII fallback for debugging
- Educational: shows both approaches
- Mirrors real systems (control plane ASCII, data plane binary)

---
This document grows with each project. Latest update includes Projects 1-5.
