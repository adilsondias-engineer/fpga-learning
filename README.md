![FPGA](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7-red)
![Language](https://img.shields.io/badge/Language-VHDL-blue)
![Status](https://img.shields.io/badge/Status-Active%20Learning-green)
![Hardware Verified](https://img.shields.io/badge/Hardware-Verified-brightgreen)
![Projects](https://img.shields.io/badge/Projects-7%20Complete-brightgreen)

# FPGA Learning for Trading Systems

A hands-on journey learning FPGA development with a focus on skills relevant to high-frequency trading and low-latency systems.

## Background

Transitioning from 20+ years of C++ systems engineering and 5 years of active futures trading (S&P 500, Nasdaq) to understand hardware acceleration in trading infrastructure.

## Hardware

- Xilinx Arty A7-100T Development Board
- Artix-7 FPGA (XC7A100T-1CSG324C)
- AMD Vivado Design Suite

## Learning Path

Projects are designed to build from fundamentals toward trading-relevant skills:

- Clock management and timing constraints
- Synchronous design and metastability handling
- Serial communication protocols (UART, SPI)
- Network protocols (Ethernet, MII interface)
- Data processing pipelines
- Hardware timestamping
- Clock domain crossing (CDC)
- FIFO buffers and flow control
- PLL/MMCM clock generation

## Projects

### Completed Projects

1. **Project 01** - Rotary Encoder Counter (Quadrature decoding, debouncing)
2. **Project 02** - Button Debouncer with LED Display (Metastability protection)
3. **Project 03** - FIFO Buffer Implementation (Circular buffer, flow control)
4. **Project 04** - Rotary Encoder with Buzzer (Audio feedback, frequency generation)
5. **Project 05** - UART Transceiver with Binary Protocol (Trading-style message framing)
6. **Project 06** - MII Ethernet Receiver with UDP Parser ✅ **Phase 1F Complete**
   - Phase 1A: MII Physical Layer Reception
   - Phase 1B: MDIO PHY Management
   - Phase 1C: MAC Frame Parsing
   - Phase 1D: IP Header Parsing
   - Phase 1E: UDP Parser (v3b - deprecated due to CDC issues)
   - **Phase 1F (v5): Production-Ready UDP Parser** 
     - **Bug #13 RESOLVED** - Critical CDC race condition fixed
     - Real-time byte-by-byte architecture (1% → 100% success rate)
     - Comprehensive clock domain crossing synchronization
     - XDC timing constraints for production reliability
     - 1000+ packet stress test validation

7. **Project 07** - ITCH 5.0 Protocol Parser ✅ **Phase 1 Complete**
   - Nasdaq market data protocol parsing (Add Order, Order Executed, Order Cancel)
   - **Critical MII Timing Discovery** - Odd byte_counter pattern (1,3,5,7...) required
   - Big-endian field extraction for multi-byte values
   - Enhanced UART formatter with order lifecycle tracking
   - MAC address filtering re-enabled (board MAC + broadcast)
   - 100% message parsing accuracy verified with real ITCH data

Each project includes, where it might be relevant/required:

- Complete VHDL source code
- Comprehensive testbenches with self-checking assertions
- Simulation waveforms
- Constraint files (XDC) with timing analysis
- Hardware verification on Arty A7-100T
- Detailed documentation of concepts and bugs resolved

## Goals

1. Master FPGA development workflow (design -> simulation -> synthesis -> hardware)
2. Build trading-relevant projects (market data parsing, order book, latency measurement)
3. Understand hardware acceleration advantages for low-latency systems
4. Create portfolio demonstrating full-stack engineering (software + hardware)

## Skills Demonstrated

- HDL design (VHDL/SystemVerilog)
- Testbench development and verification
- Waveform analysis and debugging
- Timing constraint management
- Protocol implementation
- State machine design
- Clock domain crossing
- Hardware/software integration

## Skills Demonstrated
### HDL Design & Architecture

- VHDL design - Binary counters, button debouncers, FIFO buffers, rotary encoder interfaces, UART transceivers
- Generic parameters - Configurable debounce timing, FIFO depth, clock division ratios, baud rate generation
- Hierarchical design - Component instantiation and port mapping across multiple modules
- State machine design - Quadrature decoder for rotary encoder, FIFO controller states, UART protocol parsers, unified state machines
- Multi-protocol support - Binary protocol (trading-style) and ASCII command interface coexisting

### Digital Design Fundamentals

- Clock management - Clock division from 100MHz to 1Hz, baud rate generation (115200 bps), PLL/MMCM clock generation (25 MHz reference for Ethernet PHY)
- **Clock Domain Crossing (CDC) mastery** - 2-FF synchronizers for single-bit signals, valid-gated capture for multi-bit buses, reset synchronization across domains, comprehensive XDC constraints (ASYNC_REG, set_false_path), production-ready patterns 
- Metastability protection - Three-stage synchronizer chains for asynchronous inputs, 2FF synchronizers for clock domain crossing
- Debouncing implementation - 20ms stable period filtering for mechanical switches
- Edge detection - Rising/falling edge detection with proper sequential logic ordering
- FIFO buffer architecture - 16-depth x 8-bit circular buffer with full/empty flags
- UART communication - 8N1 format, mid-bit sampling, busy/started handshake flags
- Ethernet communication - MII interface (4-bit nibbles), preamble/SFD stripping, MAC frame parsing with address filtering
- **Real-time protocol parsing** - Position-based state machine triggering (byte_index), deterministic latency, eliminates race conditions vs event-driven approaches 
- Protocol parsing - Binary message framing (START_BYTE, LENGTH, DATA, CHECKSUM), Ethernet frame structure, IP/UDP header extraction
- Pulse stretching - 100ms counters to make brief signals human-visible on LEDs

### Verification & Testing

- Testbench development - Self-checking testbenches with assert statements
- Procedure-based testing - Reusable test procedures for encoder rotation, button presses
- Waveform analysis - Signal debugging in Vivado simulator
- Hardware verification - All designs validated on Xilinx Arty A7-100T (XC7A100T)
- Coverage scenarios - Normal operation, boundary conditions, error states
- Python test scripts - Automated UART protocol testing with PySerial, Ethernet frame injection with Scapy
- Protocol validation - Checksum verification, message framing, error detection, MAC address filtering
- Network testing - Raw Ethernet frame transmission, Wireshark packet analysis

### Hardware Integration

- Peripheral interfaces - Rotary encoder (quadrature decoding), piezo buzzer (frequency generation), USB-UART bridge, Ethernet PHY (DP83848J)
- Serial communication - UART RX/TX at 115200 baud, PC-FPGA communication, echo/command processing
- Network communication - MII Ethernet interface (10/100 Mbps), PHY reset timing (10ms minimum), reference clock generation
- LED displays - Binary counters, 8-bit rainbow LED arrays, RGB status indicators with pulse stretching
- User input handling - Buttons (BTN0-3), switches, rotary encoder with button
- Audio feedback - Frequency-coded buzzer for status transitions (880Hz/523Hz/262Hz)

### Development Workflow

- Synthesis & Implementation - Successful builds through complete Vivado flow
- Constraint management - XDC files for pin assignments, timing constraints
- Simulation methodology - Fast simulation with reduced timing parameters
- Debug techniques - Resolved synthesis/simulation mode conflicts, fixed testbench procedures
- Git workflow - Version control with structured project directories

### Trading-Relevant Skills Built

- Data buffering - FIFO implementation essential for packet queuing
- Flow control - Full/empty flag management for backpressure handling
- **Production CDC techniques** - Systematic clock domain crossing for multi-clock FPGAs (network PHY, processing, memory domains) 
- **Real-time deterministic parsing** - Fixed-latency protocol parsing critical for HFT (applies to ITCH/OUCH) 
- Latency awareness - Understanding of clock cycles and timing paths
- Reliability patterns - Metastability protection mandatory for production systems
- Binary protocols - START_BYTE framing, length-prefixed messages, XOR checksums (mirrors FIX/ITCH/OUCH)
- Message parsing - State machine-based protocol decoder with checksum validation
- Error detection - Checksum mismatches, framing errors, graceful error recovery
- Multi-protocol support - Handling both binary (efficient) and ASCII (debug) interfaces
- Network packet parsing - Ethernet frame reception, MAC address filtering, preamble/SFD detection, IP/UDP header extraction
- Hardware acceleration - Direct PHY interfacing bypasses OS network stack for minimal latency
- **Production debugging** - Systematic root cause analysis, strategic instrumentation, stress testing (1000+ packet validation) 
- **Architectural decision-making** - Knowing when to rewrite vs patch (event-driven → real-time rewrite resolved 99% failure rate) 
- **ITCH Protocol Parsing** - Nasdaq market data format (Add Order, Order Executed, Order Cancel), big-endian field extraction, order lifecycle tracking
- **MII Byte Timing** - Discovered odd byte_counter requirement (1,3,5,7...) due to 2-cycle byte stability and state transition timing

---

_Learning in public. All feedback welcome!_
