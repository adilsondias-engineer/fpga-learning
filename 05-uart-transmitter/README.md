# Project 5: UART Echo System with Trading-Style Binary Protocol

A comprehensive UART communication system on Xilinx Artix-7 FPGA featuring ASCII commands, FIFO buffering, and a trading-style binary protocol with checksum validation.

![Project Status](https://img.shields.io/badge/status-in--progress-yellow)
![FPGA](https://img.shields.io/badge/FPGA-Artix--7-blue)
![Language](https://img.shields.io/badge/language-VHDL-orange)
![Protocol](https://img.shields.io/badge/protocol-binary-green)

---

## Overview

This project evolved from a simple UART echo system into a sophisticated communication platform featuring:

- **UART Communication:** 115200 baud, 8N1 format, bidirectional
- **ASCII Command Interface:** Legacy text-based control system
- **Binary Protocol:** Trading-style message framing with checksums
- **FIFO Queue:** 16-byte buffer for data management
- **Button Interface:** Professional debouncing with edge detection
- **Real-time LED Display:** Visual feedback of received data

**Target Hardware:** Digilent Arty A7-100T Development Board

---

## Features

### Core Functionality

#### 1. UART Communication

- **Baud Rate:** 115200 bps
- **Format:** 8 data bits, no parity, 1 stop bit (8N1)
- **Direction:** Full-duplex (transmit and receive)
- **LED Feedback:** Displays last received byte on 8 LEDs

#### 2. ASCII Command Interface (Legacy)

| Command | Function             | Response                |
| ------- | -------------------- | ----------------------- |
| `R`     | Reset counter        | None                    |
| `I`     | Increment counter    | None                    |
| `D`     | Decrement counter    | None                    |
| `Q`     | Query counter        | 2-char hex (e.g., "5A") |
| `S`     | FIFO status          | 2-char hex count        |
| `G`     | Get all FIFO data    | Transmits queued bytes  |
| Other   | Echo + store in FIFO | Echoes character        |

#### 3. Binary Protocol (Trading-Style)

**Message Format:**

```
[START_BYTE][CMD][LENGTH][DATA...][CHECKSUM]
   0xAA      u8    u8      N bytes    u8
```

**Checksum Calculation:**

```vhdl
CHECKSUM = CMD ⊕ LENGTH ⊕ DATA[0] ⊕ DATA[1] ⊕ ... ⊕ DATA[N-1]
```

**Supported Commands:**
| CMD | Function | Length | Data | Response |
|-----|----------|--------|------|----------|
| 0x01 | Set counter | 1 | Value (u8) | None |
| 0x02 | Add to counter | 1 | Value (u8) | None |
| 0x03 | Query counter | 0 | - | 2-char hex ASCII |
| 0x04 | Write to FIFO | N | Data bytes | None |
| 0x05 | Read from FIFO | 0 | - | All queued data |

**Example Message (Set counter to 0x42):**

```
AA 01 01 42 42
│  │  │  │  └─ Checksum: 0x01 ⊕ 0x01 ⊕ 0x42 = 0x42
│  │  │  └──── Data: 0x42
│  │  └─────── Length: 1 byte
│  └────────── Command: 0x01 (Set)
└───────────── Start byte: 0xAA
```

#### 4. FIFO Buffering

- **Capacity:** 16 bytes
- **Commands:** Status query (`S`) and bulk retrieval (`G`)
- **Auto-queue:** Unknown ASCII characters stored automatically
- **Protection:** Write-on-full and read-on-empty guarded

#### 5. Button Interface

| Button | Function             | Edge Detection           |
| ------ | -------------------- | ------------------------ |
| BTN0   | System reset         | Rising edge              |
| BTN1   | Clear counter & LEDs | Rising edge              |
| BTN2   | Send test char 'A'   | Rising edge              |
| BTN3   | Send "HELLO" message | Rising edge (sequential) |

All buttons feature professional 3-stage synchronizer + 20ms debounce + edge detection.

---

## Architecture

### Block Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                         UART Echo Top                              │
│  ┌──────────────┐     ┌──────────────┐      ┌──────────────┐       │
│  │  UART RX     │────▶│   Binary     │─────▶│   Command    │       │
│  │  115200 8N1  │     │   Protocol   │      │   Handler    │       │
│  └──────────────┘     │   Parser     │      └──────────────┘       │
│         │             └──────────────┘              │              │
│         │                     │                     │              │
│         │                     │                     ▼              │
│         ▼                     ▼             ┌──────────────┐       │
│  ┌──────────────┐     ┌──────────────┐     │     FIFO     │       │
│  │   ASCII      │────▶│   Counter    │────▶│   16-byte    │       │
│  │   Command    │     │   (8-bit)    │     │   Queue      │       │
│  │   Parser     │     └──────────────┘     └──────────────┘       │
│  └──────────────┘             │                     │              │
│         │                     │                     │              │
│         ▼                     ▼                     ▼              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐       │
│  │  UART TX     │◀────│   Hex-to-    │◀────│   Display    │       │
│  │  Echo        │     │   ASCII      │     │   8 LEDs     │       │
│  └──────────────┘     └──────────────┘     └──────────────┘       │
│         ▲                                          ▲              │
│         │             ┌──────────────┐             │              │
│         └─────────────│   Button     │─────────────┘              │
│                       │   Debouncer  │                            │
│                       └──────────────┘                            │
└────────────────────────────────────────────────────────────────────┘
```

### Component Descriptions

#### 1. UART Receiver (`uart_rx.vhd`)

- **Baud Clock Generator:** Divides 100MHz to 115200 baud
- **State Machine:** IDLE → START → DATA[0:7] → STOP
- **Sampling:** Mid-bit sampling for noise immunity
- **Output:** `rx_valid` pulse with `rx_data` byte

#### 2. UART Transmitter (`uart_tx.vhd`)

- **Transmission:** START bit → 8 data bits → STOP bit
- **Busy Flag:** Indicates transmission in progress
- **Handshake:** `tx_start` pulse initiates transmission
- **Start Detection:** `tx_started` flag for proper timing

#### 3. Binary Protocol Parser (State Machine)

**States:**

- `IDLE` → Waiting for START_BYTE (0xAA)
- `WAIT_CMD` → Reading command byte
- `WAIT_LENGTH` → Reading data length
- `WAIT_DATA` → Reading N data bytes
- `WAIT_CHECKSUM` → Validating checksum
- `PROCESS_CMD` → Executing command

**Checksum Validation:**

```vhdl
-- Accumulate XOR during receive
checksum_calc <= checksum_calc XOR rx_data

-- Validate at end
if rx_data = checksum_calc then
    -- Command valid
else
    -- Discard and return to IDLE
end if
```

#### 4. ASCII Command Parser

- **Character-based:** Single-byte commands
- **Immediate Execution:** No buffering required
- **Echo Capability:** Unknown chars echoed + stored
- **Hex Output:** Nibble-to-ASCII conversion for queries

#### 5. Button Debouncer (`button_debouncer.vhd`)

- **3-Stage Synchronizer:** Metastability protection
- **Counter-based:** 20ms stable detection
- **Parameters:**
  - Clock: 100 MHz
  - Debounce time: 20ms (configurable)

#### 6. Edge Detector (`edge_detector.vhd`)

- **Rising/Falling:** Separate outputs for both edges
- **Single-cycle Pulse:** Converts level to action trigger

---

## Known Issues & Debug History

### 🔧 **FIXED: Binary Protocol Echo Race Condition**

**Status:** ✅ RESOLVED - Unified state machine implemented

**Original Symptom:**
Binary protocol command/data bytes were being echoed back to the host, causing tests to fail.

**Example of Bug:**

```python
Send: AA 01 01 10 10
Receive: 01 10  # Unwanted echo!
```

**Root Cause:**
The protocol parser and ASCII echo handler existed in **separate VHDL processes**. When bytes arrived, both processes evaluated on the **same clock edge** and saw the **same old signal values**, creating a race condition.

**Failed Fix Attempts (4 attempts):**

1. **`protocol_active` flag** - ❌ Both processes saw old value '0'
2. **Remove redundant reset** - ❌ Same race condition
3. **Check `protocol_state` directly** - ❌ State transitions have 1-cycle delay
4. **Double-check (state AND flag)** - ❌ Same fundamental timing issue

**Fundamental Issue:**
Two separate processes reading the same signals on the same clock edge will always see old values, regardless of flags or state checks used.

**SUCCESSFUL SOLUTION:**
Merged both handlers into a **unified state machine** ([uart_echo_top.vhd:353-660](src/uart_echo_top.vhd#L353-L660)) that routes bytes immediately:

```vhdl
when WAIT_RX =>
    elsif rx_valid = '1' then
        -- Check START_BYTE in same cycle!
        if rx_data = START_BYTE then
            protocol_checksum_calc <= (others => '0');
            state <= PROTO_WAIT_CMD;  -- Route to binary protocol
        else
            -- Route to ASCII handler
            case rx_data is
                when X"52" => -- 'R' Reset
                when X"49" => -- 'I' Increment
                ...
            end case;
        end if;
    end if;
```

**Why This Works:**
Single process reads `rx_data` and routes to appropriate handler immediately in the same cycle - no inter-process communication delay.

**Test Results:**

```
1. Setting counter to 0x10
   Sending: AA 01 01 10 10
   (No unexpected echo!)  ✅

2. Querying counter value
   Response: 31 30 = b'10'
   PASS  ✅

3. Adding 0x05 to counter
   Sending: AA 02 01 05 06

4. Querying counter after add
   Response: b'15'
   PASS  ✅
```

**Date Fixed:** 03/11/2025

---

### 🔧 **FIXED: 'Q' Command Sending Wrong Data**

**Symptom:** Query command sent "PTY" instead of counter value

**Root Cause:** VHDL signal timing - reading `last_received` instead of `value_counter`

```vhdl
-- WRONG
tx_data <= last_received;  -- Old value from previous cycle

-- FIXED
tx_data <= std_logic_vector(value_counter);  -- Direct read
```

**Status:** ✅ Fixed

---

### 🔧 **FIXED: Hex Output Showing Unprintable Characters**

**Symptom:** Raw binary sent instead of ASCII hex

**Root Cause:** Missing nibble-to-hex conversion

**Solution:** Implemented conversion function

```vhdl
function nibble_to_hex(nibble : std_logic_vector(3 downto 0))
    return std_logic_vector is
begin
    case nibble is
        when X"0" => return X"30";  -- '0'
        when X"1" => return X"31";  -- '1'
        ...
        when X"F" => return X"46";  -- 'F'
    end case;
end function;
```

**Status:** ✅ Fixed

---

### 🔧 **FIXED: 16x Digit Repetition Bug**

**Symptom:** Pressing I then Q showed "000...111...222..." (each digit 16 times)

**Root Cause:** Low nibble read from stale `last_received` instead of `value_counter`

**Solution:** Read both nibbles from same source

```vhdl
-- High nibble
tx_data <= nibble_to_hex(value_counter(7 downto 4));

-- Low nibble (in SEND_HEX_LOW state)
tx_data <= nibble_to_hex(value_counter(3 downto 0));  -- Not last_received!
```

**Status:** ✅ Fixed

---

### 🔧 **FIXED: Only Sending One Hex Character**

**Symptom:** Query returned single character instead of two

**Root Cause:** Checking `tx_busy = '0'` immediately without waiting for transmission to start first

**Solution:** Added `tx_started` handshake flag

```vhdl
when ECHO_TX =>
    if tx_busy = '1' then
        tx_started <= '1';  -- Wait for start
    elsif tx_started = '1' and tx_busy = '0' then
        -- Now transmission completed
        tx_started <= '0';
        if send_second_hex = '1' then
            -- Send low nibble
            tx_data <= nibble_to_hex(query_value(3 downto 0));
            tx_start <= '1';
            send_second_hex <= '0';
            echo_state <= SEND_HEX_LOW;
        else
            echo_state <= WAIT_RX;
        end if;
    end if;
```

**Status:** ✅ Fixed

---

### 🔧 **FIXED: UART Echo Only Works When BTN0 Pressed**

**Symptom:** Characters only echoed while holding button

**Root Cause:** Inverted reset logic for active-low buttons

```vhdl
-- WRONG (button='1' when NOT pressed on Arty A7)
reset <= not btn(0);  -- System always in reset!

-- FIXED
reset <= btn(0);  -- Active high from debounced button
```

**Status:** ✅ Fixed

---

### 🔧 **FIXED: RGB LEDs Not Visible (Too Fast)**

**Status:** ✅ RESOLVED - Pulse stretching implemented

**Symptom:**
RGB LED was always blue, red and green LEDs never visible to human eye.

**Root Cause:**
Signal pulses too brief for human perception:

- **Red (rx_valid):** Only 10ns @ 100MHz → invisible
- **Green (tx_busy):** ~87μs per byte → barely visible flash
- **Blue (idle):** Constant true → always on

**Solution:**
Added 100ms pulse stretchers ([uart_echo_top.vhd:670-692](src/uart_echo_top.vhd#L670-L692)):

```vhdl
-- RGB LED pulse stretchers (100ms @ 100MHz = 10,000,000 cycles)
constant LED_STRETCH_TIME : integer := 10_000_000;
signal led_r_stretch : integer range 0 to LED_STRETCH_TIME := 0;
signal led_g_stretch : integer range 0 to LED_STRETCH_TIME := 0;

process(clk)
begin
    if rising_edge(clk) then
        -- Red: Stretch rx_valid pulse
        if rx_valid = '1' then
            led_r_stretch <= LED_STRETCH_TIME;
        elsif led_r_stretch > 0 then
            led_r_stretch <= led_r_stretch - 1;
        end if;

        -- Green: Stretch tx_busy
        if tx_busy = '1' then
            led_g_stretch <= LED_STRETCH_TIME;
        elsif led_g_stretch > 0 then
            led_g_stretch <= led_g_stretch - 1;
        end if;
    end if;
end process;

-- LED assignments
led0_r <= '1' when led_r_stretch > 0 else '0';
led0_g <= '1' when led_g_stretch > 0 else '0';
led0_b <= '1' when state = WAIT_RX and led_r_stretch = 0 and led_g_stretch = 0 else '0';
```

**Result:**

- Red LED now visible for 100ms when receiving data
- Green LED now visible for 100ms when transmitting
- Blue LED only shows when truly idle (not receiving/transmitting)

**Date Fixed:** 03/11/2025

---

## Technical Specifications

| Parameter          | Value                           |
| ------------------ | ------------------------------- |
| **FPGA Clock**     | 100 MHz                         |
| **UART Baud Rate** | 115200 bps                      |
| **UART Format**    | 8N1 (8 data, no parity, 1 stop) |
| **Data Width**     | 8 bits                          |
| **FIFO Depth**     | 16 bytes                        |
| **Debounce Time**  | 20 ms                           |
| **Logic Levels**   | 3.3V LVCMOS                     |
| **Button Logic**   | Active-low (Arty A7)            |

---

## Pin Assignments (Arty A7-100T)

### UART (USB-Serial)

| Signal            | FPGA Pin | Description     |
| ----------------- | -------- | --------------- |
| uart_txd_in (RX)  | A9       | Receive from PC |
| uart_rxd_out (TX) | D10      | Transmit to PC  |

**Note:** Xilinx naming is confusing - RXD_OUT means FPGA transmits!

### LEDs

| Signal   | FPGA Pins                           | Description        |
| -------- | ----------------------------------- | ------------------ |
| led[7:0] | H5, J5, T9, T10, H17, K15, J13, N14 | 8-bit data display |

### Buttons

| Signal | FPGA Pin | Function                  |
| ------ | -------- | ------------------------- |
| btn(0) | D9       | System reset              |
| btn(1) | C9       | Clear counter/LEDs        |
| btn(2) | B9       | Send 'A' test character   |
| btn(3) | B8       | Send "HELLO" (sequential) |

---

## Building the Project

### Prerequisites

- Xilinx Vivado 2020.1 or later (tested on 2025.1)
- Digilent Arty A7-100T board
- Micro-USB cable for programming and UART
- Python 3.x with `pyserial` for testing

### Command-Line Build (Recommended)

**Synthesize, Implement, and Generate Bitstream:**

```bash
cd 05-uart-transmitter
"C:\Xilinx\2025.1\Vivado\bin\vivado.bat" -mode batch -source build.tcl
```

**Program FPGA:**

```bash
"C:\Xilinx\2025.1\Vivado\bin\vivado.bat" -mode batch -source program.tcl
```

### GUI Build

1. **Open Project:**

   ```
   File → Project → Open: 05-uart-transmitter.xpr
   ```

2. **Run Complete Flow:**
   ```
   Flow → Run Implementation
   Flow → Generate Bitstream
   Flow → Open Hardware Manager
   Program Device
   ```

### Testing

**Python Test Script:**

```bash
cd test
python uart.py
```

**Manual Testing (PuTTY/Terminal):**

```
Port: COM7 (Windows) or /dev/ttyUSB* (Linux)
Baud: 115200
Data: 8 bits
Parity: None
Stop: 1 bit
Flow Control: None
```

**Test Commands:**

```
I       # Increment counter
Q       # Query (should show hex like "01")
S       # FIFO status
G       # Get FIFO data
```

---

## Usage

### ASCII Mode

**Basic Counter Control:**

```
Press: I I I    → Counter = 0x03
Press: Q        → Response: "03"
Press: D        → Counter = 0x02
Press: Q        → Response: "02"
Press: R        → Counter = 0x00
```

**FIFO Operations:**

```
Type: Hello     → Queued in FIFO (5 bytes)
Press: S        → Response: "05" (5 bytes queued)
Press: G        → Response: "Hello"
Press: S        → Response: "00" (FIFO empty)
```

### Binary Protocol Mode

**Set Counter Example:**

```python
import serial
ser = serial.Serial('COM7', 115200)

# Set counter to 0x42
msg = bytes([0xAA, 0x01, 0x01, 0x42, 0x42])
ser.write(msg)
```

**Query Counter Example:**

```python
# Query counter
msg = bytes([0xAA, 0x03, 0x00, 0x03])
ser.write(msg)

response = ser.read(2)
print(f"Counter value: {response}")  # Should be ASCII hex like "42"
```

---

## Troubleshooting

### No Characters Received

1. Check baud rate: 115200 bps
2. Verify UART connection (COM port)
3. Ensure BTN0 NOT pressed (system reset)
4. Check USB cable (must support data, not just power)

### Characters Echoed But Commands Don't Work

1. Verify character encoding (ASCII, not Unicode)
2. Check for line endings (some terminals send CR+LF)
3. Use hex mode to confirm exact bytes sent

### Binary Protocol Issues

1. Verify message format: [0xAA][CMD][LEN][DATA...][CHECKSUM]
2. Ensure checksum calculation: XOR of CMD + LEN + all DATA bytes
3. Check baud rate and serial port settings
4. Use test script: `python test/uart.py` to verify functionality

### LEDs Show Wrong Value

1. Endianness: MSB (bit 7) on left, LSB (bit 0) on right
2. Check that counter incremented (press I, then Q)
3. Verify LED connections (low-to-high bit order)

---

## Design Decisions

### Why Trading-Style Binary Protocol?

- **Efficiency:** Binary more compact than ASCII
- **Checksums:** Data integrity validation (critical in trading)
- **Framing:** START_BYTE + LENGTH allows synchronization
- **Professional:** Mirrors real-world exchange protocols (FIX, ITCH)

### Why Separate ASCII Mode?

- **Debugging:** Human-readable for development
- **Legacy Support:** Existing tools/scripts
- **Educational:** Shows both approaches side-by-side

### Why FIFO Buffering?

- **Async Handling:** Queues data when system busy
- **Burst Support:** Handles multiple rapid inputs
- **Real-world:** Mirrors trading system order queues

### Why Button Debouncing?

- **Reliability:** Mechanical switches bounce 5-50ms
- **Metastability:** 3-stage synchronizer prevents clock domain issues
- **Professional:** Production-quality input handling

---

## Lessons Learned

### VHDL Timing Gotchas

1. **Signal assignments take effect NEXT clock cycle** - reading immediately gives old value
2. **Multiple processes see same old values** - creates race conditions
3. **State transitions have 1-cycle delay** - can't use for same-cycle decisions

### UART Best Practices

1. **Mid-bit sampling** - reduces noise sensitivity
2. **Busy flags** - prevent transmission collisions
3. **Started flags** - proper wait-for-start-then-end handshake

### Protocol Design

1. **Always use checksums** - catches transmission errors
2. **Frame with start bytes** - enables resynchronization
3. **Length prefixes** - variable-length messages

### Debugging Techniques

1. **Python test scripts** - faster than manual testing
2. **LED visualization** - instant feedback
3. **Incremental features** - add one at a time

---

## Future Enhancements

### High Priority

- [ ] Add regression test suite
- [ ] Implement timeout/retry logic
- [ ] Add comprehensive error handling and reporting

### Medium Priority

- [ ] Support longer binary messages (>2 bytes)
- [ ] Add CRC-16 checksum option
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
├── README.md                     # This file
├── build.tcl                     # Automated build script
├── program.tcl                   # Automated programming script
├── src/
│   ├── uart_echo_top.vhd        # Top-level entity (main logic)
│   ├── uart_rx.vhd              # UART receiver
│   ├── uart_tx.vhd              # UART transmitter
│   ├── button_debouncer.vhd     # Button debouncing
│   ├── edge_detector.vhd        # Edge detection
│   └── fifo.vhd                 # FIFO buffer
├── constraints/
│   └── arty_a7_100t.xdc         # Pin assignments and timing
└── test/
    └── uart.py                   # Python test script
```

---

## License

This project is provided as-is for educational purposes.

---

## Acknowledgments

- **Hardware:** Digilent Arty A7-100T Development Board
- **Tools:** Xilinx Vivado Design Suite
- **Testing:** Python with pyserial library
- **Inspiration:** Financial trading protocols (FIX, ITCH)

---

## Contact

For questions or contributions, please open an issue on GitHub.

---

- **Built with:** VHDL, Vivado, Python, VS Code, Arty A7-100T, and many debugging sessions
- **Status:** ✅ All features fully functional - Binary protocol and RGB LEDs fixed!
- **Completed:** 02/11/2025
- **Last Updated:** 03/11/2025
- **Time Invested:** ~34 hours (incremental features, extensive debugging, successful fixes)

**Recent Fixes:**

- ✅ Binary protocol race condition resolved via unified state machine (03/11/2025)
- ✅ RGB LED visibility fixed with 100ms pulse stretching (03/11/2025)

---

_Part of FPGA Learning Journey - Building trading-relevant hardware skills_
