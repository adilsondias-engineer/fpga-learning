2# Project 7: ITCH 5.0 Protocol Parser Phase 4

## Overview

ITCH 5.0 protocol parser implementation for Nasdaq market data feeds. Receives UDP packets containing ITCH binary messages, extracts message types and fields, and outputs human-readable debug information via UART. Demonstrates hardware protocol parsing capabilities relevant to high-frequency trading systems.

**Trading Relevance:** ITCH is the industry-standard protocol for Nasdaq market data dissemination. Trading firms parse ITCH feeds in FPGAs to achieve sub-microsecond latency from network arrival to trading decision.

## Status

**Phase 1:** ✅ Complete - Message type detection, Add Order/Execute/Cancel field extraction
**Phase 2:** ✅ Complete - System Event, Stock Directory, UDP port filtering
**Phase 3:** ✅ Complete - Parser completion fixes, back-to-back message handling, encoder reliability
**Phase 3.5 (v3 Architecture):** ✅ Complete - **MAJOR REFACTORING** - Async FIFO architecture eliminates race conditions
**Phase 4 (v4):** 🔄 Planned - Additional message types (P, Q, U, D) - will start from v3 codebase
**Phase 5:** 🔄 Planned - Integration with order book (Project 8)

## Hardware Requirements

- **Board:** Digilent Arty A7-100T Development Board
- **FPGA:** Xilinx Artix-7 XC7A100T-1CSG324C
- **PHY:** TI DP83848J 10/100 Ethernet (MII interface)
- **Tools:** AMD Vivado Design Suite 2025.1

## Features Implemented

### Protocol Support
- ITCH 5.0 binary message parsing
- Big-endian (network byte order) field extraction
- Message type detection and validation
- Per-message-type field extraction
- Multi-layer packet filtering (MAC, IP, UDP port)

### Message Types Supported
| Type | Name | Size | Fields Extracted |
|------|------|------|------------------|
| 'A' | Add Order | 36 bytes | Order ref, Buy/Sell, Shares, Symbol, Price |
| 'E' | Order Executed | 31 bytes | Order ref, Executed shares, Match number |
| 'X' | Order Cancel | 23 bytes | Order ref, Cancelled shares |
| 'S' | System Event | 12 bytes | Event Code (O/S/Q/M/E/C) |
| 'R' | Stock Directory | 39 bytes | Symbol, Market Category, Financial Status, Round Lot Size |

### Defense-in-Depth Packet Filtering

**Layer 1: MAC Filtering** ([mac_parser.vhd](src/mac_parser.vhd))
- Board MAC: `00:18:3E:04:5D:E7`
- Broadcast: `FF:FF:FF:FF:FF:FF`
- Blocks unicast traffic to other devices

**Layer 2: IP Protocol Filtering** ([ip_parser.vhd](src/ip_parser.vhd))
- Protocol: `0x11` (UDP only)
- Blocks TCP, ICMP, etc.

**Layer 3: IP Checksum Validation**
- Rejects malformed packets

**Layer 4: UDP Length Validation** ([udp_parser.vhd](src/udp_parser.vhd))
- Validates header and payload length fields

**Layer 5: UDP Port Filtering** ([mii_eth_top.vhd](src/mii_eth_top.vhd))  **NEW**
- Target port: `12345` (configurable constant)
- Combinational filtering (zero-delay, preserves alignment)
- Blocks DNS, mDNS, SSDP, and other broadcast traffic

**Layer 6: ITCH Message Length Validation** ([itch_parser.vhd](src/itch_parser.vhd))
- Per-message-type expected length checking

**Result:** Professional-grade filtering prevents spurious message detection from random network traffic.

### Build Version Management  **NEW**

Auto-incrementing build version system for bitstream verification:
- Build counter stored in `build_version.txt` (git-ignored)
- Auto-increments on every build via TCL script
- Passed to top-level as `BUILD_VERSION` generic
- Displayed in build log: `BUILD VERSION: 6`
- Ensures correct bitstream is programmed to FPGA

### Statistics and Monitoring
- Total message counter
- Per-message-type counters (Add/Execute/Cancel/SystemEvent/StockDir)
- Parse error detection and counting
- LED display modes (7 modes via switches)
- Activity indicator (blinks on message reception)

### Debug Output
- UART 115200 baud ASCII output
- Human-readable message formatting
- Field values displayed in hexadecimal
- Real-time message streaming

**Example Output:**
```
[#00] [ITCH] Type=A Ref=00000000000F4241 B/S=B Shr=00000064 Sym=4141504C20202020 Px=0016E360
[#01] [ITCH] Type=S EventCode=4F
[#02] [ITCH] Type=R Market=51 FinalStat=4E Roundlot=00000064 Symboles=4141504C20202020
[#03] [ITCH] Type=E Ref=00000000000F4245 ExecShr=00000032 Match=000000024CB016EA
[#04] [ITCH] Type=X Ref=00000000000F4246 CxlShr=00000019
```

## Architecture

### v3 Major Refactoring: Async FIFO Architecture 

**Version 3 represents a complete architectural redesign** to eliminate race conditions and message loss/duplication issues encountered in v2.

**The Problem (v2):**
- Messages passed via CDC with pending flags and edge detection
- Race conditions: SET and CLEAR of pending flags could occur in same cycle
- Symptoms: Message loss (alternating messages dropped), message duplication (every message appeared twice)
- 20+ failed attempts to fix race conditions with various flag clearing strategies
- Fundamental architectural limitation: impossible to reliably manage pending flags across clock domains

**The Solution (v3):**
- **Async FIFO with Gray Code CDC** at clock domain boundary (25 MHz → 100 MHz)
- Natural message queuing eliminates need for pending flags
- No race conditions possible - write and read in separate clock domains
- Clean separation of concerns: parser → encoder → FIFO → decoder → formatter

**Architecture Benefits:**
1. ✅ No message loss - messages queue naturally in FIFO (depth 512)
2. ✅ No message duplication - each message written once, read once
3. ✅ No race conditions - CDC handled by gray code pointer synchronization
4. ✅ Easy to extend - adding P/Q/U/D messages requires only encoder/decoder updates
5. ✅ Cleaner code - uart_itch_formatter reduced from 677 lines to 395 lines
6. ✅ Overflow protection - encoder detects and reports message loss if buffers fill (v35+)

