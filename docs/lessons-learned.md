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

## Project 06: UDP Packet Parser - MII Ethernet Receiver

### Critical Lesson: Documentation BEFORE Implementation

**Major Mistake:** Initially implemented RGMII interface when hardware requires MII.

**Time Wasted:** 4+ hours implementing wrong interface
- 2 hours RGMII implementation
- 1.5 hours debugging
- 15 minutes identifying root cause

**Root Cause:** Insufficient hardware verification before implementation

**What Should Have Been Done:**
1. Read Arty A7 Reference Manual (Section 6: Ethernet PHY)
2. Check PHY part number (DP83848J datasheet)
3. Verify interface type (MII, not RGMII)
4. Review master XDC for pin assignments
5. THEN begin implementation

**Lesson Learned:** **Documentation -> Planning -> Coding**
- 30 minutes of documentation review prevents hours of wasted implementation
- Hardware specifications are non-negotiable - software assumptions don't apply
- Always verify PHY capabilities before selecting interface protocol

### MII vs RGMII Comparison

**Key Differences:**

| Specification    | MII (Required)      | RGMII (Wrong)       |
| ---------------- | ------------------- | ------------------- |
| Speed            | 10/100 Mbps         | 1000 Mbps           |
| Data Width       | 4-bit               | 4-bit               |
| Data Rate        | SDR (rising edge)   | DDR (both edges)    |
| Clock Frequency  | 25 MHz / 2.5 MHz    | 125 MHz             |
| Clock Source     | PHY -> FPGA         | FPGA -> PHY         |
| Reference Clock  | FPGA -> PHY         | None                |
| Pin Count        | ~18 signals         | ~12 signals         |
| Compatible PHY   | DP83848J            | RTL8211E, etc.      |

**Arty A7 Hardware:**
- PHY: Texas Instruments DP83848J
- Interface: MII only (10/100 Mbps)
- No RGMII support

### MII Interface Implementation

**Clock Architecture (Critical Understanding):**

```
FPGA generates:  25 MHz -> eth_ref_clk -> PHY X1 pin (reference clock)

PHY generates:   25 MHz -> eth_rx_clk -> FPGA (RX data sampling clock)
                 25 MHz -> eth_tx_clk -> FPGA (TX data clocking)
```

**This is OPPOSITE of RGMII!**
- RGMII: FPGA drives TX_CLK and RX_CLK
- MII: PHY provides both data clocks, FPGA provides reference

### PLL/MMCM Clock Generation

**Challenge:** Generate 25 MHz reference clock from 100 MHz system clock

**Solution:** PLLE2_BASE primitive (Xilinx 7-Series)

```vhdl
PLLE2_BASE
    generic map (
        CLKFBOUT_MULT   => 8,        -- 100 MHz * 8 = 800 MHz (VCO)
        CLKOUT0_DIVIDE  => 32,       -- 800 MHz / 32 = 25 MHz
        CLKIN1_PERIOD   => 10.0,     -- 100 MHz input (10ns period)
        DIVCLK_DIVIDE   => 1,
        STARTUP_WAIT    => "FALSE"   -- STRING literal, not boolean!
    )
    port map (
        CLKIN1   => CLK,             -- 100 MHz system clock
        CLKFBOUT => clkfb,
        CLKFBIN  => clkfb,
        CLKOUT0  => eth_ref_clk_unbuf,
        LOCKED   => pll_locked,
        PWRDWN   => '0',
        RST      => '0'
    );
```

**Critical Bug - Xilinx Primitive Parameters:**
- **WRONG:** `STARTUP_WAIT => FALSE` (boolean)
- **CORRECT:** `STARTUP_WAIT => "FALSE"` (string literal)
- Error: "type error near false; current type boolean; expected type string"
- **Lesson:** Xilinx primitives require STRING LITERALS for generic parameters
- Always check UG953 (Vivado 7 Series Libraries Guide)

### PHY Reset Timing

**DP83848J Datasheet Requirement:** Minimum 10ms reset pulse

**Implementation:**
```vhdl
-- Counter for 20ms @ 100MHz = 2,000,000 cycles
signal reset_counter : unsigned(23 downto 0) := (others => '0');

process(clk_100mhz)
begin
    if rising_edge(clk_100mhz) then
        if btn_reset = '1' then
            reset_counter <= (others => '0');
            reset_sync <= '1';
        elsif reset_counter < 2_000_000 then
            reset_counter <= reset_counter + 1;
            reset_sync <= '1';
        else
            reset_sync <= '0';
        end if;
    end if;
end process;

eth_rst_n <= not reset_sync;  -- PHY reset is active LOW
```

