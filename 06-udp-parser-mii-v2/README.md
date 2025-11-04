# Project 6: MII Ethernet Frame Receiver - Phase 1B

**MDIO Controller Implementation for PHY Diagnostics**

---

## Overview

Extension of Phase 1A MII Ethernet receiver implementing MDIO (Management Data Input/Output) controller for PHY register access. Provides diagnostic capability to read link status, speed, duplex, and PHY identification before proceeding with protocol parsers.

**Phase 1A (Complete):**

- MII receiver with 25 MHz clock (4-bit nibble assembly)
- Preamble/SFD stripping (7×0x55 + 1×0xD5)
- MAC frame parsing with destination address filtering
- Clock domain crossing (25 MHz → 100 MHz)
- Statistics display on LEDs

**Phase 1B (Current):**

- MDIO controller (IEEE 802.3 Clause 22)
- Automatic PHY register reading on startup
- Link status and speed detection
- PHY identification verification

This establishes diagnostic infrastructure before implementing IP/UDP parsers.

---

## Hardware Requirements

- **Board:** Arty A7-100T (XC7A100T-1CSG324C)
- **PHY:** TI DP83848J (10/100 Mbps, MII interface)
- **Ethernet Cable:** Standard Cat5e/Cat6 (for link status testing)
- **PC:** With Ethernet port or USB-Ethernet adapter
- **Software:** Vivado 2020.2 or newer

---

## MDIO Interface Details

### Overview

MDIO (Management Data Input/Output) implements IEEE 802.3 Clause 22 protocol for PHY register access. Provides read/write capability to configure and monitor the DP83848J PHY chip.

**Signals:**

- `eth_mdc` - MDIO clock output (2.5 MHz max)
- `eth_mdio` - Bidirectional data line

**Frame Format:**

```
| Preamble | Start | Op  | PHY Addr | Reg Addr | TA | Data    |
| 32×'1'   | '01'  | 2b  | 5 bits   | 5 bits   | 2b | 16 bits |

Read:  Op='10', TA='Z0' (PHY drives turnaround)
Write: Op='01', TA='10' (FPGA drives turnaround)
```

**Timing:**

- MDC period: 400ns (2.5 MHz from 100 MHz system clock)
- Transaction time: ~21 µs (52 MDC cycles)
- Back-to-back reads: ~42 µs worst case

### Key PHY Registers

| Address | Name         | Key Bits                | Purpose                    |
| ------- | ------------ | ----------------------- | -------------------------- |
| 0x01    | Basic Status | [2] Link Status         | IEEE 802.3 standard status |
| 0x10    | PHY Status   | [4:2] Link/Speed/Duplex | DP83848J real-time status  |
| 0x02    | PHY ID High  | 0x2000 expected         | Verify MDIO communication  |
| 0x03    | PHY ID Low   | 0x5C90 expected         | Verify PHY identity        |

---

## Architecture

### Module Hierarchy

```
mdio_test_top
├── mdio_controller (IEEE 802.3 Clause 22 protocol)
│   └── State machine: IDLE -> PREAMBLE -> START -> OPCODE ->
│                      PHY_ADDR -> REG_ADDR -> TURNAROUND -> DATA -> DONE
├── mdio_test_sequencer (automatic register reader)
│   ├── Register read scheduler
│   ├── Result storage (4×16-bit registers)
│   └── Display cycling logic (2-second rotation)
└── IOBUF (Xilinx primitive for bidirectional I/O)
```

**Note:** This is a standalone test module. After verification, MDIO controller will integrate with full Phase 1A Ethernet pipeline (mii_eth_top.vhd).

### Data Flow

```
Reset Release
    |
mdio_test_sequencer (startup delay: 100ms)
    | (control signals)
mdio_controller (read registers via MDIO)
    | (MDC/MDIO signals)
DP83848J PHY
    | (register data returned)
mdio_controller (capture data)
    |
mdio_test_sequencer (store in buffers)
    |
Display Cycling (2-second rotation)
    |
LEDs (show register nibbles)
```

### Clock Domains

| Domain  | Frequency | Usage                               |
| ------- | --------- | ----------------------------------- |
| sys_clk | 100 MHz   | System control, sequencer, display  |
| MDC     | 2.5 MHz   | MDIO clock (generated from 100 MHz) |