**Files Changed/Created in v3:**
- **NEW:** [itch_msg_pkg.vhd](src/itch_msg_pkg.vhd) - Message encoding/decoding package (324-bit serialization)
- **NEW:** [itch_msg_encoder.vhd](src/itch_msg_encoder.vhd) - Parser → FIFO adapter (25 MHz domain)
- **NEW:** [async_fifo.vhd](src/async_fifo.vhd) - Dual-clock FIFO with gray code CDC
- **NEW:** [itch_msg_decoder.vhd](src/itch_msg_decoder.vhd) - FIFO → Formatter adapter (100 MHz domain)
- **REWRITTEN:** [uart_itch_formatter.vhd](src/uart_itch_formatter.vhd) - Simplified to read from FIFO
- **UPDATED:** [mii_eth_top.vhd](src/mii_eth_top.vhd) - Wire new architecture, remove old CDC synchronizers

**Build History:**
- v1-v29: Race condition debugging attempts (v2 codebase)
- v31: Internal FIFO attempt (still had multiple driver issues)
- v33-v34: Async FIFO architecture (v3 codebase) - **WORKING**
- v35-v45: Overflow detection and diagnostics added

### Module Hierarchy

```
mii_eth_top (top-level)
├── PLL (25 MHz eth_rx_clk → 100 MHz sys_clk)
├── PHY Reset Generator
├── Button Handling (debouncer + edge detector)
├── MDIO Subsystem
│   ├── mdio_controller
│   └── mdio_phy_monitor
├── Ethernet Receiver Pipeline (25 MHz domain)
│   ├── mii_rx (MII physical interface)
│   ├── mac_parser (MAC frame parsing + filtering)
│   ├── ip_parser (IPv4 header + checksum)
│   ├── udp_parser (UDP header + validation)
│   ├── UDP port filter (combinational)
│   ├── itch_parser (ITCH protocol - 5 message types)
│   └── itch_msg_encoder (serialize to 324-bit FIFO format)  **NEW v3**
├── Clock Domain Crossing (Async FIFO)  **NEW v3**
│   └── async_fifo (512-deep, gray code CDC, 324-bit wide)
├── UART Formatter Pipeline (100 MHz domain)
│   ├── itch_msg_decoder (deserialize from FIFO)  **NEW v3**
│   └── uart_itch_formatter (simplified, reads from FIFO)  **REWRITTEN v3**
├── Statistics and Display
│   └── itch_stats_counter (uses simple 2FF sync for valid signals)
└── UART TX
    └── uart_tx
```

### Data Flow (v3 Architecture)

```
═══════════════════════════════════════════════════════════
25 MHz Clock Domain (eth_rx_clk)
═══════════════════════════════════════════════════════════
Ethernet PHY (MII)
    ↓ (4-bit nibbles, DDR)
MII RX (nibble → byte assembly)
    ↓ (bytes + frame detection)
MAC Parser + MAC Filter
    ↓ (MAC payload, board/broadcast only)
IP Parser + Protocol Filter (UDP only)
    ↓ (IP payload)
UDP Parser + Length Validation
    ↓ (UDP payload stream)
UDP Port Filter (port 12345 only)
    ↓ (filtered payload)
ITCH Parser (5 message types: A,E,X,S,R)
    ↓ (parsed message fields + valid signals)
ITCH Message Encoder  **NEW v3**
    ↓ (324-bit serialized: 4-bit type + 320-bit data)
    ↓
═══════════════════════════════════════════════════════════
Async FIFO (512-deep, Gray Code CDC)  **NEW v3**
Write: 25 MHz → Read: 100 MHz
═══════════════════════════════════════════════════════════
    ↓
═══════════════════════════════════════════════════════════
100 MHz Clock Domain (sys_clk)
═══════════════════════════════════════════════════════════
ITCH Message Decoder  **NEW v3**
    ↓ (decoded fields: msg_type + all data fields)
UART ITCH Formatter  **REWRITTEN v3**
    ↓ (human-readable ASCII formatting)
UART TX
    ↓ (115200 baud serial)
Terminal
═══════════════════════════════════════════════════════════

Statistics Path (parallel to main data flow):
ITCH Parser (25 MHz)
    ↓ (valid signals only, via simple 2FF sync)
ITCH Stats Counter (100 MHz)
    ↓
LEDs
```

### State Machine (itch_parser.vhd)

```
IDLE
  ↓ (udp_payload_start)
COUNT_BYTES (capture fields at specific offsets)
  ↓ (byte_counter == expected_length)
COMPLETE (assert msg_valid, set type-specific valid)
  ↓
IDLE

ERROR (unknown type or truncated message)
  ↓
IDLE
```

**Critical Implementation Detail:** Field registers are NOT cleared in IDLE state to allow Clock Domain Crossing (CDC) synchronizers adequate sampling time (3-4 cycles). Registers hold values until overwritten by next message.

## Pin Assignments

Constraints file: `constraints/arty_a7_100t.xdc`

### Ethernet MII Interface
| Signal | Pin | Description |
|--------|-----|-------------|
| eth_rx_clk | G18 | 25 MHz RX clock from PHY |
| eth_rxd[3:0] | F16, F14, E18, D18 | RX data nibbles |
| eth_rx_ctl | D17 | RX data valid (CRS_DV) |
| eth_mdc | H16 | MDIO clock (2.5 MHz) |
| eth_mdio | K13 | MDIO data |
| eth_rst_n | C16 | PHY reset (active-low) |

### User Interface
| Signal | Pin | Description |
|--------|-----|-------------|
| clk (100 MHz) | E3 | System clock input |
| led[3:0] | H5, J5, T9, T10 | Status LEDs |
| sw[2:0] | A8, C11, C10 | Display mode select |
| btn[0] | D9 | Statistics report trigger |
| uart_tx | D10 | UART debug output |

## Building the Design

### Prerequisites
- Vivado 2025.1 (or compatible version)
- Windows PC (universal build.tcl works on Windows)
- Git for version control

### Build Commands

Use the universal build script from repository root:

```batch
REM Full build (synthesis + implementation + bitstream)
REM Auto-increments build version
build 07-itch-parser-v2

REM Program FPGA
prog 07-itch-parser-v2
```

Build time: ~10-15 minutes on typical desktop

**Build Version:** Displayed in build log:
```
==========================================
BUILD VERSION: 6
==========================================
```

## Testing

### Hardware Setup

1. Connect Arty A7 to a PC via USB (JTAG + UART) or network switch
2. Connect Ethernet cable from PC/Network switch to Arty A7
3. Configure the new Ethernet port(Arty A7) IP to 192.168.1.100
3. If not using network switch, configure PC Ethernet adapter:
   - IP: 192.168.1.10
   - Subnet: 255.255.255.0
   - No gateway needed
4. If using network switch, all that is required is the Arty MAC address from mii_eth_top
    ```
    -- MAC address --> check label on top of the ethernet port
    constant MY_MAC_ADDR : STD_LOGIC_VECTOR(47 downto 0) := x"00183E045DE7"; 
    ```
    Add a static IP from your network to the test script target and update Arty MAC address

### Test Procedure

#### 1. System Event Test  **NEW**

```batch
REM Open serial terminal (115200 baud, 8N1)
python -m serial.tools.miniterm COM3 115200

REM In another terminal, send system event
cd 07-itch-parser-v2\test
python send_itch_packets.py --target 192.168.1.10 --port 12345 --test system_event
```

**Expected UART output:**
```
[#00] [ITCH] Type=S EventCode=4F
```
Shows: System Event, Code 0x4F = 'O' (Start of Messages)

**Event Codes:**
- `4F` = 'O' (Start of Messages)
- `53` = 'S' (Start of System Hours)
- `51` = 'Q' (Start of Market Hours)
- `4D` = 'M' (End of Market Hours)
- `45` = 'E' (End of System Hours)
- `43` = 'C' (End of Messages)

#### 2. Stock Directory Test  **NEW**

```batch
python send_itch_packets.py --target 192.168.1.10 --port 12345 --test stock_directory
```

**Expected UART output:**
```
[#00] [ITCH] Type=R Market=51 FinalStat=4E Roundlot=00000064 Symboles=4141504C20202020
```
Shows: Stock Directory, Market='Q', Financial Status='N' (Normal), 100 shares round lot, Symbol=AAPL

#### 3. Add Order Test

```batch
python send_itch_packets.py --target 192.168.1.10 --port 12345 --test add_order
```

**Expected UART output:**
```
[#00] [ITCH] Type=A Ref=00000000000F4241 B/S=B Shr=00000064 Sym=4141504C20202020 Px=0016E360
```
Shows: Add Order, Reference 1000001, Buy, 100 shares, AAPL, Price $60.00

#### 4. Complete Market Simulation

```batch
python send_itch_packets.py --target 192.168.1.10 --port 12345 --test complete
```

Sends full market day sequence:
1. System Events (O, S, Q)
2. Stock Directory (AAPL, GOOGL, MSFT, TSLA, SPY, QQQ)
3. Trading activity (Add/Execute/Cancel)
4. System Events (M, E, C)

**Verification:**
- All 5 message types appear correctly
- No spurious messages from network noise
- LED counter increments
- No parse errors

#### 5. Port Filtering Verification  **NEW**

To verify port filtering is working:

1. Generate background network traffic (DNS, mDNS, SSDP):
```batch
REM Open browser, perform Google search to generate DNS traffic
REM Enable network discovery to generate mDNS/SSDP
```

2. Send ITCH messages on port 12345:
```batch
python send_itch_packets.py --target 192.168.1.10 --port 12345 --test add_order
```

**Expected:** Only ITCH messages appear, no spurious Type='E' or garbage from DNS/mDNS

**Without port filtering:** Random UDP broadcasts would trigger false message detection

### LED Display Modes

Use switches SW[2:0] to select display mode:

| SW[2:0] | Mode | Display |
|---------|------|---------|
| 000 | Total messages | Lower 4 bits of message count |
| 001 | Add Order count | Lower 4 bits of Add Order count |
| 010 | Execute count | Lower 4 bits of Execute count |
| 011 | Cancel count | Lower 4 bits of Cancel count |
| 100 | Error count | Lower 4 bits of error count |
| 101 | Last message type | Lower 4 bits of last type (ASCII) |
| 110 | Activity | All LEDs blink on message |

### Troubleshooting

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| No UART output | Wrong COM port | Check Device Manager for port number |
| LEDs not changing | Not receiving packets | Verify IP/port 12345, check Wireshark |
| Parse errors | Malformed packets | Verify packet format with Wireshark |
| Truncated messages | UDP packet too short | Check send_itch_packets.py message lengths |
| Spurious messages | Port filtering disabled | Verify ITCH_UDP_PORT = 12345 in code |
| All zeros in fields | CDC timing violation | Verify registers not cleared in IDLE state |
| LD5 Blue ON | Encoder overflow | CRITICAL: Message rate exceeds capacity, check overflow_count via JTAG |

## Performance Metrics

### Throughput

- **Messages per second:** 10,000+ (typical ITCH feed rate)
- **Parse latency:** < 1 microsecond (< 25 clock cycles @ 25 MHz)
- **Total latency (wire-to-parsed):** < 5 microseconds

### Resource Utilization

Estimated for Artix-7 XC7A100T:

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| Slice LUTs | 4000-4500 | 63,400 | 6-7% |
| Slice Registers | 3500-4000 | 126,800 | 3% |
| BRAM Tiles | 2-4 | 135 | 1-3% |
| DSP Slices | 0 | 240 | 0% |

*(Actual values depend on synthesis optimization)*

### Timing

- **System clock:** 100 MHz (10 ns period)
- **Ethernet RX clock:** 25 MHz (40 ns period)
- **Worst Negative Slack (WNS):** > 0 ns (timing met)
- **Critical path:** Typically in CDC synchronizers or field extraction logic

## Implementation Details

### MII Timing and Byte Alignment (Critical)

**Problem:** The MII interface operates at 25 MHz receiving 4-bit nibbles, assembling them into bytes every 2 clock cycles. Each assembled byte remains stable for 2 consecutive clock cycles at 12.5 MHz byte rate.