**Lesson:**
- Add safety margin (20ms when 10ms required)
- Use counter at known frequency for accurate timing
- Improper reset prevents PHY link establishment
- PHY won't function without proper reset sequence

### Preamble/SFD Stripping (Critical for MII)

**Problem:** MII receiver passes preamble bytes to FPGA

**Ethernet Frame Structure:**
```
Preamble (7 bytes): 0x55 0x55 0x55 0x55 0x55 0x55 0x55
SFD (1 byte):       0xD5 (Start Frame Delimiter)
Dest MAC (6 bytes): 0x00 0x0A 0x35 0x02 0xAF 0x9A
Src MAC (6 bytes):  ...
Type (2 bytes):     0x08 0x00 (IPv4)
Payload:            ...
FCS (4 bytes):      Frame Check Sequence
```

**Bug:** MAC parser expected destination MAC as first byte, but received preamble

**Symptom:** LEDs stuck at 0000 despite link established and frames transmitted

**Root Cause Analysis:**
1. Wireshark confirmed frames sent correctly
2. Link LEDs showed PHY connection established
3. FPGA not incrementing frame counter
4. Traced data path: PHY -> mii_rx -> mac_parser
5. Realized: MII passes preamble, RMII/RGMII strip it

**Solution:** SFD Detection in mii_rx.vhd

```vhdl
signal sfd_detected : std_logic := '0';

process(eth_rx_clk)
begin
    if rising_edge(eth_rx_clk) then
        if rx_dv = '1' then
            -- Detect SFD (0xD5)
            if rx_data = X"D5" then
                sfd_detected <= '1';
            end if;

            -- Only output data AFTER SFD
            if sfd_detected = '1' and rx_data /= X"D5" then
                data_out <= rx_data;
                data_valid <= '1';
            end if;
        else
            sfd_detected <= '0';  -- Reset on frame end
        end if;
    end if;
end process;
```

**Lesson:**
- Different PHY interfaces handle framing differently
- MII: FPGA must strip preamble/SFD
- RMII/RGMII: PHY may strip automatically (check datasheet!)
- Always verify byte-level frame structure
- IEEE 802.3 specification is authoritative

### MAC Address Filtering

**Purpose:** Only process frames addressed to FPGA

**Target MAC:** `00:0a:35:02:af:9a` (Digilent OUI + board serial)

**Implementation:**
```vhdl
constant FPGA_MAC : std_logic_vector(47 downto 0) := X"000a3502af9a";
signal mac_match : std_logic;

-- Receive destination MAC (first 6 bytes)
case byte_count is
    when 0 => dest_mac(47 downto 40) <= rx_data;
    when 1 => dest_mac(39 downto 32) <= rx_data;
    when 2 => dest_mac(31 downto 24) <= rx_data;
    when 3 => dest_mac(23 downto 16) <= rx_data;
    when 4 => dest_mac(15 downto 8)  <= rx_data;
    when 5 => dest_mac(7 downto 0)   <= rx_data;
              -- Check match after last byte
              if dest_mac(47 downto 8) & rx_data = FPGA_MAC then
                  mac_match <= '1';
              else
                  mac_match <= '0';  -- Reject frame
              end if;
end case;

-- Also accept broadcast
if dest_mac = X"ffffffffffff" then
    mac_match <= '1';
end if;
```

**Testing:**
- Frames to FPGA_MAC: Accepted, LEDs increment
- Frames to wrong MAC: Rejected, no increment
- Broadcast frames: Accepted

### Clock Domain Crossing (25 MHz -> 100 MHz)

**Challenge:** `frame_valid` pulse generated in 25 MHz domain, stats counter in 100 MHz domain

**Solution:** 2-Flip-Flop Synchronizer

```vhdl
signal frame_valid_sync1 : std_logic := '0';
signal frame_valid_sync2 : std_logic := '0';

process(clk_100mhz)
begin
    if rising_edge(clk_100mhz) then
        frame_valid_sync1 <= frame_valid_cdc;  -- First FF
        frame_valid_sync2 <= frame_valid_sync1; -- Second FF (stable)
    end if;
end process;

-- Use sync2 for counter increment
```

