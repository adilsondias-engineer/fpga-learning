![FPGA](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7-red)
![Language](https://img.shields.io/badge/Language-VHDL-blue)
![Status](https://img.shields.io/badge/Status-Active%20Learning-green)
![Hardware Verified](https://img.shields.io/badge/Hardware-Verified-brightgreen)
![Projects](https://img.shields.io/badge/Projects-5%2F10-orange)

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
- Data processing pipelines
- Hardware timestamping
- Clock domain crossing (CDC)
- FIFO buffers and flow control

## Projects

Each project includes:

- Complete VHDL/Verilog source code
- Comprehensive testbenches
- Simulation waveforms
- Constraint files (XDC)
- Hardware verification videos/photos
- Documentation of concepts learned

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

- Clock management - Clock division from 100MHz to 1Hz, baud rate generation (115200 bps), clock domain understanding
- Metastability protection - Three-stage synchronizer chains for asynchronous inputs
- Debouncing implementation - 20ms stable period filtering for mechanical switches
- Edge detection - Rising/falling edge detection with proper sequential logic ordering
- FIFO buffer architecture - 16-depth x 8-bit circular buffer with full/empty flags
- UART communication - 8N1 format, mid-bit sampling, busy/started handshake flags
- Protocol parsing - Binary message framing (START_BYTE, LENGTH, DATA, CHECKSUM)
- Pulse stretching - 100ms counters to make brief signals human-visible on LEDs

### Verification & Testing

- Testbench development - Self-checking testbenches with assert statements
- Procedure-based testing - Reusable test procedures for encoder rotation, button presses
- Waveform analysis - Signal debugging in Vivado simulator
- Hardware verification - All designs validated on Xilinx Arty A7-100T (XC7A100T)
- Coverage scenarios - Normal operation, boundary conditions, error states
- Python test scripts - Automated UART protocol testing with PySerial
- Protocol validation - Checksum verification, message framing, error detection

### Hardware Integration

- Peripheral interfaces - Rotary encoder (quadrature decoding), piezo buzzer (frequency generation), USB-UART bridge
- Serial communication - UART RX/TX at 115200 baud, PC-FPGA communication, echo/command processing
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
- Synchronization - CDC techniques critical for asynchronous market data
- Latency awareness - Understanding of clock cycles and timing paths
- Reliability patterns - Metastability protection mandatory for production systems
- Binary protocols - START_BYTE framing, length-prefixed messages, XOR checksums (mirrors FIX/ITCH/OUCH)
- Message parsing - State machine-based protocol decoder with checksum validation
- Error detection - Checksum mismatches, framing errors, graceful error recovery
- Multi-protocol support - Handling both binary (efficient) and ASCII (debug) interfaces

---

_Learning in public. All feedback welcome!_