**Critical Discovery:** When the state machine transitions from IDLE to COUNT_BYTES on `udp_payload_start='1'`, the type byte (byte 0) remains visible for one additional clock cycle. This causes an off-by-one error if processing on even byte_counter values (0, 2, 4, 6...).

**Solution:** Process ITCH data bytes on ODD byte_counter values (1, 3, 5, 7...). This skips the repeated type byte and correctly captures data bytes.

**Byte Counter Mapping Formula:**
```
Physical byte N → byte_counter = 2*N - 1
Example: byte 11 (Order Ref MSB) → byte_counter = 21
```

**Implementation Pattern:**
```vhdl
-- Check for odd byte counter with modulo operator
if byte_counter >= 1 and (byte_counter mod 2) = 1 then
    case byte_counter is
        when 21 => field_reg(63 downto 56) <= udp_payload_data;  -- Byte 11
        when 23 => field_reg(55 downto 48) <= udp_payload_data;  -- Byte 12
        -- etc.
    end case
end if
```

**Why This Works:**
- Type byte captured in IDLE state on `payload_start='1'`
- In COUNT_BYTES, byte_counter=0: Type byte still visible (ignored)
- byte_counter=1: First data byte (byte 1) - NOW we start processing
- byte_counter=3: Second data byte (byte 2)
- Pattern continues: odd counters = valid data

This timing issue is fundamental to the MII interface and must be respected in all byte-by-byte parsing logic.

### Clock Domain Crossing (CDC) - Critical Fix 

**The Problem:** ITCH parser runs at 25 MHz (eth_rx_clk), UART formatter at 100 MHz (sys_clk). Field data and valid signals must cross clock domains safely.

**Initial Bug:** Field registers were cleared in IDLE state immediately after asserting valid signal. At 25 MHz, data was only stable for ~40ns (1 cycle). The 100 MHz CDC synchronizer needs 2-3 cycles (~20-30ns) to sample the valid signal, but by then the data was already cleared to zeros.

**Solution:** Do NOT clear field registers in IDLE state. Let them hold values until overwritten by next message. This gives CDC synchronizers 3-4 cycles (~120-160ns @ 25 MHz) to sample data correctly.

**Implementation:**
```vhdl
when IDLE =>
    if udp_payload_start = '1' and udp_payload_valid = '1' then
        current_msg_type <= udp_payload_data;
        expected_length <= get_msg_length(udp_payload_data);
        byte_counter <= 0;

        -- DO NOT clear field registers here!
        -- They must remain stable for CDC sampling
        -- Registers will be overwritten with new data during COUNT_BYTES
```

**CDC Synchronizer Pattern (mii_eth_top.vhd):**
```vhdl
-- 2-FF synchronizer for valid signals (single-bit)
process(clk)
begin
    if rising_edge(clk) then
        itch_system_event_valid_sync1 <= itch_system_event_valid;
        itch_system_event_valid_sync2 <= itch_system_event_valid_sync1;
    end if;
end process;

-- Sample multi-bit data on FIRST sync stage
process(clk)
begin
    if rising_edge(clk) then
        if itch_system_event_valid_sync1 = '1' then
            itch_event_code_sync <= itch_event_code;  -- Sample on sync1
        end if;
    end if;
end process;

-- Use SECOND sync stage for edge detection in formatter
process(clk)
begin
    if rising_edge(clk) then
        if itch_system_event_valid_sync2 = '1' and itch_system_event_valid_prev = '0' then
            -- Rising edge detected, data is stable
        end if;
        itch_system_event_valid_prev <= itch_system_event_valid_sync2;
    end if;
end process;
```

**Why This Works:**
- Valid signal synchronized through 2 FF stages (metastability protection)
- Data sampled on sync1 (when valid is stable in 100 MHz domain)
- Edge detection on sync2 (after data has been captured)
- Data remains stable for 3-4 cycles minimum (not cleared in IDLE)

### UDP Port Filtering - Combinational Implementation 

**The Challenge:** Filter UDP payload signals based on destination port, but avoid introducing registered delays that would misalign `payload_start` with `payload_data`.

**Failed Approach #1:** Registered filtering inside clocked process
```vhdl
-- WRONG - introduces 1-cycle delay
process(eth_rx_clk)
begin
    if rising_edge(eth_rx_clk) then
        if port_match = '1' then
            payload_start_filtered <= payload_start;  -- Delayed!
        end if;
    end if;
end process;
```

**Problem:** When `payload_start='1'` and `payload_data=0x41` ('A'), the filtered signal becomes '1' one cycle later when data has already moved to next byte.

**Correct Approach:** Combinational filtering with timing fix
```vhdl
-- Latch port match (registered)
process(eth_rx_clk)
begin
    if rising_edge(eth_rx_clk) then
        if udp_valid = '1' then
            if unsigned(udp_dst_port) = ITCH_UDP_PORT then
                port_match <= '1';  -- Latched for entire packet
            else
                port_match <= '0';
            end if;
        end if;
        if payload_end = '1' then
            port_match <= '0';  -- Clear at packet end
        end if;
    end if;
end process;

-- Combinational filtering (zero delay)
-- Check BOTH latched flag AND current udp_valid for first cycle
payload_start_filtered <= payload_start when (port_match = '1' or
                                               (udp_valid = '1' and unsigned(udp_dst_port) = ITCH_UDP_PORT))
                          else '0';
```

**Why This Works:**
- Port match decision latched when UDP header validated
- Filtering uses combinational `when/else` (no clock delay)
- First cycle: `udp_valid='1'` check catches payload_start immediately
- Subsequent cycles: latched `port_match='1'` passes data through
- **Zero registered delay** = perfect alignment preserved

### System Event Message ('S') - 12 bytes 

**ITCH Specification (Page 4):**
```
Byte  0:    Message Type = 'S' (0x53)
Bytes 1-2:  Stock Locate (big-endian uint16)
Bytes 3-4:  Tracking Number (big-endian uint16)
Bytes 5-10: Timestamp (big-endian uint48, nanoseconds since midnight)
Byte  11:   Event Code (ASCII char)
```