**Timing Constraints (XDC):**
```tcl
set_max_delay -from [get_clocks eth_rx_clk] -to [get_clocks sys_clk] 40.0
set_max_delay -from [get_clocks sys_clk] -to [get_clocks eth_rx_clk] 10.0
```

**Lesson:**
- 2FF synchronizer is minimum for CDC
- First FF may go metastable
- Second FF guarantees stability
- Proper timing constraints essential
- Same pattern used in Project 2 (button debouncer)

### Python/Scapy Testing

**Test Script:** Send raw Ethernet frames directly to FPGA MAC

```python
from scapy.all import Ether, sendp

FPGA_MAC = "00:0a:35:02:af:9a"
frame = Ether(dst=FPGA_MAC, src=MY_MAC, type=0x0800) / b"Hello FPGA!"
sendp(frame, iface="Ethernet 17", count=10, verbose=False)
```

**Benefits:**
- Bypasses OS network stack
- Full control over frame contents
- Can test MAC filtering, broadcasts, malformed frames
- Real hardware validation

**Testing Scenarios:**
1. Correct MAC -> LEDs increment
2. Wrong MAC -> LEDs don't change
3. Broadcast -> LEDs increment
4. Various frame sizes (64 to 1518 bytes)
5. Burst testing (100 frames rapidly)

### Nibble-to-Byte Assembly

**MII Interface:** 4-bit nibbles @ 25 MHz

**Assembly Logic:**
```vhdl
signal nibble_count : std_logic := '0';
signal byte_lower   : std_logic_vector(3 downto 0);

process(eth_rx_clk)
begin
    if rising_edge(eth_rx_clk) then
        if rx_dv = '1' then
            if nibble_count = '0' then
                byte_lower <= rxd;     -- Store lower nibble
                nibble_count <= '1';
            else
                -- Upper nibble received, output complete byte
                data_out <= rxd & byte_lower;  -- Concatenate
                data_valid <= '1';
                nibble_count <= '0';
            end if;
        end if;
    end if;
end process;
```

**Bit Ordering:** Network byte order (big-endian)
- First nibble received = bits [3:0]
- Second nibble received = bits [7:4]

### Module Hierarchy

```
mii_eth_top
├── PLLE2_BASE (100 MHz -> 25 MHz reference clock)
├── mii_rx (MII receiver - nibble assembly, SFD detection)
├── mac_parser (MAC frame parser with filtering)
├── 2FF synchronizer (25 MHz -> 100 MHz CDC)
└── stats_counter (LED display + activity indicator)
```

**Clean separation of concerns:**
- mii_rx: Physical layer (nibble assembly, preamble stripping)
- mac_parser: Data link layer (MAC filtering, frame validation)
- stats_counter: Application layer (counting, display)

### Timing Analysis Results

**WNS (Worst Negative Slack):** +7.234 ns (PASSING)
**TNS (Total Negative Slack):** 0 ns
**Setup/Hold:** All constraints met

**Critical Path:** eth_rx_clk to sys_clk crossing
- Properly constrained with set_max_delay
- 2FF synchronizer adds latency but guarantees stability

### Hardware Verification

**Visual Confirmation:**
1. Blue LED ON after 5 seconds (PHY reset complete)
2. RJ45 link LEDs illuminate (PHY negotiated link)
3. LEDs count frames in binary (LD0-LD2)
4. Green LED pulses on frame reception

**Wireshark Validation:**
- Confirmed frames transmitted correctly
- Destination MAC matches FPGA
- Source MAC shows PC adapter
- Frame structure correct per IEEE 802.3

**LED Counter Test:**
- Send 1 frame: LEDs show 0001
- Send 10 frames: LEDs show 1010 (wraps to lower 3 bits)
- Send 100 frames: LEDs show 100 (mod 8 = 4)

### Process Improvements Implemented

**New Development Workflow:**
1. **Documentation Review** (30 min) - Read reference manuals, datasheets
2. **Planning** (15 min) - Module hierarchy, interfaces, constraints
3. **Coding** (2-3 hours) - Implementation with proper synchronizers
4. **Hardware Testing** (30 min) - Real board verification

**Old (Wrong) Workflow:**
1. Make assumptions about hardware
2. Start coding immediately
3. Debug for hours when it doesn't work
4. Finally read documentation and discover wrong interface

