# Project 6: MII Ethernet Frame Receiver - Phase 1C

**Integrated MDIO + Ethernet Pipeline with Debug Interface**

---

## Overview

Full integration of MDIO controller with Phases 1A and 1B Ethernet receiver pipeline. Combines PHY diagnostics with frame reception, adding interactive debug mode, UART status output, and multiplexed LED display.

**Phase 1A (Complete):**

- MII receiver with 25 MHz clock (4-bit nibble assembly)
- Preamble/SFD stripping (7×0x55 + 1×0xD5)
- MAC frame parsing with destination address filtering
- Clock domain crossing (25 MHz → 100 MHz)
- Statistics display on LEDs

**Phase 1B (Complete):**

- MDIO controller (IEEE 802.3 Clause 22)
- Automatic PHY register reading on startup
- Link status and speed detection
- PHY identification verification

**Phase 1C (Complete):**

- **Integrated pipeline:** MDIO + MII receiver + MAC parser running simultaneously
- **Button control:** BTN3 toggles between frame stats and MDIO register display
- **UART debug:** Real-time state machine status output at 115200 baud
- **Enhanced LED indicators:** RGB status for debug mode, sequence activity, PHY ready
- **Debounced inputs:** Proper button handling with edge detection

Establishes complete diagnostic and monitoring infrastructure for Ethernet frame processing.

---

## Hardware Requirements

- **Board:** Arty A7-100T (XC7A100T-1CSG324C)
- **PHY:** TI DP83848J (10/100 Mbps, MII interface)
- **Ethernet Cable:** Standard Cat5e/Cat6 (for link status and frame reception)
- **PC:** With Ethernet port or USB-Ethernet adapter
- **USB Cable:** For UART debug output (micro-USB)
- **Software:** Vivado 2020.2 or newer, serial terminal (115200 baud)

---

## Architecture

### Module Hierarchy

```
mii_eth_top
├── Clock Generation
│   └── PLLE2_BASE: 100 MHz → 25 MHz reference for PHY
├── PHY Reset Generation
│   └── 20ms reset pulse counter
├── Button Handling
│   ├── button_debouncer (BTN0, BTN3)
│   └── edge_detector (rising/falling edge detection)
├── MDIO Subsystem
│   ├── mdio_controller (IEEE 802.3 Clause 22 protocol)
│   ├── mdio_phy_monitor (sequencer: 4 register reads)
│   └── IOBUF (tristate buffer for eth_mdio)
├── Ethernet Receiver Pipeline
│   ├── mii_rx (nibble→byte, preamble strip)
│   ├── mac_parser (address filtering, frame counting)
│   ├── 2FF synchronizer (25 MHz → 100 MHz CDC)
│   └── stats_counter (LED display, activity indicator)
└── UART Debug Output
    └── uart_tx (state machine status at 115200 baud)
```

### Data Flow

**Ethernet Reception Path:**

```
PHY (eth_rxd[3:0]) → mii_rx → mac_parser → frame_valid
                                                |
                                    2FF Synchronizer (CDC)
                                                |
                                         stats_counter
                                                |
                                        LED multiplexer
                                                |
                                        LED[3:0] output
```

**MDIO Diagnostic Path:**

```
mdio_phy_monitor → mdio_controller → PHY registers
         |                                   |
    (control)                            (data)
         |                                   |
         └──────── reg_values[63:0] ─────────┘
                         |
                  Display cycling
                         |
                 LED multiplexer
```

**User Interface:**

```
BTN3 → debouncer → edge_detector → debug_mode toggle
                                          |
                                    LED multiplexer
                                          |
                           ┌──────────────┴──────────────┐
                      debug='0'                    debug='1'
                           |                             |
                   Frame Statistics              MDIO Registers
                   (stats_counter)         (cycling every 2s)
```

### Clock Domains

| Domain      | Frequency | Usage                                        |
| ----------- | --------- | -------------------------------------------- |
| clk         | 100 MHz   | System clock, MDIO, buttons, UART, stats     |
| eth_rx_clk  | 25 MHz    | MII receiver, MAC parser (from PHY)          |
| eth_ref_clk | 25 MHz    | PHY reference clock (PLL generated from clk) |
| MDC         | 2.5 MHz   | MDIO clock (internally divided from clk)     |

**Clock Domain Crossings:**

- `frame_valid` (25 MHz) → 2FF synchronizer → `frame_valid_sync2` (100 MHz)

---

## Building the Project

### 1. Build Design

**Windows:**

```cmd
cd fpga-learning\06-udp-parser-mii-v3
"C:\Xilinx\2025.1\Vivado\bin\vivado.bat" -mode batch -source build.tcl
```