**Event Codes:**
- 'O' (0x4F) = Start of Messages
- 'S' (0x53) = Start of System Hours
- 'Q' (0x51) = Start of Market Hours
- 'M' (0x4D) = End of Market Hours
- 'E' (0x45) = End of System Hours
- 'C' (0x43) = End of Messages

**Implementation (itch_parser.vhd):**
```vhdl
elsif current_msg_type = MSG_SYSTEM_EVENT and byte_counter >= 1 and (byte_counter mod 2) = 1 then
    if byte_counter = 1 then
        stock_locate_reg(15 downto 8) <= udp_payload_data;  -- Byte 1 MSB
    elsif byte_counter = 3 then
        stock_locate_reg(7 downto 0) <= udp_payload_data;   -- Byte 2 LSB
    -- Timestamp bytes 5-10 (counters 9-19)
    elsif byte_counter = 21 then
        event_code_reg <= udp_payload_data;  -- Byte 11: Event Code
    end if;
end if;
```

### Stock Directory Message ('R') - 39 bytes 

**ITCH Specification (Page 4-6):**
```
Byte  0:     Message Type = 'R' (0x52)
Bytes 1-2:   Stock Locate
Bytes 3-4:   Tracking Number
Bytes 5-10:  Timestamp
Bytes 11-18: Stock Symbol (8 ASCII chars, right-padded with spaces)
Byte  19:    Market Category (Q/G/S/N/A/P/Z)
Byte  20:    Financial Status (N/D/E/Q/G/H/J/K)
Bytes 21-24: Round Lot Size (big-endian uint32)
Bytes 25-38: Additional fields (Round Lots Only, Issue Classification, etc.)
```

**Implementation (itch_parser.vhd):**
```vhdl
elsif current_msg_type = MSG_STOCK_DIR and byte_counter >= 1 and (byte_counter mod 2) = 1 then
    -- Stock Symbol: bytes 11-18 (counters 21,23,25,27,29,31,33,35)
    if byte_counter = 21 then
        stock_symbol_reg(63 downto 56) <= udp_payload_data;  -- 'A'
    elsif byte_counter = 23 then
        stock_symbol_reg(55 downto 48) <= udp_payload_data;  -- 'A'
    elsif byte_counter = 25 then
        stock_symbol_reg(47 downto 40) <= udp_payload_data;  -- 'P'
    elsif byte_counter = 27 then
        stock_symbol_reg(39 downto 32) <= udp_payload_data;  -- 'L'
    elsif byte_counter = 29 then
        stock_symbol_reg(31 downto 24) <= udp_payload_data;  -- ' '
    elsif byte_counter = 31 then
        stock_symbol_reg(23 downto 16) <= udp_payload_data;  -- ' '
    elsif byte_counter = 33 then
        stock_symbol_reg(15 downto 8) <= udp_payload_data;   -- ' '
    elsif byte_counter = 35 then
        stock_symbol_reg(7 downto 0) <= udp_payload_data;    -- ' '
    elsif byte_counter = 37 then
        market_category_reg <= udp_payload_data;  -- Byte 19
    elsif byte_counter = 39 then
        financial_status_reg <= udp_payload_data;  -- Byte 20
    elsif byte_counter = 41 then
        round_lot_size_reg(31 downto 24) <= udp_payload_data;  -- Byte 21 MSB
    elsif byte_counter = 43 then
        round_lot_size_reg(23 downto 16) <= udp_payload_data;  -- Byte 22
    elsif byte_counter = 45 then
        round_lot_size_reg(15 downto 8) <= udp_payload_data;   -- Byte 23
    elsif byte_counter = 47 then
        round_lot_size_reg(7 downto 0) <= udp_payload_data;    -- Byte 24 LSB
    end if;
end if;
```

### Big-Endian Field Extraction

ITCH uses network byte order (big-endian). Multi-byte fields captured MSB-first using odd byte counters:

```vhdl
-- Price field (4 bytes at physical offset 32-35, byte_counter 63-69)
elsif current_msg_type = x"41" and byte_counter >= 1 and (byte_counter mod 2) = 1 then
    if byte_counter = 63 then
        price_reg(31 downto 24) <= udp_payload_data;  -- Byte 32 (MSB)
    elsif byte_counter = 65 then
        price_reg(23 downto 16) <= udp_payload_data;  -- Byte 33
    elsif byte_counter = 67 then
        price_reg(15 downto 8) <= udp_payload_data;   -- Byte 34
    elsif byte_counter = 69 then
        price_reg(7 downto 0) <= udp_payload_data;    -- Byte 35 (LSB)
    end if;
end if;
```

Resulting `price_reg` contains value in FPGA-native format, ready for processing.

### Price Representation

ITCH prices are 4-byte integers representing 1/10000 dollars:
- ITCH value: 0x0016E360 = 1,500,000
- Actual price: 1,500,000 / 10,000 = $150.00

### Symbol Encoding

Symbols are 8-byte ASCII strings, right-padded with spaces:
- "AAPL    " = 0x4141504C20202020
- "SPY     " = 0x5350592020202020
- "GOOGL   " = 0x474F4F474C202020

### Error Handling

Parser detects:
1. **Unknown message types** → Skip entire message, increment error counter
2. **Truncated messages** → Discard, return to IDLE, increment error counter
3. **Malformed UDP packets** → Ignore, wait for next packet
4. **Wrong UDP port** → Blocked before reaching parser (port filter)

Recovery strategy: Always return to IDLE on `udp_payload_end`.

## Project Statistics

- **Lines of Code:** ~1,600 VHDL (Phase 2 + Phase 3 modules)
- **Development Time:** ~200 hours intensive development after business hours and incl. weekends
- **Test Cases:** 6 automated Python scripts
- **Documentation:** Complete specification + comprehensive README
- **Build Versions:** 45+ tracked builds (v1-v45 since build counter added in v2; many more untracked builds in Projects 1-6)

## Known Issues

None currently reported. All critical bugs fixed in Phase 2 and Phase 3.

## Lessons Learned

### 1. MII Timing and Byte Alignment (Critical Discovery - Phase 1)
**The Problem:** MII interface outputs bytes every 2 clock cycles (12.5 MHz byte rate). When state machine transitions from IDLE to COUNT_BYTES, the message type byte remains visible for 1 extra cycle, causing off-by-one errors.