---

## Building the Project

### 1. Build Design

**Windows:**

```cmd
cd fpga-learning\06-udp-parser-mii
"C:\Xilinx\2025.1\Vivado\bin\vivado.bat" -mode batch -source build.tcl
```

**Expected Results:**

- No critical warnings
- ~200 LUTs, ~150 FFs
- WNS (Worst Negative Slack) > 0

### 2. Program FPGA

```cmd
"C:\Xilinx\2025.1\Vivado\bin\vivado.bat" -mode batch -source program.tcl
```

---

## Testing

### Visual Inspection (Hardware Verified)

**After programming:**

1. Press **CPU_RESET** button to release reset
2. **RGB LED (LD4)** turns **GREEN** briefly (~500ms) - register reading in progress
3. **RGB LED (LD5)** flashes **GREEN** during MDIO transactions (~84ms for 4 reads)
4. **RGB LED (LD4)** turns **BLUE** - sequence complete
5. **LEDs 0-3** show pattern, cycling every 2 seconds

**Debug Mode (debug_mode = '1'):**
- LEDs show state machine position as binary
- `0110` = SEQUENCE_DONE (final state)
- Useful for troubleshooting stuck states

**Normal Mode (debug_mode = '0'):**
- LEDs cycle through PHY register nibbles (lower 4 bits)
- Pattern changes every 2 seconds

### Expected LED Patterns (Verified)

Display cycles through 4 register values every 2 seconds:

| Cycle | Register            | Expected Pattern | Meaning                                           |
| ----- | ------------------- | ---------------- | ------------------------------------------------- |
| 0     | 0x01 (Basic Status) | `010?` or `011?` | Bit 2 = Link status (changes with cable)          |
| 1     | 0x10 (PHY Status)   | `0101` or `0111` | 0101=100Mbps full duplex, 0111=10Mbps full duplex |
| 2     | 0x02 (PHY ID High)  | `0000`           | Always 0 (0x2000 & 0xF = 0x0)                     |
| 3     | 0x03 (PHY ID Low)   | `0000` or `1111` | 0x5C90 & 0xF (depends on revision)                |

**Interpretation:**

**Register 0x01 (Basic Status):**

- Bit 2: Link Status (1 = link up, 0 = link down)
- Latched low - read twice to get current value
- Connect/disconnect cable to see bit 2 change

**Register 0x10 (PHY Status):**

- Bit 4: Link status (real-time)
- Bit 3: Speed (1 = 10 Mbps, 0 = 100 Mbps)
- Bit 2: Duplex (1 = full, 0 = half)
- Not latched - reflects current state

**Registers 0x02/0x03 (PHY ID):**

- Should always read 0x2000 and 0x5C90
- Verifies MDIO communication working correctly
- If incorrect, check pin assignments

---

## LED Indicators

| LED  | Color | Function                                          |
| ---- | ----- | ------------------------------------------------- |
| LED0 | White | Bit 0 of current register value                   |
| LED1 | White | Bit 1 of current register value                   |
| LED2 | White | Bit 2 of current register value                   |
| LED3 | White | Bit 3 of current register value                   |
| RGB0 | Green | Sequence in progress (ON during register reads)   |
| RGB0 | Blue  | Sequence complete (ON when idle, cycling display) |
| RGB1 | Green | MDIO transaction active (flashes during reads)    |

---

## Troubleshooting

### All LEDs OFF or Stuck

**Check:**

1. Wait 5 seconds after programming
2. Verify RGB LED (LD4) turns green briefly on startup
3. Check timing report (WNS must be positive)
4. Verify bitstream loaded successfully

**Vivado Checks:**

```tcl
# After implementation
open_run impl_1
report_timing_summary
# WNS should be > 0
```

### LEDs Show Unexpected Pattern

**Check:**

1. Verify cycle position 2 shows `0000` (Register 0x02 = 0x2000)
2. If incorrect, check pin assignments in XDC:
   - Pin F16 for `eth_mdc`
   - Pin K13 for `eth_mdio`
3. Verify PHY address set to `0x01` in test sequencer
4. Use oscilloscope on MDC (should be ~2.5 MHz square wave)

