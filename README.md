![FPGA](https://img.shields.io/badge/FPGA-Xilinx%20Artix--7-red)
![Language](https://img.shields.io/badge/Language-VHDL-blue)
![Status](https://img.shields.io/badge/Status-Production%20Ready-green)
![Hardware Verified](https://img.shields.io/badge/Hardware-Verified-brightgreen)
![Projects](https://img.shields.io/badge/Projects-8%20Complete-brightgreen)

# FPGA Trading Systems

Hardware-accelerated market data processing and order book management for low-latency trading systems. Features NASDAQ ITCH 5.0 protocol parsing, hardware order book with sub-microsecond latency, and production-grade clock domain crossing architecture.

## Profile

**Technical Background:**
- 20+ years C++ systems engineering (distributed systems, real-time processing, network protocols)
- 5 years active futures trading (S&P 500, Nasdaq 100)
- FPGA hardware acceleration specialist focusing on trading infrastructure

**Domain Expertise:** Combining software engineering experience with active trading knowledge to build FPGA-based market data systems and order management infrastructure.

## Hardware

- Xilinx Arty A7-100T Development Board
- Artix-7 FPGA (XC7A100T-1CSG324C)
- AMD Vivado Design Suite

## Technical Focus

Progressive architecture development from digital design fundamentals to production trading systems:

- **Low-latency network processing:** MII Ethernet, UDP/IP stack, NASDAQ ITCH 5.0 protocol
- **Memory architecture:** BRAM-based order storage, price level tables, FIFO buffering
- **Clock domain crossing:** Production-grade CDC with gray code synchronization
- **State machine design:** Multi-stage FSM pipelines for deterministic latency
- **Real-time processing:** Sub-microsecond order book updates, hardware BBO tracking
- **Timing analysis:** XDC constraints, setup/hold violations, critical path optimization

## Project Portfolio

### Core Trading Infrastructure (Projects 6-8)

**Project 06: UDP/IP Network Stack**
- **Achievement:** Production-ready Ethernet packet processing with 100% reliability under stress testing
- **Architecture:** MII physical layer, MAC frame parser, IP/UDP protocol stack
- **Key Innovation:** Real-time byte-by-byte parsing eliminates CDC race conditions (1% → 100% success rate)
- **Validation:** 1000+ packet stress test, comprehensive XDC timing constraints
- **Latency:** Wire-to-parsed < 2 μs @ 100 MHz processing clock

**Project 07: NASDAQ ITCH 5.0 Protocol Parser**
- **Achievement:** Full ITCH 5.0 market data decoder with 9 message types
- **Architecture:** Async FIFO with gray code CDC, configurable symbol filtering
- **Message Types:** S (System), R (Directory), A (Add), E (Execute), X (Cancel), D (Delete), U (Replace), P (Trade), Q (Cross)
- **Performance:** Deterministic message parsing, symbol filtering reduces downstream load
- **Integration:** Feeds parsed ITCH messages to Project 8 order book

**Project 08: Multi-Symbol Hardware Order Book** ✅
- **Achievement:** Sub-microsecond order book tracking 8 symbols simultaneously
- **Architecture:** 8 parallel BRAM-based order books with round-robin BBO arbiter
- **Symbols:** AAPL, TSLA, SPY, QQQ, GOOGL, MSFT, AMZN, NVDA
- **Capacity:** 1,024 orders × 256 price levels per symbol
- **Latency:** Order processing 120-170 ns, BBO update 2.6 μs per symbol
- **Resources:** 32 RAMB36 tiles (24% utilization), excellent scalability headroom
- **Spread Calculation:** Real-time ask - bid calculation for risk management
- **BRAM Implementation:** Production-grade Block RAM inference using Xilinx templates
- **Debug Methodology:** Comprehensive instrumentation for systematic troubleshooting
- **Trading Relevance:** Multi-symbol tracking essential for real-world exchange systems
- **BBO Output:** UART interface with symbol name, bid/ask prices/shares, spread, change detection

### Application Layer (Projects 9-10)

**Project 09: C++ Order Gateway** (In Development)
- **Purpose:** Bridge FPGA BBO output to Java application layer
- **Architecture:** UART reader, BBO parser (hex→decimal), TCP server, CSV logger
- **Interface:** Receives ASCII BBO from FPGA UART, serves JSON via TCP (localhost:9999)
- **Scope:** Minimal middleware gateway (~500-800 LOC) demonstrating C++ systems programming
- **Technologies:** C++17, Boost.Asio (or POSIX sockets), nlohmann/json

**Project 10: Java Market Data Platform** (Planned)
- **Purpose:** Real-time market data visualization and analytics
- **Architecture:** TCP client, in-memory order book, market analytics, JavaFX dashboard
- **Features:** BBO visualization, spread analysis, depth tracking, Chronicle Queue persistence
- **Technologies:** Java 17+, JavaFX, Chronicle Queue, JUnit 5
- **Testing:** ITCH packet generator (replaces Python scripts)

### Foundation Projects (Projects 1-5)

**Digital Design Fundamentals:**
1. Rotary Encoder Counter - Quadrature decoding, debouncing, edge detection
2. Button Debouncer - Metastability protection, synchronizer chains
3. FIFO Buffer - Circular buffer, flow control, full/empty flags
4. Frequency Generator - Audio feedback, precise timing control
5. UART Transceiver - Binary protocol framing, checksum validation, 115200 baud

**Skills Demonstrated:** Clock management, state machine design, serial protocols, timing constraints, hardware verification

Each project includes:
- Complete VHDL source with production-grade coding practices
- Testbenches with self-checking assertions
- XDC constraints with timing analysis
- Hardware validation on Xilinx Arty A7-100T
- Design rationale and architectural decisions documented

## Architecture Highlights

**End-to-End Trading System Pipeline:**
```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              FPGA Layer (VHDL)                                           │
│  Ethernet PHY → UDP/IP Parser → ITCH Decoder → Order Book → BBO Tracker → UART Output  │
│     25 MHz         100 MHz        100 MHz        100 MHz       100 MHz      115200 baud │
│                └── Gray Code CDC ──┘                                                     │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            │ UART (ASCII BBO)
                                            ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                          C++ Gateway Layer (Project 9)                                   │
│  UART Reader → BBO Parser (hex→decimal) → TCP Server (JSON) → CSV Logger                │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                            │
                                            │ TCP localhost:9999 (JSON)
                                            ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                       Java Application Layer (Project 10)                                │
│  TCP Client → Order Book → Market Analytics → JavaFX Dashboard → Chronicle Queue        │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

**Performance Characteristics:**
- **Wire-to-BBO latency:** < 5 μs (Ethernet → Best Bid/Offer output)
- **Order processing:** 120-170 ns per ITCH message
- **BBO update:** 2.6 μs (full price level scan)
- **Deterministic:** Fixed-latency processing, no OS overhead
- **Capacity:** 1024 concurrent orders, 256 price levels per symbol

**Production Patterns:**
- Clock domain crossing with gray code FIFO synchronization
- BRAM inference using Xilinx coding templates
- Multi-stage FSM pipelines for deterministic latency
- Comprehensive debug instrumentation for systematic troubleshooting

## Technical Skills
### HDL Design & Architecture

- **VHDL Implementation:** Complex state machines, BRAM-based memory systems, protocol parsers, hierarchical component design
- **Memory Architecture:** Block RAM inference using Xilinx templates, dual-port RAM, read-modify-write pipelines
- **State Machine Design:** Multi-stage FSMs with deterministic latency, pipelined data paths, error recovery logic
- **Parameterization:** Generic-based configurability for FIFO depth, clock ratios, protocol parameters, symbol filtering

### Clock Domain Crossing & Timing

- **Production CDC Techniques:** Gray code FIFO synchronizers, 2-FF chains for single-bit signals, valid-gated multi-bit bus capture
- **XDC Constraints:** ASYNC_REG attributes, set_false_path declarations, timing exception management
- **Metastability Protection:** Synchronizer chains for asynchronous inputs, reset domain crossing
- **Clock Management:** PLL/MMCM configuration (25 MHz Ethernet PHY reference), multi-clock domain systems
- **Timing Closure:** Critical path analysis, setup/hold violation resolution, pipeline balancing

### Network Protocol Implementation

- **Ethernet/MII:** Physical layer reception (4-bit nibbles), preamble/SFD detection, MAC frame parsing with address filtering
- **UDP/IP Stack:** IP header validation, UDP datagram extraction, checksum verification
- **ITCH 5.0 Protocol:** Big-endian field extraction, 9 message types, order lifecycle tracking
- **Real-time Parsing:** Position-based state machine triggering for deterministic latency (vs event-driven approaches)
- **Binary Protocols:** Frame synchronization, length-prefixed messages, checksum validation

### Verification & Debug Methodology

- **Self-Checking Testbenches:** VHDL assertions, procedure-based test scenarios, waveform analysis
- **Hardware Validation:** All designs verified on Xilinx Arty A7-100T with real-world traffic
- **Automated Testing:** Python/Scapy scripts for Ethernet packet injection, 1000+ packet stress tests
- **Debug Infrastructure:** Strategic UART instrumentation, state machine visibility, performance counters
- **Systematic Troubleshooting:** Root cause analysis, architectural refactoring when needed (event-driven → real-time rewrite resolved 99% failure rate)

### Development Workflow & Toolchain

- **Vivado Flow:** Synthesis, implementation, bitstream generation, timing analysis
- **Constraint Management:** XDC pin assignments, timing constraints, false path declarations
- **Hardware Integration:** TI DP83848J Ethernet PHY (MII), USB-UART bridge, quadrature encoders, GPIO
- **Version Control:** Structured Git workflow with build versioning
- **Automated Build System:** TCL-based universal build scripts with version tracking

### Trading Systems Expertise

- **Market Data Processing:** NASDAQ ITCH 5.0 decoder, order lifecycle tracking, symbol filtering
- **Order Book Implementation:** BRAM-based architecture, price level aggregation, BBO tracking
- **Low-Latency Design:** Sub-microsecond order processing, deterministic FSM pipelines, direct PHY interfacing
- **Protocol Knowledge:** Binary message framing, big-endian field extraction, checksum validation
- **Performance Optimization:** BRAM vs LUTRAM trade-offs, pipeline balancing, critical path reduction
- **Production Patterns:** Gray code CDC, systematic debug instrumentation, architectural refactoring based on performance data

## Why FPGA for Trading?

**Latency Advantage:**
- **Software (OS network stack):** 10-100+ μs latency, non-deterministic
- **FPGA (direct PHY):** < 5 μs wire-to-BBO, deterministic processing
- **Critical for HFT:** Microseconds determine profitability in high-frequency strategies

**Determinism:**
- Hardware FSMs provide fixed-cycle processing (no context switches, no GC pauses)
- Predictable performance under load (no cache misses, no OS scheduling)
- Essential for algorithmic trading where timing consistency matters

**This Portfolio Demonstrates:**
- Full stack: PHY → Protocol → Application (Order Book)
- Production techniques: CDC, BRAM inference, timing closure
- Debug methodology: Systematic troubleshooting, performance analysis
- Real-world validation: Hardware-verified with stress testing

---

**Contact:** [GitHub Profile](https://github.com/adilsondias-engineer)