**The Solution:** Process data on ODD byte_counter values (1,3,5,7...) instead of even. This skips the repeated type byte and correctly captures payload bytes. Formula: Physical byte N → byte_counter = 2*N - 1.

**Impact:** This is fundamental to MII-based parsing. All byte-offset logic must account for this timing behavior. Debugging required extensive cycle-by-cycle analysis to discover the root cause.

### 2. Clock Domain Crossing Requires Stable Data (Critical - Phase 2) 
**The Problem:** Field registers were cleared in IDLE state immediately after pulsing valid signal. At 25 MHz, data only stable for 1 cycle (~40ns). CDC synchronizer at 100 MHz needs 2-3 cycles to sample valid and data, but data was already zeros by then.

**The Solution:** Do NOT clear field registers in IDLE. Hold values until overwritten by next message. This gives CDC 3-4 cycles (~120-160ns) to sample correctly.

**Impact:** All CDC interfaces require data stability analysis. Register clearing must consider downstream sampling requirements. This bug caused ALL fields to appear as zeros despite correct parsing.

### 3. Orphaned elsif Chain Bug (Critical - Phase 2) 
**The Problem:** Extra `end if;` at line 435 of itch_parser.vhd closed the message type if/elsif chain BEFORE System Event and Stock Directory elsif conditions, leaving them orphaned outside any if block.

**Why It Compiled:** The orphaned elsif was inside an outer `if udp_payload_valid = '1'` block, so VHDL compiler accepted it as unreachable "dead code" rather than syntax error.

**Impact:** System Event and Stock Directory field extraction code NEVER executed, all fields remained at reset values (zeros). Demonstrates importance of careful code structure review beyond compiler checks.

### 4. UDP Port Filtering Timing Race (Phase 2) 
**The Problem:** When `udp_valid='1'` sets `port_match='1'`, the new value isn't visible until next clock cycle. If `payload_start` occurs on same cycle as `udp_valid`, it gets blocked because `port_match` still reads '0'.

**The Solution:** Use combinational filtering that checks BOTH latched `port_match` flag AND current `udp_valid` signal. First cycle caught by udp_valid check, subsequent cycles use latched flag.

**Impact:** Demonstrates need for combinational logic in time-critical filtering paths. Registered filtering introduces delays that misalign related signals.

### 5. Registered Filtering Breaks Alignment (Phase 2) 
**The Problem:** Initial port filtering used registered assignments (`<=` inside clocked process). This introduced 1-cycle delay, causing `payload_start_filtered` to pulse one cycle after `payload_data` had already advanced to next byte. Parser sampled wrong byte as message type.

**The Solution:** Use combinational filtering (`when/else` concurrent assignment) for payload signals. Only latch the port match decision, not the filtered signals themselves.

**Impact:** When filtering multi-signal interfaces (valid/start/data), alignment is critical. Registered delays can break protocol timing. Always use combinational logic for signal gating.

### 6. Defense in Depth is Professional Engineering (Phase 2) 
**The Principle:** Implement filtering at every protocol layer, not just one. Each layer catches different error classes and attack vectors.

**Implementation:**
- Layer 1: MAC filtering (blocks wrong recipients)
- Layer 2: IP protocol filtering (blocks non-UDP)
- Layer 3: IP checksum validation (blocks corruption)
- Layer 4: UDP length validation (blocks malformed packets)
- Layer 5: UDP port filtering (blocks wrong applications)
- Layer 6: ITCH message validation (blocks protocol errors)

**Impact:** Professional-grade code doesn't rely on single point of validation. Even though MAC+IP+UDP filtering caught most garbage, UDP port filtering adds crucial defense against application-layer noise (DNS, mDNS, SSDP).

### 7. Build Version Management is Essential (Phase 2) 
**The Problem:** I've programmed wrong bitstream (07-itch-parser instead of 07-itch-parser-v2), causing confusion about whether new features were implemented.

**The Solution:** Auto-incrementing build version in TCL script, displayed in build log, passed to VHDL as generic. Provides verification that correct bitstream is programmed.

**Impact:** In professional development, build tracking is mandatory. Prevents "it works on my machine" issues and enables bisecting bugs to specific builds.

### 8. Parser Completion Check Timing (Critical - Phase 3)
**The Problem:** Completion check used `byte_counter >= 2 * (expected_length - 1)` after incrementing, but VHDL signal assignments occur at end of process. The check evaluated the old value before increment, causing premature or missed completion detection.

**The Solution:** Check completion condition BEFORE increment using `(byte_counter + 1) >= 2 * (expected_length - 1)`. This correctly evaluates the next counter value that will exist after the assignment completes.

**Impact:** Incorrect completion detection caused messages to not complete properly or complete prematurely, leading to lost or corrupted messages. Signal assignment timing must be considered in all conditional logic.

### 9. Back-to-Back Message Handling (Critical - Phase 3)
**The Problem:** Parser transitioned from COMPLETE to IDLE unconditionally. If next packet's `payload_start` arrived while parser was in COMPLETE state, it was ignored because parser only checked for `payload_start` in IDLE state.

**The Solution:** Check for next `payload_start` in COMPLETE state before transitioning to IDLE. If `payload_start` is detected, begin parsing immediately without returning to IDLE first.

**Impact:** Rapidly arriving messages (back-to-back packets) were lost. State machines must handle immediate transitions without intermediate idle states when processing continuous data streams.

### 10. Encoder Missing Valid Pulses (Critical - Phase 3)
**The Problem:** Encoder used single-stage capture mechanism that could miss 1-cycle valid pulses if FIFO was busy or logic evaluated conditions in wrong order. Valid signals pulse for exactly one cycle, and encoder might not capture them if processing previous message.

**The Solution:** Implement two-stage capture mechanism: `captured_msg` register always captures valid pulses immediately (highest priority), then `msg_buffer` holds messages waiting for FIFO space. This ensures no valid pulse is ever missed, regardless of FIFO state.

**Impact:** Messages were lost when encoder failed to capture valid pulses during FIFO writes or buffer management. Time-critical interfaces require prioritized capture logic that never misses single-cycle events.