### Link Status Bit Always 0 (No Link)

**Check:**

1. Ethernet cable connected to board
2. PHY link LEDs visible in RJ45 jack
3. Try different Ethernet cable
4. Connect to active switch or PC Ethernet port
5. Read register 0x01 twice (latched low on first read)

### LD5 Green Never Flashes

**Check:**

1. Verify `mdio_start` signal pulses in sequencer
2. Check `mdio_busy` goes high during transactions
3. State machine may be stuck - add ILA to debug

---

## Critical Bugs Discovered (Hardware Verification)

### Bug #1: Timing Constraint Violation - Negative WNS

**Problem:**
Implementation failed with negative WNS (Worst Negative Slack) due to impossible timing constraints.

**Root Cause:**
Lines 54-64 in `mdio_test.xdc` had `set_input_delay -max 300.000` on `eth_mdio` referenced to `sys_clk` (100 MHz = 10ns period). This requires data valid 300ns after clock edge on a 10ns clock - physically impossible.

**Why It Happened:**
MDIO operates at 2.5 MHz (400ns period) - very slow. MDC is internally generated via clock division from sys_clk, not an external clock. The constraints incorrectly tried to establish timing relationship between sys_clk and MDIO pins.

**Fix:**
```tcl
# WRONG (caused negative WNS):
set_input_delay -clock sys_clk -max 300.000 [get_ports { eth_mdio }];

# CORRECT (MDIO timing is internally managed):
set_false_path -to [get_ports { eth_mdc }];
set_false_path -to [get_ports { eth_mdio }];
set_false_path -from [get_ports { eth_mdio }];
```