**Time Saved:** Hours of debugging prevented by upfront documentation review

### Trading System Relevance

**Market Data Reception:**
- Direct PHY interfacing = minimal latency
- Bypasses OS network stack completely
- MAC filtering reduces processing load
- Hardware timestamps possible (next phase)

**Packet Processing:**
- Preamble stripping at wire speed
- Immediate MAC filtering (not CPU-based)
- Dedicated state machines for protocol parsing
- Deterministic latency (no OS scheduling)

**Next Steps (Phase 1B):**
- IP header parsing
- UDP packet extraction
- Hardware timestamping (sub-microsecond precision)
- MDIO interface for PHY register access

---

## Project 06 Phase 1F: Bug #13 - Critical CDC Issues & Real-Time Architecture

### ⭐ The Most Important Lesson: Clock Domain Crossing Can Break Working Designs

**Context:** IP parser worked perfectly (ip=1, proto=11), but UDP parser consistently failed (udp=0). This was Bug #13 - a race condition caused by CDC violations that took significant debugging to identify and resolve.

### Bug #13: UDP Parser Race Condition (99% Failure Rate)

**Initial Symptoms:**
```
Terminal Output: MAC: frame fr=1 ip=1 udp=0 pend=-- ver=0 ihl=0 csum=0 b14=45 proto=11
                      ^^^^^^^^^^^^ IP parsing works   ^^^^ UDP parsing fails
```

**Root Cause Analysis Timeline:**

1. **First Discovery:** Event-driven UDP parser triggered on `ip_valid` pulse
2. **Debug Investigation:** Added debug outputs (proto=, upok=, ulok=, frm=)
3. **Race Condition Revealed:**
   - UDP parser triggered at byte 37 (when `ip_valid` pulsed)
   - UDP header bytes 34-41 already passed by that time
   - State machine entered PARSE_HEADER too late to capture data
   - Success rate: ~1% (only when timing accidentally aligned)

**Timing Diagram of the Failure:**
```
Byte Index:  23    24-33       34   35   36   37        38-41
             ↓     ↓           ↓    ↓    ↓    ↓         ↓
IP Parse:    proto VALIDATE    ─────────────> ip_valid (pulse)
UDP Parse:   idle  idle        idle idle idle START     Too late!
                                ^^^^^^^^^^^^^^^^^^^
                                UDP header bytes missed
```

**Failed Fix Attempts:**
1. Trigger window `byte_index >= 24 and < 34` → 100% failure (too early)
2. Trigger window `byte_index >= 23 and < 34` → Still mostly 0% (timing off)
3. Trigger window `byte_index >= 23` (no upper bound) → ~1% success (race persists)

**Successful Solution:** Complete architectural rewrite from event-driven to real-time.

### Real-Time vs Event-Driven Parser Architecture

**❌ Event-Driven (v3b - FAILED):**
```vhdl
-- Wait for signal, then try to capture bytes
when IDLE =>
    if ip_valid = '1' then  -- Signal arrives too late!
        state <= PARSE_HEADER;
    end if;

when PARSE_HEADER =>
    -- By now, UDP header bytes already passed
    if byte_index = UDP_HEADER_START + header_byte_count then
        case header_byte_count is
            when 0 => src_port_reg(15 downto 8) <= data_in;  -- MISSED!
```

**✅ Real-Time (v5 - SUCCESS):**
```vhdl
-- Trigger at exact byte position
when IDLE =>
    if frame_valid = '1' and byte_index = UDP_HEADER_START then  -- Byte 34
        state <= PARSE_HEADER;
    end if;

when PARSE_HEADER =>
    -- Capture bytes in real-time as they arrive
    if byte_index = (UDP_HEADER_START + header_byte_count) then
        case header_byte_count is
            when 0 => src_port_reg(15 downto 8) <= data_in;  -- ✓ Captured!
            when 1 => src_port_reg(7 downto 0) <= data_in;
            when 2 => dst_port_reg(15 downto 8) <= data_in;
            when 3 => dst_port_reg(7 downto 0) <= data_in;
            when 4 => length_reg(15 downto 8) <= data_in;
            when 5 => length_reg(7 downto 0) <= data_in;
            when 6 => checksum_reg(15 downto 8) <= data_in;
            when 7 =>
                checksum_reg(7 downto 0) <= data_in;
                state <= VALIDATE;  -- All 8 bytes captured!
```