### 11. Race Conditions in Pending Flag Architecture (Critical - v2→v3 Refactor) 
**The Problem:** v2 architecture used pending flags with edge detection for CDC. Flags were set when parser detected message, cleared when formatter completed transmission. When SET and CLEAR conditions were both true in same cycle, race condition occurred causing either message loss or duplication.

**Failed Attempts (v9-v29):**
- v9-v17: Clear flags on various state transitions (IDLE→SEND_*, WAIT_TX→IDLE, byte_index=0) → Message loss (alternating messages dropped)
- v18-v20: Clear on SEND_*→IDLE transition → Infinite loop (messages repeated 41+ times)
- v21-v26: Clear on WAIT_TX→IDLE transition → Message duplication (every message appeared twice)
- v27-v29: Handshake signals for clearing → Multiple driver errors

**Root Cause:** Impossible to reliably manage SET/CLEAR of flags across two processes (edge detection + FSM) without race conditions.

**The Solution:** Complete architectural refactor to async FIFO with gray code CDC (v3):
- Eliminated pending flags entirely
- Messages queue naturally in FIFO (512-deep)
- Gray code pointer synchronization handles CDC safely
- Write and read in separate clock domains → no race conditions possible

**Impact:** After 20+ failed attempts to fix race conditions, recognized need for fundamental architecture change. Sometimes the right solution is to redesign, not debug. v3 architecture is production-ready foundation for v4 (additional message types).

### 12. FIFO Depth Sizing for Burst Handling (v3)
**The Problem:** Initial FIFO depth of 8 might overflow during message bursts when formatter (UART 115200 baud, ~87μs per byte) is slower than parser (25 MHz, ~40ns per byte).

**The Solution:** Increased FIFO depth from 8 to 512 entries. At 324 bits/entry, this is 20,736 bytes of buffering.

**Calculation:** AAPL stock typically generates 1000+ messages/second during market hours. At 36 bytes/message average, burst rate can be 36KB/second. FIFO @ 512 deep can buffer ~0.6 seconds of continuous messages.

**Impact:** Proper FIFO sizing prevents overflow during burst traffic. Must account for worst-case producer/consumer rate mismatch.

### 13. Two-Stage Capture for Single-Cycle Valid Pulses (v3)
**The Problem:** ITCH parser asserts valid signals for exactly 1 cycle (40ns @ 25 MHz). If encoder is busy writing to FIFO or managing buffer, it might miss the pulse.

**The Solution:** Encoder uses two-stage capture:
- `captured_msg` register: Always captures valid pulse immediately (highest priority, never blocks)
- `msg_buffer`: Holds messages waiting for FIFO space (secondary storage)
- Priority: Write from buffer first, then from captured message, then capture new arrivals

**Impact:** Guarantees no valid pulse is ever missed, regardless of FIFO state or encoder logic timing. Critical for time-sensitive interfaces with single-cycle events.

### 14. Encoder Overflow Protection - Defense Against Silent Failure (v35+)
**The Problem:** Initial encoder had two-stage capture (`captured_msg` + `msg_buffer`), but if both stages were full when new valid pulse arrived, message would be silently dropped. Comment said "captured message is lost" but no diagnostic visibility.

**The Risk:** With 512-deep FIFO providing 0.6 seconds of buffering, overflow is extremely unlikely. But "should never happen" is not the same as "cannot happen." Silent message loss in production trading system is unacceptable.

**The Solution:** Added overflow detection and diagnostics:
- `overflow_error` output: Pulses for 1 cycle when message dropped
- `overflow_count` output: 16-bit counter of total lost messages (saturates at 0xFFFF)
- **LD5 Blue LED**: Latches ON when overflow occurs (stays lit until board reset)
- **Visual critical error**: Operator immediately knows something is wrong

**Implementation:**
```vhdl
else
    -- OVERFLOW: Both buffer and captured_msg are full
    overflow_error_reg <= '1';
    if overflow_count_reg /= x"FFFF" then
        overflow_count_reg <= overflow_count_reg + 1;
    end if;
    -- Drop the captured message (no choice)
    captured_msg.valid <= '0';
end if;
```

**Impact:** Converts potential silent failure into visible, diagnosable error. Professional systems must detect and report failure modes, even "impossible" ones. LD5 Blue LED provides immediate visual feedback that sustained message rate exceeded system capacity. Operator can check overflow_count via debugger to quantify loss.

### 15. Lots of Debugging Time (Phase 1, 2, 3 & v3 Refactor)
It required considerable time to debug and troubleshoot issues with ITCH Parser. Each critical bug (MII timing, CDC timing, orphaned elsif, port filtering, completion check, encoder capture, race conditions) required systematic analysis and multiple build iterations. The v2→v3 refactor alone took 20+ build attempts before recognizing architectural redesign was needed. Patience and methodical debugging are essential skills. Know when to debug vs. when to redesign.

## Next Steps

### Version 4 (Starting from v3 Codebase)
**v4 will be a copy of v3 with additional message types implemented**

**Plan:**
1. Copy 07-itch-parser-v3 → 07-itch-parser-v4 (clean v3 architecture as foundation)
2. Update encoder/decoder to support P, Q, U, D message types
3. Update parser to extract fields for new message types
4. Update formatter to display new message types
5. Test with complete ITCH feed simulation

**Benefits of v3 Foundation:**
- Clean async FIFO architecture (no race conditions)
- Easy to extend (just update encoder/decoder/parser)
- Proven stable with 5 message types

### Phase 4 (v4): Additional Message Types
- **'P'** - Trade Non-Cross (44 bytes)
- **'Q'** - Trade Cross (40 bytes)
- **'U'** - Order Replace (35 bytes)
- **'D'** - Order Delete (19 bytes)
- Complete ITCH 5.0 core message support

### Phase 5 (v4+): Symbol Filtering
- Configurable symbol filter list (4-8 symbols)
- Only process messages for specified symbols
- Filtered vs total message statistics
- BRAM-based symbol lookup table

### Phase 6: Integration with Order Book (Project 8)
- Feed parsed messages to hardware order book
- Build price-level data structure
- Track best bid/offer (BBO)
- DDR3 storage for order book depth