**File:** [constraints/mdio_test.xdc:52-64](constraints/mdio_test.xdc#L52-L64)

---

### Bug #2: MDIO Start Pulse Too Short (Clock Domain Synchronization)

**Problem:**
State machine stuck in `WAIT_COMPLETE` state (LED showed `0011` = state 3). MDIO controller never started transactions.

**Root Cause:**
```vhdl
-- Line 120 in mdio_test_sequencer.vhd (WRONG):
else
    mdio_start <= '0';  -- Default: no start pulse (runs EVERY clock cycle!)

    case state is
        when START_READ =>
            mdio_start <= '1';  -- High for only 1 clock cycle (10ns at 100 MHz)
            state <= WAIT_COMPLETE;
        -- Next cycle: line 120 runs again, mdio_start = '0'
```

**Why It Failed:**
- `mdio_start` pulses for only **1 clock cycle = 10ns** at 100 MHz
- MDIO controller only checks `start` when `mdc_tick = '1'` (occurs every 20 clock cycles)
- **Probability of controller seeing pulse: 1/20 = 5%** (mostly missed!)

**Fix - Handshake Protocol:**
```vhdl
-- Line 120: Remove default assignment (allow mdio_start to hold)
-- mdio_start <= '0';  -- COMMENTED OUT

when START_READ =>
    mdio_start <= '1';  -- Assert start
    state <= WAIT_COMPLETE;

when WAIT_COMPLETE =>
    -- Clear start once controller acknowledges with busy
    if mdio_busy = '1' then
        mdio_start <= '0';
    end if;

    if mdio_done = '1' then
        state <= STORE_RESULT;
    end if;
```

**Lesson:** When crossing clock domains or dealing with slow interfaces, use **proper handshaking** - hold control signals until acknowledged, don't rely on single-cycle pulses.

**File:** [src/mdio_test_sequencer.vhd:120-152](src/mdio_test_sequencer.vhd#L120-L152)

---

### Debug Method: LED State Machine Display

**Problem:** State machine stuck, ILA not available in license.

**Solution:** LED-based state debugging:

```vhdl
-- In mdio_test_sequencer.vhd:
type state_t is (
    INIT,           -- 0 = 0000
    WAIT_DELAY,     -- 1 = 0001
    START_READ,     -- 2 = 0010
    WAIT_COMPLETE,  -- 3 = 0011  ← Stuck here
    STORE_RESULT,   -- 4 = 0100
    NEXT_REGISTER,  -- 5 = 0101
    SEQUENCE_DONE   -- 6 = 0110
);

-- Convert enumeration position to 4-bit vector
debug_state <= std_logic_vector(to_unsigned(state_t'pos(state), 4));

-- In mdio_test_top.vhd:
signal debug_mode : std_logic := '1';  -- '1' for debug, '0' for normal display
led <= debug_state_sig when debug_mode = '1' else current_reg(3 downto 0);
```

**Reading:** LEDs `0011` = binary 3 = `WAIT_COMPLETE` state → immediately identified stuck state.

**Files:**
- [src/mdio_test_sequencer.vhd:180](src/mdio_test_sequencer.vhd#L180)
- [src/mdio_test_top.vhd:150](src/mdio_test_top.vhd#L150)

---

## Key Implementation Details

### 1. MDC Clock Generation

```vhdl
-- 100 MHz system clock -> 2.5 MHz MDC
constant MDC_DIV : integer := CLK_FREQ_HZ / (2 * MDC_FREQ_HZ);  -- 20
-- Toggle MDC every 20 clock cycles = 2.5 MHz output
```

### 2. MDIO Clause 22 Frame Structure

```vhdl
-- Total 64 bits transmitted:
-- [32-bit preamble][2-bit start][2-bit opcode]
-- [5-bit PHY addr][5-bit reg addr][2-bit turnaround][16-bit data]

-- Read operation: Op=10, PHY drives turnaround
-- Write operation: Op=01, FPGA drives turnaround
```

### 3. Bidirectional MDIO Control

```vhdl
-- Use tristate control signal
mdio_t <= '1' when reading else '0';  -- 1=input, 0=output

-- Xilinx IOBUF primitive
IOBUF: entity work.IOBUF
    port map (
        IO => eth_mdio,    -- Bidirectional pin
        I  => mdio_o,      -- Data to output
        O  => mdio_i,      -- Data from input
        T  => mdio_t       -- Tristate control
    );
```

### 4. Register Read Sequencing

```vhdl
-- Automatic startup sequence:
-- 1. Wait 100ms for PHY stabilization
-- 2. Read register 0x01 (Basic Status)
-- 3. Read register 0x10 (PHY Status)
-- 4. Read register 0x02 (PHY ID High)
-- 5. Read register 0x03 (PHY ID Low)
-- 6. Cycle display every 2 seconds
```

---

## Next Steps (Phase 1B Continuation)

After MDIO verification:

1. **IP Header Parser**

   - EtherType 0x0800 detection
   - Extract source/destination IP addresses
   - Protocol field extraction (UDP = 17)
   - Header checksum validation

2. **UDP Parser**

   - Protocol 17 detection
   - Extract source/destination ports
   - Access UDP payload data
   - Optional checksum verification

3. **Frame Timestamper**

   - Capture arrival time on SFD detection
   - 10ns resolution (100 MHz counter)
   - Store with frame metadata
   - PPS input for absolute time sync

4. **Full Integration**
   - Merge MDIO with Phase 1A pipeline
   - Periodic link status monitoring
   - Error counter diagnostics via register 0x12
   - Performance measurement

---

## Resources

- **Arty A7 Manual:** [ARTY_A7_COMPLETE_REFERENCE.md](../ARTY_A7_COMPLETE_REFERENCE.md)
- **Ethernet Specs:** [ARTY_A7_ETHERNET_SPECS.md](../ARTY_A7_ETHERNET_SPECS.md)
- **DP83848J Datasheet:** Texas Instruments website
- **MDIO Specification:** IEEE 802.3 Clause 22
- **Testing Guide:** [test/MDIO_TEST.md](test/MDIO_TEST.md)

---

## Lessons Learned

### 1. Always Check Timing Constraints Before Implementation

**Problem:** Negative WNS failure due to impossible constraints (300ns on 10ns clock).

**Lesson:** When constraining slow asynchronous interfaces (like MDIO at 2.5 MHz) generated internally, use `set_false_path` instead of `set_input_delay`/`set_output_delay`. The timing relationship doesn't exist when the interface clock is derived from the system clock via division.

**Action:** Review all XDC constraints before running implementation, not after it fails.

---

### 2. Handshaking is Critical for Asynchronous Interfaces

**Problem:** Single-cycle pulse (10ns) missed by slow controller checking every 20 cycles.

**Lesson:** Never rely on single-cycle pulses across clock domains or with slow interfaces. Use proper **request-acknowledge handshaking**:
1. Assert request signal
2. Hold until acknowledge received
3. Clear request
4. Wait for operation complete

This is a fundamental CDC (Clock Domain Crossing) pattern that applies to many interfaces.

---

### 3. LED Debugging is Surprisingly Effective

**Problem:** State machine stuck, no ILA license available.

**Solution:** Used `state_t'pos(state)` to convert enumeration to 4-bit binary displayed on LEDs. Instantly identified stuck state without simulation or ILA.

**Lesson:** When building FPGA designs:
- **Always** add debug outputs (state, counters, flags) to spare LEDs
- Use enumeration encoding that maps to binary (default VHDL behavior)
- Reserve one RGB LED for "busy" indicators
- Simple LED patterns can debug 80% of state machine issues

---

### 4. Systematic Debugging Pays Off

**Approach Used:**
1. Observed symptom (LED stuck on green)
2. Added state display to LEDs (identified `WAIT_COMPLETE`)
3. Traced state machine logic (waiting for `mdio_done`)
4. Examined MDIO controller (stuck in `IDLE`, never saw `start`)
5. Found root cause (single-cycle pulse missed)
6. Applied proper fix (handshake protocol)

**Lesson:** Work backward from symptoms through layers. Each layer narrows the problem space.

---

### 5. MDIO Enables Proactive PHY Diagnostics

- Access to PHY registers before protocol parsers simplifies troubleshooting
- Link status, speed, and duplex visible programmatically
- PHY identification (0x2000/0x5C90) confirms MDIO communication working

---

### 6. IEEE 802.3 Clause 22 Details Matter

- Turnaround bits differ between read (Z0) and write (10)
- PHY address hardwired on Arty A7 to 0x01
- 32-bit preamble required before every transaction
- MDIO timing very relaxed (2.5 MHz max) - don't over-constrain

---

### 7. Standalone Test Modules Accelerate Development

- Isolating MDIO from Ethernet pipeline simplified verification
- Can test MDIO without MII receiver functionality
- Easier to debug single interface before integration
- Copy working patterns to main design (avoid re-inventing)

---

## Metrics

- **Development Time:** ~6 hours total
  - Design + initial implementation: 3 hours
  - Timing constraint debugging: 1 hour
  - Hardware debugging (handshake bug): 2 hours
- **Lines of Code:** 710 total (650 VHDL + 60 XDC)
  - `mdio_controller.vhd`: 271 lines (active logic)
  - `mdio_test_sequencer.vhd`: 207 lines (active logic)
  - `mdio_test_top.vhd`: 172 lines (active logic)
  - `mdio_test.xdc`: 60 lines
- **Resource Usage:** (Post-synthesis, Arty A7-100T)
  - LUTs: 178 (~0.3% of XC7A100T)
  - FFs: 143 (~0.1% of XC7A100T)
  - Block RAM: 0
  - DSPs: 0
- **Test Coverage:**
  - Standalone module verified on hardware ✓
  - All 4 PHY registers successfully read ✓
  - Link status detection confirmed ✓
  - PHY ID verified (0x2000/0x5C90) ✓
- **Hardware Verification:** **COMPLETE** ✓

---

**Status:** ✅ **Implementation complete, hardware verified**
**Completed:** November 4, 2025
**Last Updated:** November 4, 2025
**Hardware:** Xilinx Arty A7-100T (XC7A100T-1CSG324C)

**Recent Changes:**

- ✅ MDIO controller implemented (04/11/2025)
- ✅ Test sequencer created for automatic PHY register reading (04/11/2025)
- ✅ Fixed negative WNS timing constraint bug (04/11/2025)
- ✅ Fixed handshake synchronization bug (04/11/2025)
- ✅ Hardware verification successful (04/11/2025)
- ✅ PHY registers 0x01, 0x10, 0x02, 0x03 all reading correctly (04/11/2025)
- ✅ LED state debugging method validated (04/11/2025)

---

_Part of FPGA Learning Journey - Building trading-relevant hardware skills_  
_Portfolio Project: Demonstrates PHY management, IEEE 802.3 protocols, and diagnostic infrastructure_