**Key Differences:**

| Aspect | Event-Driven (v3b) | Real-Time (v5) |
|--------|-------------------|----------------|
| **Trigger** | Waits for `ip_valid` signal | Triggers at `byte_index = 34` |
| **Timing** | Arrives too late (byte 37) | Exact position (byte 34) |
| **Success Rate** | ~1% (race condition) | 100% (deterministic) |
| **Code Size** | 280+ lines | 188 lines |
| **States** | 5 states | 4 states (simplified) |
| **Complexity** | Complex triggering logic | Simple byte-position logic |

**Results:**
- v3b: 1% success rate → v5: 100% success rate
- Reduced code size: 280+ lines → 188 lines
- Eliminated race condition entirely
- Production-ready reliability

### Clock Domain Crossing (CDC) - Production Patterns

**Challenge:** Signals crossing from 25 MHz (eth_rx_clk) to 100 MHz (clk) domain can cause metastability.

**Critical CDC Fixes Applied:**

#### 1. Reset Synchronization (NEW in v5)
```vhdl
-- Reset synchronizer for 25 MHz domain
signal mdio_rst_rxclk_sync1 : std_logic := '1';
signal mdio_rst_rxclk_sync2 : std_logic := '1';
signal mdio_rst_rxclk       : std_logic := '1';

process(eth_rx_clk)
begin
    if rising_edge(eth_rx_clk) then
        mdio_rst_rxclk_sync1 <= reset;
        mdio_rst_rxclk_sync2 <= mdio_rst_rxclk_sync1;
        mdio_rst_rxclk       <= mdio_rst_rxclk_sync2;
    end if;
end process;
```

**Lesson:** Reset must be synchronized to each clock domain. Using unsynchronized reset causes random initialization failures.

#### 2. Single-Bit CDC Synchronizers
```vhdl
-- 2-FF synchronizer pattern
signal ip_valid_sync1 : std_logic := '0';
signal ip_valid_sync2 : std_logic := '0';

process(clk)
begin
    if rising_edge(clk) then
        if reset = '1' then
            ip_valid_sync1 <= '0';
            ip_valid_sync2 <= '0';
        else
            ip_valid_sync1 <= ip_valid;        -- First FF (may go metastable)
            ip_valid_sync2 <= ip_valid_sync1;  -- Second FF (stable)
        end if;
    end if;
end process;
```

**Applied to ALL single-bit signals:**
- `ip_valid`, `udp_valid`, `frame_valid`
- `ip_checksum_ok`, `ip_version_err`, `ip_ihl_err`, `ip_checksum_err`
- `udp_length_err`

**Lesson:** EVERY single-bit signal crossing clock domains needs 2-FF synchronizer. Missing even one can cause intermittent failures.

#### 3. Multi-Bit CDC (Valid-Gated Capture)
```vhdl
-- Multi-bit signals captured on synchronized valid pulse
signal ip_protocol_latch : std_logic_vector(7 downto 0) := (others => '0');

process(clk)
begin
    if rising_edge(clk) then
        if reset = '1' then
            ip_protocol_latch <= (others => '0');
        elsif ip_valid_sync2 = '1' then  -- Use synchronized valid
            ip_protocol_latch <= ip_protocol;  -- Sample when stable
        end if;
    end if;
end process;
```

**Applied to multi-bit buses:**
- `ip_protocol` (8 bits)
- `ip_total_length` (16 bits)
- `byte_index` (integer)

**Lesson:** Multi-bit signals CANNOT be synchronized directly (bus skew). Use synchronized valid pulse to gate sampling.

#### 4. In-Frame Flag for Clean Boundaries
```vhdl
-- Track frame boundaries in 25 MHz domain
signal in_frame : std_logic := '0';

process(eth_rx_clk)
begin
    if rising_edge(eth_rx_clk) then
        if mdio_rst_rxclk = '1' then
            in_frame <= '0';
        else
            if rx_dv = '1' and sfd_detected = '1' then
                in_frame <= '1';  -- Frame started
            elsif rx_dv = '0' then
                in_frame <= '0';  -- Frame ended
            end if;
        end if;
    end if;
end process;
```

**Lesson:** Track state in source clock domain before crossing. Clean boundaries prevent glitches.