**Expected Results:**

- No critical warnings
- ~400-500 LUTs, ~300-350 FFs
- WNS (Worst Negative Slack) > 0
- ~1% of XC7A100T resources

### 2. Program FPGA

```cmd
"C:\Xilinx\2025.1\Vivado\bin\vivado.bat" -mode batch -source program.tcl
```

### 3. Connect Serial Terminal

```cmd
# Connect to COM port at 115200 baud, 8N1
# Use PuTTY, TeraTerm, or screen (Linux/Mac)
screen /dev/ttyUSB0 115200   # Linux
screen /dev/cu.usbserial 115200  # Mac
```

---

## Testing

### Hardware Verification

**After programming:**

1. **PHY Reset (automatic):**

   - LD4 Blue turns ON after 20ms → PHY ready

2. **MDIO Sequence (automatic):**

   - LD5 Green flashes during register reads (~84ms total)
   - LD6 Green/Blue indicates sequence progress
   - UART outputs state machine hex codes (0-6)

3. **Frame Reception (automatic when cable connected):**

   - LD4 Green flashes on frame activity
   - LED[3:0] shows frame count (default mode)

4. **Debug Mode Toggle:**
   - Press BTN3 to switch modes
   - LD6 changes to indicate debug mode active
   - LED[3:0] switches from frame count to MDIO registers

### User Controls

| Button  | Function                                    | Active |
| ------- | ------------------------------------------- | ------ |
| BTN0    | System reset (debounced)                    | HIGH   |
| BTN3    | Toggle debug mode (frame stats ↔ MDIO regs) | HIGH   |
| reset_n | CPU reset (built-in on Arty A7)             | LOW    |

### LED Indicators

**Normal Mode (debug_mode='0'):**

| LED       | Color | Function                                |
| --------- | ----- | --------------------------------------- |
| LED[3:0]  | White | Frame count (4-bit counter)             |
| LD4 Red   | Red   | RX error detected                       |
| LD4 Green | Green | Frame activity (flashes on valid frame) |
| LD4 Blue  | Blue  | PHY ready after 20ms reset              |
| LD5 Green | Green | MDIO transaction active                 |
| LD6       | Off   | Debug mode inactive                     |

**Debug Mode (debug_mode='1'):**

| LED       | Color | Function                              |
| --------- | ----- | ------------------------------------- |
| LED[3:0]  | White | MDIO register nibbles (cycling 2s)    |
| LD4 Red   | Red   | RX error detected                     |
| LD4 Green | Green | Frame activity (still shows activity) |
| LD4 Blue  | Blue  | PHY ready                             |
| LD5 Green | Green | MDIO transaction active               |
| LD6 Green | Green | Sequence in progress                  |
| LD6 Blue  | Blue  | Sequence complete                     |

### MDIO Register Display (Debug Mode)

Display cycles through 4 register values every 2 seconds:

| Cycle | Register            | Expected Pattern | Meaning                                           |
| ----- | ------------------- | ---------------- | ------------------------------------------------- |
| 0     | 0x01 (Basic Status) | `010?` or `011?` | Bit 2 = Link status (changes with cable)          |
| 1     | 0x10 (PHY Status)   | `0101` or `0111` | 0101=100Mbps full duplex, 0111=10Mbps full duplex |
| 2     | 0x02 (PHY ID High)  | `0000`           | Always 0 (0x2000 & 0xF = 0x0)                     |
| 3     | 0x03 (PHY ID Low)   | `0000` or `1111` | 0x5C90 & 0xF (depends on revision)                |

### UART Debug Output

When debug mode active (BTN3 pressed):

```
3
3
4
5
6
6
6
```

Each line shows current MDIO sequencer state:

- `0` = INIT
- `1` = WAIT_DELAY
- `2` = START_READ
- `3` = WAIT_COMPLETE
- `4` = STORE_RESULT
- `5` = NEXT_REGISTER
- `6` = SEQUENCE_DONE

Format: Single hex digit + newline (0xHEX 0x0A 0x0D)

---

## MDIO Interface Details

### Key PHY Registers

| Address | Name         | Key Bits                | Purpose                    |
| ------- | ------------ | ----------------------- | -------------------------- |
| 0x01    | Basic Status | [2] Link Status         | IEEE 802.3 standard status |
| 0x10    | PHY Status   | [4:2] Link/Speed/Duplex | DP83848J real-time status  |
| 0x02    | PHY ID High  | 0x2000 expected         | Verify MDIO communication  |
| 0x03    | PHY ID Low   | 0x5C90 expected         | Verify PHY identity        |

