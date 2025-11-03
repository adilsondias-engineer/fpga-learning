# Project 5: UART Communication with Trading-Style Binary Protocol

![Project Status](https://img.shields.io/badge/status-complete-brightgreen)
![FPGA](https://img.shields.io/badge/FPGA-Artix--7-blue)
![Language](https://img.shields.io/badge/language-VHDL-orange)
![Protocol](https://img.shields.io/badge/protocol-binary-green)
![Hardware Verified](https://img.shields.io/badge/hardware-verified-brightgreen)

A professional UART communication system on Xilinx Artix-7 FPGA featuring dual-protocol support (binary + ASCII), FIFO buffering, and checksum validation - demonstrating skills directly applicable to high-frequency trading systems.

**Target Hardware:** Digilent Arty A7-100T Development Board

---

## Quick Start (5 Minutes)

**Prerequisites:** Arty A7-100T + USB cable | Vivado 2025.1 | Python 3.x + PySerial

### 1. Build & Program

```bash
# From repository root
vivado -mode batch -source build.tcl -tclargs 05-uart-transmitter
vivado -mode batch -source program.tcl -tclargs 05-uart-transmitter
```

### 2. Automated Testing

```bash
cd 05-uart-transmitter/test
python uart.py
```

**Expected Output:**

```
Testing binary protocol...

1. Setting counter to 0x10
   Sending: AA 01 01 10 10

2. Querying counter value
   Response: 31 30 = b'10'
   PASS ✓

3. Adding 0x05 to counter
   Sending: AA 02 01 05 06

4. Querying counter after add
   Response: b'15'
   PASS ✓
```

### 3. Manual Testing (Optional)

**Serial Terminal Settings:**

- Port: COM7 (Windows) or /dev/ttyUSB\* (Linux)
- Baud: 115200
- Data: 8 bits, No parity, 1 stop bit

**Try These Commands:**

```
I       # Increment counter
Q       # Query (returns hex value like "01")
```

**Binary Protocol Example:**

```
Send: AA 01 01 42 42    (Set counter to 0x42)
```

**Result:** FPGA processes commands, validates checksums, echoes responses, displays data on LEDs.

---

## Overview

This project evolved from a simple UART echo system into a sophisticated dual-protocol communication platform, demonstrating the complexity of real-world trading system message handlers.

### Core Features

- **Dual Protocol Support:** Trading-style binary protocol (efficient) + ASCII commands (debug)
- **UART Communication:** 115200 baud, 8N1 format, full-duplex
- **Message Validation:** XOR checksum for data integrity
- **FIFO Buffering:** 16-byte queue for asynchronous data handling
- **Hardware Interface:** Button controls with professional debouncing
- **Visual Feedback:** RGB LED status indicators with pulse stretching
- **Test Automation:** Python-based protocol validation

### Trading System Relevance

| Feature                 | Trading Application                         |
| ----------------------- | ------------------------------------------- |
| **Binary Protocol**     | Mirrors FIX, ITCH, OUCH exchange protocols  |
| **Checksum Validation** | Data integrity critical for order execution |
| **Message Framing**     | START_BYTE enables resynchronization        |
| **FIFO Buffering**      | Packet queuing for burst market data        |
| **State Machines**      | Professional approach to protocol parsing   |
| **Multi-Protocol**      | Control plane (ASCII) + data plane (binary) |

---

## Architecture

### Binary Protocol (Trading-Style)

**Message Format:**

```
[START_BYTE][CMD][LENGTH][DATA...][CHECKSUM]
   0xAA      u8    u8      N bytes    u8
```

**Checksum Calculation:**

```
CHECKSUM = CMD ⊕ LENGTH ⊕ DATA[0] ⊕ DATA[1] ⊕ ... ⊕ DATA[N-1]
```

**Example Message (Set counter to 0x42):**

```
AA 01 01 42 42
│  │  │  │  └─ Checksum: 0x01 ⊕ 0x01 ⊕ 0x42 = 0x42
│  │  │  └──── Data: 0x42
│  │  └─────── Length: 1 byte
│  └────────── Command: 0x01 (Set)
└───────────── Start byte: 0xAA
```

**Supported Commands:**

| CMD  | Function       | Length | Data       | Response         |
| ---- | -------------- | ------ | ---------- | ---------------- |
| 0x01 | Set counter    | 1      | Value (u8) | None             |
| 0x02 | Add to counter | 1      | Value (u8) | None             |
| 0x03 | Query counter  | 0      | -          | 2-char hex ASCII |
| 0x04 | Write to FIFO  | N      | Data bytes | None             |
| 0x05 | Read from FIFO | 0      | -          | All queued data  |

### ASCII Command Interface (Legacy/Debug)

| Command | Function             | Response                |
| ------- | -------------------- | ----------------------- |
| `R`     | Reset counter        | None                    |
| `I`     | Increment counter    | None                    |
| `D`     | Decrement counter    | None                    |
| `Q`     | Query counter        | 2-char hex (e.g., "5A") |
| `S`     | FIFO status          | 2-char hex count        |
| `G`     | Get all FIFO data    | Transmits queued bytes  |
| Other   | Echo + store in FIFO | Echoes character        |

### Block Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     UART Echo Top                            │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │ UART RX  │───▶│  Binary  │───▶│ Command  │              │
│  │ 115200   │    │ Protocol │    │ Handler  │              │
│  └──────────┘    │  Parser  │    └──────────┘              │
│       │          └──────────┘          │                    │
│       │                 │              │                    │
│       ▼                 ▼              ▼                    │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐             │
│  │  ASCII   │───▶│ Counter  │───▶│   FIFO   │             │
│  │ Command  │    │  (8-bit) │    │ 16-byte  │             │
│  │  Parser  │    └──────────┘    └──────────┘             │
│  └──────────┘          │              │                    │
│       │                │              │                    │
│       ▼                ▼              ▼                    │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐            │
│  │ UART TX  │◀───│ Hex-to-  │◀───│ Display  │            │
│  │  Echo    │    │  ASCII   │    │ 4 LEDs   │            │
│  └──────────┘    └──────────┘    └──────────┘            │
│       ▲                                 ▲                  │
│       │          ┌──────────┐           │                 │
│       └──────────│  Button  │───────────┘                 │
│                  │ Debouncer│                             │
│                  └──────────┘                             │
└──────────────────────────────────────────────────────────┘
```

### State Machine (Protocol Parser)

**States:**

- `WAIT_RX` → Waiting for input (ASCII or binary START_BYTE)
- `PROTO_WAIT_CMD` → Binary protocol: reading command byte
- `PROTO_WAIT_LEN` → Binary protocol: reading length byte
- `PROTO_WAIT_DATA` → Binary protocol: reading N data bytes
- `PROTO_WAIT_CSUM` → Binary protocol: validating checksum
- `PROTO_PROCESS` → Binary protocol: executing command
- `ECHO_TX` → Transmitting echo/response
- `SEND_HEX_LOW` → Sending second hex digit
- `SEND_FIFO_DATA` → Transmitting FIFO contents

**Key Design Decision:** Unified state machine eliminates race conditions between ASCII and binary protocol handlers (see Lessons Learned).

---

## Hardware Interface

### Button Functions

| Button | Function             | Edge Detection           |
| ------ | -------------------- | ------------------------ |
| BTN0   | System reset         | Rising edge              |
| BTN1   | Clear counter & LEDs | Rising edge              |
| BTN2   | Send test char 'A'   | Rising edge              |
| BTN3   | Send "HELLO" message | Rising edge (sequential) |

All buttons feature professional 3-stage synchronizer + 20ms debounce + edge detection.

### LED Indicators

**Standard LEDs (4-bit):** Display lower nibble of last received/transmitted byte

**RGB LED 0 (Status):**

- **Red:** Receiving data (100ms pulse stretch)
- **Green:** Transmitting data (100ms pulse stretch)
- **Blue:** Idle (no activity)

_Pulse stretching makes brief signals visible to human eye (10ns → 100ms)_

### Pin Assignments (Arty A7-100T)

**UART:**
| Signal | FPGA Pin | Description |
|--------|----------|-------------|
| uart_txd_in (RX) | A9 | Receive from PC |
| uart_rxd_out (TX) | D10 | Transmit to PC |

_Note: Xilinx naming is confusing - RXD_OUT means FPGA transmits!_

**LEDs:**
| Signal | FPGA Pins | Description |
|--------|-----------|-------------|
| led[3:0] | H5, J5, T9, T10 | 4-bit data display |
| led0_r | G6 | RGB Red |
| led0_g | F6 | RGB Green |
| led0_b | E1 | RGB Blue |

**Buttons:**
| Signal | FPGA Pin | Function |
|--------|----------|----------|
| btn(0) | D9 | System reset |
| btn(1) | C9 | Clear counter/LEDs |
| btn(2) | B9 | Send 'A' test character |
| btn(3) | B8 | Send "HELLO" (sequential) |

---

## Building the Project

### Prerequisites

- Xilinx Vivado 2020.1 or later (tested on 2025.1)
- Digilent Arty A7-100T board
- Micro-USB cable for programming and UART
- Python 3.x with `pyserial` for testing

### Command-Line Build (Recommended)

**From repository root:**

```bash
# Synthesize, Implement, Generate Bitstream
vivado -mode batch -source build.tcl -tclargs 05-uart-transmitter

# Program FPGA
vivado -mode batch -source program.tcl -tclargs 05-uart-transmitter
```

### GUI Build

1. Open project: `File → Project → Open: 05-uart-transmitter.xpr`
2. Run complete flow:
   - `Flow → Run Implementation`
   - `Flow → Generate Bitstream`
   - `Flow → Open Hardware Manager`
   - `Program Device`

### Testing

**Automated (Recommended):**

```bash
cd 05-uart-transmitter/test
python uart.py
```

**Manual Testing:**

- Open PuTTY/TeraTerm/screen
- Port: COM7 (Windows) or /dev/ttyUSB\* (Linux)
- Settings: 115200, 8N1, no flow control

**Test Commands:**

```
Type: I I I Q    → Counter increments, query returns "03"
Type: R Q        → Reset counter, query returns "00"
Type: Hello S G  → Store in FIFO, check status, retrieve
```

**Binary Protocol Testing:**

```bash
# Use Python script for automated validation
python test/uart.py

# Or send binary manually (requires hex-capable terminal)
AA 01 01 10 10  → Set counter to 0x10
AA 03 00 03     → Query counter (returns "10")
```

---

## Technical Specifications

| Parameter             | Value                           |
| --------------------- | ------------------------------- |
| **FPGA Clock**        | 100 MHz                         |
| **UART Baud Rate**    | 115200 bps                      |
| **UART Format**       | 8N1 (8 data, no parity, 1 stop) |
| **Data Width**        | 8 bits                          |
| **FIFO Depth**        | 16 bytes                        |
| **Debounce Time**     | 20 ms                           |
| **LED Pulse Stretch** | 100 ms                          |
| **Logic Levels**      | 3.3V LVCMOS                     |
| **Button Logic**      | Active-low (Arty A7)            |

---

## Known Issues & Debug History

### ✅ FIXED: Binary Protocol Race Condition

**Status:** RESOLVED - Unified state machine implemented (03/11/2025)

**Symptom:** Binary protocol bytes echoed to host, causing test failures.

**Root Cause:** Two separate VHDL processes (protocol parser + ASCII echo) evaluated on same clock edge, both saw old signal values, creating race condition.

**Failed Attempts (4 total):**

1. `protocol_active` flag - both processes saw old '0'
2. Remove redundant reset - same race
3. Check `protocol_state` directly - 1-cycle delay
4. Double-check (state AND flag) - same timing issue

**Solution:** Merged into unified state machine that routes bytes immediately in same cycle:

```vhdl
when WAIT_RX =>
    if rx_valid = '1' then
        if rx_data = START_BYTE then
            state <= PROTO_WAIT_CMD;  -- Binary protocol
        else
            case rx_data is           -- ASCII commands
                when X"52" => -- 'R'
                when X"49" => -- 'I'
                -- ...
            end case;
        end if;
    end if;
```

**Why This Works:** Single process makes routing decision without inter-process communication delay.

**Key Lesson:** Architectural problems require architectural solutions - cannot fix multi-process race conditions with flags.

### ✅ FIXED: RGB LEDs Not Visible

**Status:** RESOLVED - 100ms pulse stretching implemented (03/11/2025)

**Symptom:** RGB LED always blue, red/green invisible.

**Root Cause:** Pulses too brief for human perception:

- Red (rx_valid): 10ns @ 100MHz
- Green (tx_busy): ~87μs per byte

**Solution:** Added 100ms pulse stretchers (10,000,000 clock cycles)

```vhdl
-- Stretch rx_valid to 100ms
if rx_valid = '1' then
    led_r_stretch <= LED_STRETCH_TIME;
elsif led_r_stretch > 0 then
    led_r_stretch <= led_r_stretch - 1;
end if;
```

### ✅ FIXED: Other Issues

- **Query returning wrong data** - Reading `last_received` instead of `value_counter`
- **Unprintable hex output** - Missing nibble-to-ASCII conversion
- **16x digit repetition** - Low nibble from stale register
- **Single hex character** - Missing `tx_started` handshake flag
- **Echo only when button pressed** - Inverted reset logic

_Full debug history documented in README for portfolio demonstration._

---

## Design Decisions

### Why Trading-Style Binary Protocol?

- **Efficiency:** Binary more compact than ASCII (saves bandwidth)
- **Checksums:** Data integrity validation critical in trading
- **Framing:** START_BYTE + LENGTH enables resynchronization after errors
- **Professional:** Mirrors real exchange protocols (FIX, ITCH, OUCH)

### Why Dual Protocol (Binary + ASCII)?

- **Production:** Binary protocol for efficiency
- **Debug:** ASCII for human-readable testing
- **Educational:** Demonstrates both approaches
- **Real-world:** Control plane (ASCII) + data plane (binary) separation

### Why FIFO Buffering?

- **Async Handling:** Queues data when system busy
- **Burst Support:** Handles multiple rapid inputs
- **Flow Control:** Full/empty flags prevent data loss
- **Trading:** Mirrors order queue in trading systems

### Why Unified State Machine?

- **No Race Conditions:** Single process eliminates inter-process timing issues
- **Deterministic:** Clear routing decision in same cycle
- **Maintainable:** Easier to debug than distributed logic
- **Professional:** Matches production FPGA design patterns

---

## Lessons Learned

### Critical Insights

**VHDL Timing:**

- Signal assignments take effect NEXT clock cycle
- Reading signal immediately after assignment returns OLD value
- Multiple processes on same clock edge see identical old values
- Cannot solve inter-process race conditions with flags

**UART Best Practices:**

- Mid-bit sampling reduces noise sensitivity
- Busy flags prevent transmission collisions
- `tx_started` flag for proper wait-for-start-then-end handshake
- Metastability protection mandatory on async inputs

**Protocol Design:**

- Always use checksums for data integrity
- Frame with start bytes enables resynchronization
- Length prefixes support variable-length messages
- State machines are professional approach to parsing

**Development Workflow:**

- Python test scripts faster than manual testing
- LED visualization provides instant feedback
- Incremental features (add one at a time)
- Document bugs and fixes (demonstrates learning)

**Trading System Relevance:**

- FIFOs essential for packet buffering
- Metastability protection critical for async market data
- Binary protocols more efficient than ASCII
- Checksums detect transmission errors
- Message framing enables recovery from errors

---

## Future Enhancements

### High Priority

- [ ] Comprehensive regression test suite
- [ ] Timeout/retry logic for binary protocol
- [ ] Error reporting to host (NAK messages)

### Medium Priority

- [ ] Support longer binary messages (>2 data bytes)
- [ ] CRC-16 checksum option (stronger than XOR)
- [ ] FIFO overflow/underflow error reporting
- [ ] Message sequence numbers

### Low Priority

- [ ] DMA-style burst transfers
- [ ] Multiple baud rate support
- [ ] Hardware flow control (RTS/CTS)
- [ ] Protocol version negotiation

---

## Project Structure

```
05-uart-transmitter/
├── README.md                    # This file
├── build.tcl                    # Automated build script
├── program.tcl                  # Automated programming script
├── src/
│   ├── uart_echo_top.vhd       # Top-level entity (main logic)
│   ├── uart_rx.vhd             # UART receiver
│   ├── uart_tx.vhd             # UART transmitter
│   ├── button_debouncer.vhd    # Button debouncing
│   ├── edge_detector.vhd       # Edge detection
│   └── fifo.vhd                # FIFO buffer
├── constraints/
│   └── arty_a7_100t.xdc        # Pin assignments and timing
├── simulation/
│   ├── uart_tb.vhd             # UART loopback testbench
│   └── uart_tb_behav.wcfg      # Waveform configuration
└── test/
    └── uart.py                  # Python protocol test script
```

---

## Usage Examples

### ASCII Mode

```
# Basic counter control
I I I         → Counter = 0x03
Q             → Response: "03"
D             → Counter = 0x02
Q             → Response: "02"
R             → Counter = 0x00

# FIFO operations
Hello         → Queued in FIFO (5 bytes)
S             → Response: "05" (5 bytes queued)
G             → Response: "Hello"
S             → Response: "00" (FIFO empty)
```

### Binary Protocol Mode

```python
import serial

ser = serial.Serial('COM7', 115200)

# Set counter to 0x42
msg = bytes([0xAA, 0x01, 0x01, 0x42, 0x42])
ser.write(msg)

# Query counter
msg = bytes([0xAA, 0x03, 0x00, 0x03])
ser.write(msg)
response = ser.read(2)  # Returns b"42"

# Add 0x10 to counter
msg = bytes([0xAA, 0x02, 0x01, 0x10, 0x13])
ser.write(msg)

# Query again
msg = bytes([0xAA, 0x03, 0x00, 0x03])
ser.write(msg)
response = ser.read(2)  # Returns b"52" (0x42 + 0x10)
```

---

## Troubleshooting

### No Characters Received

1. Check baud rate: 115200 bps
2. Verify UART connection (correct COM port)
3. Ensure BTN0 NOT pressed (system reset)
4. Check USB cable (must support data, not just power)
5. Verify FPGA is programmed (check LED activity)

### Characters Echoed But Commands Don't Work

1. Verify character encoding (ASCII, not Unicode)
2. Check for line endings (some terminals send CR+LF)
3. Use hex mode to confirm exact bytes sent
4. Try uppercase commands ('R' not 'r')

### Binary Protocol Issues

1. Verify message format: `[0xAA][CMD][LEN][DATA...][CHECKSUM]`
2. Ensure checksum calculation: XOR of CMD + LEN + all DATA bytes
3. Check baud rate and serial port settings
4. Use test script: `python test/uart.py` to verify functionality
5. Check for unexpected echoes (should be none for binary protocol)

### LEDs Show Wrong Value

1. Endianness: MSB (bit 3) on left, LSB (bit 0) on right
2. Check that counter changed (press I, then Q)
3. Verify LED connections match constraints
4. Only lower 4 bits displayed on standard LEDs

### Python Test Script Fails

1. Ensure PySerial installed: `pip install pyserial`
2. Verify COM port number in script matches your system
3. Close any other programs using the serial port
4. Check FPGA is programmed and not in reset
5. Increase timeouts if using slow PC

---

## Metrics

- **Development Time:** ~34 hours (incremental features + extensive debugging)
- **Lines of VHDL:** ~900 lines (including comments)
- **Test Coverage:** Automated Python tests + manual validation
- **Bug Fixes:** 7 major issues resolved and documented
- **Hardware Verification:** Complete - all features tested on Arty A7-100T

---

## License

This project is provided as-is for educational purposes.

---

## Acknowledgments

- **Hardware:** Digilent Arty A7-100T Development Board
- **Tools:** Xilinx Vivado Design Suite
- **Testing:** Python with PySerial library
- **Inspiration:** Financial trading protocols (FIX, ITCH, OUCH)

---

## Contact

For questions or contributions, please open an issue on GitHub.

---

**Status:** ✅ Complete - All features fully functional  
**Completed:** November 2, 2025  
**Last Updated:** November 3, 2025  
**Hardware:** Xilinx Arty A7-100T (XC7A100T-1CSG324C)

**Recent Fixes:**

- ✅ Binary protocol race condition resolved via unified state machine (03/11/2025)
- ✅ RGB LED visibility fixed with 100ms pulse stretching (03/11/2025)
- ✅ All Python automated tests passing (03/11/2025)

---

_Part of FPGA Learning Journey - Building trading-relevant hardware skills_  
_Portfolio Project: Demonstrates protocol design, state machines, error handling, and professional debugging_