#### 5. XDC Timing Constraints (Critical!)
```tcl
## Mark asynchronous clock domains
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks eth_rx_clk] \
    -group [get_clocks eth_tx_clk] \
    -group [get_clocks eth_ref_clk]

## CDC Synchronizer Constraints
## Mark synchronizer flip-flops to prevent optimization and guide placement
set_property ASYNC_REG TRUE [get_cells -hier *ip_valid_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *udp_valid_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *frame_valid_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *ip_checksum_ok_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *ip_version_err_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *ip_ihl_err_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *ip_checksum_err_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *udp_length_err_sync*]
set_property ASYNC_REG TRUE [get_cells -hier *mdio_rst_rxclk_sync*]

## False paths to first stage of synchronizers (metastability allowed here)
set_false_path -to [get_cells -hier *ip_valid_sync1*]
set_false_path -to [get_cells -hier *udp_valid_sync1*]
set_false_path -to [get_cells -hier *frame_valid_sync1*]
set_false_path -to [get_cells -hier *ip_checksum_ok_sync1*]
set_false_path -to [get_cells -hier *ip_version_err_sync1*]
set_false_path -to [get_cells -hier *ip_ihl_err_sync1*]
set_false_path -to [get_cells -hier *ip_checksum_err_sync1*]
set_false_path -to [get_cells -hier *udp_length_err_sync1*]
set_false_path -to [get_cells -hier *mdio_rst_rxclk_sync1*]
```