## References

### Protocol Specifications
- [Nasdaq ITCH 5.0 Specification](https://www.nasdaqtrader.com/content/technicalsupport/specifications/dataproducts/NQTVITCHspecification.pdf)
- IEEE 802.3: Ethernet Standard
- RFC 791: Internet Protocol (IPv4)
- RFC 768: User Datagram Protocol

### Hardware Documentation
- Digilent Arty A7 Reference Manual
- Xilinx Artix-7 FPGA Datasheet (DS181)
- TI DP83848J PHY Datasheet
- AMD Vivado Design Suite User Guide (UG893)

### Related Projects
- Project 06: UDP Parser (Phase 1E) - Foundation
- Project 08: Hardware Order Book (Planned)
- Project 09: DDR3 Integration (Planned)

## License

Educational project for FPGA learning and career transition into high-frequency trading.

---

**Development Notes:**
- All field extraction verified against Nasdaq ITCH 5.0 specification
- Parser handles variable-length messages correctly (12-39 bytes)
- Statistics counters tested up to 1M messages without overflow
- UART formatter provides immediate feedback for debugging
- Multi-layer filtering prevents spurious message detection
- Build version system ensures correct bitstream deployment

---

**Project Status:** ✅ **Project 7 v3 - ITCH 5.0 Parser with Async FIFO Architecture COMPLETE**

**Hardware Status:** ✅ Synthesized, Programmed, and Verified on Arty A7-100T

**Quality Metrics:** **14 Critical Bugs Fixed**, **Major Architectural Refactor**, Clean Synthesis, **100% Message Parsing Accuracy**, **Zero Race Conditions**, **No Message Loss/Duplication**, **Overflow Detection & Diagnostics**

## Version History

### v2 (Archived - Race Condition Architecture)
- Used pending flags + edge detection for CDC
- 20+ failed attempts to fix race conditions (v9-v29)
- Issues: Message loss, duplication, infinite loops
- **Deprecated**: Fundamental architecture limitations

### v3 (Current - Async FIFO Architecture)
- Complete architectural redesign
- Async FIFO with gray code CDC eliminates race conditions
- 4 new modules created, uart_itch_formatter rewritten (677→395 lines)
- Overflow detection and diagnostics added (v35+)
- Proven stable with 5 message types
- **Production ready** - foundation for v4

## Bugs Fixed (All Phases + v3 Refactor)

### Phase 1 Bugs (v1-v8)
1. **MII Timing/Byte Alignment** - MII 2-cycle byte timing requires odd byte_counter processing (1,3,5,7...)
2. **Signal Name Mismatch** - Fixed captured_match_number → captured_match_num
3. **MAC Filtering** - Re-enabled MAC address filtering (was in debug mode)

### Phase 2 Bugs (v9-v29)
4. **CDC Timing Violation** - Field registers cleared too early. Fixed by NOT clearing in IDLE state.
5. **Orphaned elsif Chain** - Extra `end if;` made System Event/Stock Directory unreachable
6. **Missing financial_status Port** - Stock Directory output not connected
7. **UDP Port Filter Timing Race** - payload_start blocked on first cycle. Fixed with combinational filtering.

### Phase 3 Bugs (v30-v32)
8. **Parser Completion Check Timing** - Used byte_counter after increment. Fixed by checking (byte_counter + 1) before increment.
9. **Back-to-Back Message Handling** - Parser missed messages arriving in COMPLETE state. Fixed by checking payload_start before returning to IDLE.
10. **Encoder Missing Valid Pulses** - Single-cycle pulses missed when busy. Fixed with two-stage capture (captured_msg + msg_buffer).

### v3 Architecture Bugs (v9-v34)
11. **Race Conditions - Message Loss** (v9-v17) - Pending flags cleared on wrong transitions → alternating messages dropped
12. **Race Conditions - Infinite Loop** (v18-v20) - Clear condition never triggered → messages repeated 41+ times
13. **Race Conditions - Message Duplication** (v21-v29) - SET/CLEAR in same cycle → every message appeared twice

**Solution:** Complete refactor to async FIFO architecture (v33-v34) - **ALL RACE CONDITIONS ELIMINATED**

### v3 Improvements (v35+)
14. **Silent Message Loss Risk** (v35-v45) - Two-stage encoder could drop messages if both buffers full. Added overflow detection (`overflow_error`, `overflow_count`), LD5 Blue LED indicator (latched until reset). Converts silent failure to visible, diagnosable error.

## v3 Architecture Changes

**New Modules:**
- [async_fifo.vhd](src/async_fifo.vhd) - Dual-clock FIFO with gray code CDC (124 lines)
- [itch_msg_pkg.vhd](src/itch_msg_pkg.vhd) - Message encoding/decoding package (174 lines)
- [itch_msg_encoder.vhd](src/itch_msg_encoder.vhd) - Parser→FIFO adapter (105 lines)
- [itch_msg_decoder.vhd](src/itch_msg_decoder.vhd) - FIFO→Formatter adapter (78 lines)

**Rewritten Modules:**
- [uart_itch_formatter.vhd](src/uart_itch_formatter.vhd) - Simplified to read from FIFO (677→395 lines, 41% reduction)

**Updated Modules:**
- [mii_eth_top.vhd](src/mii_eth_top.vhd) - Wire async FIFO architecture, remove old CDC synchronizers

**Message Types Implemented:**
- Add Order ('A') - 36 bytes
- Order Executed ('E') - 31 bytes
- Order Cancel ('X') - 23 bytes
- System Event ('S') - 12 bytes
- Stock Directory ('R') - 39 bytes

**v3 Benefits:**
- ✅ No message loss
- ✅ No message duplication
- ✅ No race conditions
- ✅ Clean architecture (easy to extend for P/Q/U/D in v4)
- ✅ 512-deep FIFO handles message bursts
- ✅ Overflow detection with visual LED indicator (v35+)
- ✅ Production-ready foundation

**Ready For:** **Version 4 - Additional Message Types (P, Q, U, D)**

**Last Updated:** November 10, 2025 - **v3 COMPLETE - Async FIFO Architecture with Overflow Protection (Build v45)**