### Timing

- MDC frequency: 2.5 MHz (400ns period)
- Single register read: ~21 µs
- Full 4-register sequence: ~84 ms (with delays)
- Display cycle period: 2 seconds per register

---

## Troubleshooting

### All LEDs OFF or Stuck

**Check:**

1. Wait 5 seconds after programming
2. Verify LD4 Blue turns ON (PHY ready)
3. Press CPU_RESET button
4. Check timing report (WNS must be positive)
5. Verify bitstream loaded successfully

### No Frame Count (LED[3:0] stays 0000)

**Check:**

1. Ethernet cable connected to board
2. Ethernet cable connected to active device (PC/switch)
3. PHY link LEDs visible in RJ45 jack
4. Send frames from PC: `python test/test_mii_ethernet.py`
5. Verify MAC address matches: `MY_MAC_ADDR = x"000A3502AF9A"`

### MDIO Registers Show All Zeros

**Check:**

1. Press BTN3 to enter debug mode
2. Wait 2-4 seconds for display to cycle
3. Check pin assignments in XDC:
   - Pin F16 for `eth_mdc`
   - Pin K13 for `eth_mdio`
4. Verify PHY address = `0x01` in [mii_eth_top.vhd:230](src/mii_eth_top.vhd#L230)

### UART No Output

**Check:**

1. Press BTN3 to activate debug mode
2. Verify LD6 shows activity (green/blue)
3. Check serial port settings: 115200 baud, 8N1
4. Verify USB cable connected (micro-USB on Arty A7)
5. Check COM port assignment (Windows Device Manager)

### Debug Mode Toggle Not Working

**Check:**

1. Verify BTN3 pressed (button requires active HIGH on Arty A7)
2. LED[3:0] should switch between frame count and MDIO registers
3. LD6 should change state when debug mode active
4. Check [mii_eth_top.vhd:388-390](src/mii_eth_top.vhd#L388-L390) for toggle logic

---

## Critical Bugs Fixed

None found

---

## Key Implementation Details

### 1. Button Debouncing

```vhdl
-- 20ms debounce period prevents mechanical switch bounce
button_debouncer: generic map (
    CLK_FREQ => 100_000_000,
    DEBOUNCE_MS => 20
)
```

**Why needed:** Mechanical switches bounce for 5-20ms, causing multiple transitions.

---

### 2. Edge Detection for Button Events

```vhdl
-- Detect rising edge of debounced button
edge_detector: port map (
    clk => clk,
    sig_in => debug_btn_db,
    rising => debug_btn_rise,  -- Single-cycle pulse on press
    falling => debug_btn_fall
)
```

**Why needed:** Prevents multiple toggles during button hold.

---

### 3. LED Multiplexing to Avoid Multiple Drivers

```vhdl
-- Intermediate signals from stats_counter
signal frame_count_leds : std_logic_vector(3 downto 0);
signal frame_activity   : std_logic;

-- Single assignment with multiplexer
led <= current_reg(3 downto 0) when debug_mode = '1' else frame_count_leds;
led_rgb(1) <= frame_activity;  -- Always show activity
```

**Why needed:** VHDL prohibits multiple drivers on same signal.

---

### 4. MDIO Tristate Buffer

```vhdl
-- Bidirectional I/O using Xilinx IOBUF primitive
mdio_iobuf : IOBUF
    port map (
        IO => eth_mdio,  -- Bidirectional pin
        O  => mdio_i,    -- Input to FPGA
        I  => mdio_o,    -- Output from FPGA
        T  => mdio_t     -- Tristate: '1'=input, '0'=output
    );
```

**Why needed:** MDIO uses single bidirectional data line for read/write.

---

### 5. Clock Domain Crossing (CDC)

```vhdl
-- 2FF synchronizer for frame_valid (25 MHz → 100 MHz)
process(CLK)
begin
    if rising_edge(CLK) then
        frame_valid_sync1 <= frame_valid;
        frame_valid_sync2 <= frame_valid_sync1;
    end if;
end process;
```

**Why needed:** Prevents metastability when crossing clock domains.

---

### 6. UART State Machine for Debug Output

```vhdl
-- Sends MDIO state machine position as hex ASCII
when UART_IDLE =>
    if debug_mode = '1' then
        case uart_msg_counter is
            when 0 => tx_data <= nibble_to_hex(debug_state_sig);
            when 1 => tx_data <= X"0A";  -- '\n'
            when 2 => tx_data <= X"0D";  -- '\r'
        end case;
        tx_start <= '1';
        uart_state <= UART_ECHO_TX;
    end if;
```

**Purpose:** Real-time visibility into MDIO sequencer state without ILA.

---

## Lessons Learned

### 1. Integration Testing Reveals Edge Cases

Combining MDIO with Ethernet pipeline exposed subtle timing interactions not visible in standalone testing. Button debouncing became critical when user toggles affected both subsystems simultaneously.

---

### 2. Multiplexed Displays Improve Debug Visibility

Single set of LEDs showing either frame stats or MDIO registers via button toggle maximizes utility of limited hardware. Users can verify both subsystems without reprogramming.

---

### 3. UART Debug Output Complements LED Indicators

UART provides continuous state machine trace without consuming LED resources. Hex output format minimizes bandwidth (3 bytes per update vs. verbose text).

---

### 4. Proper Button Handling Prevents Glitches

Debouncing + edge detection is essential for toggle functionality. Without edge detection, holding button causes rapid toggling. Without debouncing, single press causes multiple toggles.

---

### 5. Intermediate Signals Solve Multiple Driver Issues

VHDL's single-driver rule requires careful architecture. Connecting component outputs to intermediate signals, then using multiplexers for final assignment, provides clean solution.

---

### 6. Structural Architecture Clarifies Integration

Changing from behavioral to structural architecture makes module interconnections explicit. Component declarations serve as internal documentation of subsystem interfaces.

---

## Next Steps (Phase 2)

After integrated pipeline verification:

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

4. **Performance Monitoring**
   - Periodic PHY register polling
   - Error counter diagnostics (register 0x12)
   - Frame loss detection
   - Throughput measurement

---

## Resources

- **Arty A7 Manual:** [ARTY_A7_COMPLETE_REFERENCE.md](../ARTY_A7_COMPLETE_REFERENCE.md)
- **Ethernet Specs:** [ARTY_A7_ETHERNET_SPECS.md](../ARTY_A7_ETHERNET_SPECS.md)
- **DP83848J Datasheet:** Texas Instruments website
- **MDIO Specification:** IEEE 802.3 Clause 22
- **UART Testing:** Python PySerial for automated verification

---

## Metrics

- **Development Time:** ~12 hours total
  - Integration architecture: 6 hours
  - Button control implementation: 2 hours
  - UART debug output: 1 hour
  - LED multiplexing: 1 hour
  - Bug fixes and testing: 2 hours
- **Lines of Code:** ~950 total VHDL (active logic)
  - `mii_eth_top.vhd`: 714 lines (integration)
  - `mdio_controller.vhd`: 271 lines (reused from v2)
  - `mdio_phy_monitor.vhd`: 207 lines (reused from v2)
  - `mii_rx.vhd`: 180 lines (reused from Phase 1A)
  - `mac_parser.vhd`: 160 lines (reused from Phase 1A)
  - `stats_counter.vhd`: 90 lines (reused from Phase 1A)
  - `uart_tx.vhd`: 120 lines (added for debug)
  - `button_debouncer.vhd`: 60 lines (added for controls)
  - `edge_detector.vhd`: 30 lines (added for controls)
- **Resource Usage:** (Post-synthesis estimate)
  - LUTs: ~450 (~0.7% of XC7A100T)
  - FFs: ~320 (~0.3% of XC7A100T)
  - Block RAM: 0
  - DSPs: 0
- **Test Coverage:**
  - MDIO integration verified ✓
  - Button controls verified ✓
  - LED multiplexing verified ✓
  - UART output verified ✓
  - Frame reception + MDIO simultaneous operation ✓
- **Hardware Verification:** Completed, fully working on Arty A7

---

**Status:** ✅ **Implementation complete**
**Created:** November 4, 2025
**Last Updated:** November 5, 2025
**Hardware:** Xilinx Arty A7-100T (XC7A100T-1CSG324C)

**Recent Changes:**

- ✅ Integrated MDIO with Ethernet receiver pipeline (04/11/2025)
- ✅ Added BTN3 debug mode toggle (05/11/2025)
- ✅ Implemented button debouncing and edge detection (05/11/2025)
- ✅ Added UART debug output for state machine monitoring (05/11/2025)
- ✅ Created LED multiplexer for dual-mode display (05/11/2025)
- ✅ Fixed BTN comment inconsistency bug (05/11/2025)
- ✅ Fixed ASCII code comment errors (05/11/2025)
- ✅ Removed incomplete commented code (05/11/2025)

---

_Part of FPGA Learning Journey - Building trading-relevant hardware skills_
_Portfolio Project: Demonstrates subsystem integration, user interfaces, and concurrent operation_