**Lesson:**
- `ASYNC_REG` property tells tools these are synchronizer FFs (don't optimize away, keep close together)
- `set_false_path` to first stage allows metastability (first FF purpose)
- Without these constraints, tools may violate CDC integrity during placement/routing

### Debug Methodology That Worked

**Problem:** Hard to diagnose why UDP parsing fails when IP parsing works.

**Solution:** Comprehensive debug outputs added to UART formatter:

```vhdl
-- Debug fields added to MAC message
proto=11    -- IP protocol (should be 0x11 for UDP)
upok=0      -- UDP protocol check passed (udp_protocol_ok)
ulok=0      -- UDP length check passed (udp_length_ok)
frm=1       -- In-frame flag at ip_valid time
b14=45      -- Byte 14 content (IP version/IHL verification)
```

**Terminal Output Progression:**

1. **Initial:** `udp=0` (failure, no details)
2. **With debug:** `udp=0 upok=0 ulok=0 frm=1` (UDP checks failing)
3. **After debug analysis:** Discovered upok=1 only when IP checksum failed (wrong packets!)
4. **Root cause identified:** Race condition - UDP parser starting too late

**Lesson:** Strategic debug outputs reveal timing relationships. Seeing `frm=1` but `upok=0` showed timing issue, not logic bug.

### Production-Ready CDC Checklist

Based on Bug #13 resolution, use this checklist for ALL multi-clock designs:

✅ **1. Identify ALL CDC signals**
   - Single-bit control/status signals
   - Multi-bit data buses
   - Reset signals

✅ **2. Synchronize reset to EACH clock domain**
   - Use 2-FF synchronizer for reset
   - Apply synchronized reset to all registers in that domain

✅ **3. Apply 2-FF synchronizer to ALL single-bit CDC signals**
   - Don't skip error flags or status signals
   - Even "don't care" signals need synchronization

✅ **4. Use valid-gated capture for multi-bit buses**
   - Never synchronize multi-bit buses directly
   - Synchronize the valid signal (2-FF)
   - Sample bus on synchronized valid pulse

✅ **5. Track state in source clock domain**
   - Clean boundaries (like in_frame flag)
   - Reduces glitches during CDC

✅ **6. Add comprehensive XDC constraints**
   - Mark clock groups as asynchronous
   - Set ASYNC_REG property on synchronizer FFs
   - Set false path to first synchronizer stage

✅ **7. Verify timing closure**
   - Check for CDC violations in timing report
   - Ensure no setup/hold violations on CDC paths

✅ **8. Hardware stress test**
   - Test with 1000+ packets
   - Verify 100% success rate
   - Look for intermittent failures

### Key Architectural Lessons from Bug #13

#### ⭐ Lesson 1: Real-Time Architecture for Streaming Data
**Problem:** Event-driven parsers waiting for signals create race conditions.

**Solution:** Trigger state machines directly on byte position, not on derived signals.

**Pattern:**
```vhdl
-- ✅ GOOD: Position-based triggering
if byte_index = HEADER_START then
    state <= PARSE;
end if;

-- ❌ BAD: Signal-based triggering (creates race)
if some_valid_signal = '1' then
    state <= PARSE;
end if;
```

**When to use:**
- Streaming protocols (Ethernet, UART, SPI)
- Fixed-position headers (MAC, IP, UDP, ITCH)
- Deterministic timing requirements

#### ⭐ Lesson 2: CDC Cannot Be Partial
**Problem:** Missing even one CDC signal causes random failures.

**Solution:** Systematic approach - synchronize EVERY signal crossing clock domains.

**Checklist:**
- Valid/enable signals ✓
- Data buses ✓
- Error flags ✓ ← Often forgotten!
- Status signals ✓ ← Often forgotten!
- Reset ✓ ← Critical!

**One missed signal = production failure.**

#### ⭐ Lesson 3: Debug Outputs Are Investments
**Problem:** "It doesn't work" provides no actionable information.

**Solution:** Add strategic debug outputs showing signal relationships.

**Effective debug outputs:**
- Show both input and output of logic
- Display timing-critical flags (like `frm=` at ip_valid)
- Use hex for multi-bit values (easier to spot patterns)
- Keep format concise (fits on one line)

**Example:** `proto=11 upok=0 ulok=0 frm=1` instantly showed timing mismatch.

#### ⭐ Lesson 4: XDC Constraints Are Not Optional
**Problem:** Design works in simulation, fails in hardware.

**Solution:** CDC constraints guide tools to preserve synchronizer integrity.

**Critical constraints:**
- `set_clock_groups -asynchronous` - Declares independent clocks
- `ASYNC_REG TRUE` - Protects synchronizer FFs from optimization
- `set_false_path` - Allows metastability in first FF

**Without these:** Tools may optimize away synchronizers or place FFs too far apart.

### Comparison: v3b (Event-Driven) vs v5 (Real-Time)

| Metric | v3b (Broken) | v5 (Fixed) | Improvement |
|--------|--------------|------------|-------------|
| **Success Rate** | ~1% | 100% | **99% improvement** |
| **Code Size** | 280+ lines | 188 lines | 33% reduction |
| **State Machine** | 5 states | 4 states | Simpler |
| **Trigger Method** | ip_valid signal | byte_index position | Deterministic |
| **CDC Sync** | Partial | Complete | Production-ready |
| **XDC Constraints** | None | Comprehensive | Timing verified |
| **Stress Test** | Failed | 1000+ packets pass | Reliable |
| **Debug Time** | 4+ hours | N/A (working) | Huge time savings |

### Trading System Relevance

**Skills Demonstrated:**

1. **Production Debugging** - Systematic root cause analysis of race conditions
2. **CDC Mastery** - Essential for multi-clock trading FPGAs (network PHY, order entry, timestamping)
3. **Real-Time Processing** - Fixed-latency parsing critical for deterministic HFT systems
4. **Stress Testing** - 1000+ packet validation mirrors production QA requirements
5. **Architectural Redesign** - Knowing when to rewrite vs patch shows engineering maturity
6. **Debug Strategy** - Strategic instrumentation enables rapid issue diagnosis

**Why This Matters for Trading:**
- **ITCH/OUCH Parsing:** Same real-time architecture applies to NASDAQ protocols
- **Multi-Clock FPGAs:** Trading systems have multiple clock domains (network, processing, memory)
- **Zero Failures:** 100% success rate requirement mirrors trading production standards
- **Deterministic Latency:** Real-time parsing guarantees fixed latency (critical for HFT)
- **Production Patterns:** CDC checklist prevents costly bugs in live trading systems

### Files Modified for Bug #13 Resolution

1. **udp_parser.vhd** - Complete rewrite (280+ → 188 lines)
2. **mii_eth_top.vhd** - CDC synchronizers, reset sync, in_frame flag, debug signals
3. **uart_formatter.vhd** - Debug outputs (proto=, upok=, ulok=, frm=)
4. **arty_a7_100t_mii.xdc** - Comprehensive CDC timing constraints
5. **README.md** - Full documentation of Bug #13 journey (1,502 lines)

---
This document grows with each project. **Latest update: Project 6 Phase 1F v5 - Bug #13 Resolution Complete (November 7, 2025)**
