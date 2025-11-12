# FPGA Trading Systems Portfolio - Technical Summary

**Engineer:**  Adilson Dias
**Repository:** [fpga-trading-systems](https://github.com/adilsondias-engineer/fpga-trading-systems)
**Hardware:** Xilinx Arty A7-100T (Artix-7 FPGA)

---

## Executive Summary

Complete FPGA-based trading system implementing wire-to-order-book processing with sub-5μs latency. Demonstrates production-grade techniques: NASDAQ ITCH 5.0 protocol parsing, hardware order book management, clock domain crossing, BRAM architecture, and systematic debug methodology.

**Unique Value Proposition:** 20+ years C++ systems engineering + 5 years active futures trading (S&P 500, Nasdaq) + FPGA hardware acceleration expertise.

---

## Core Achievements

### 1. Complete Market Data Pipeline (Projects 6-8)

**End-to-End Latency:** < 5 μs (Ethernet PHY → Best Bid/Offer output)

```
Ethernet → UDP/IP Parser → ITCH 5.0 Decoder → Order Book → BBO Tracker → Output
 25 MHz      100 MHz          100 MHz          100 MHz       100 MHz     115200 baud
         └── Gray Code CDC ──┘
```

**Components:**
- **UDP/IP Network Stack:** MII physical layer, MAC/IP/UDP parsing, 100% reliability (1000+ packet stress test)
- **ITCH 5.0 Protocol Parser:** 9 message types, symbol filtering, big-endian field extraction
- **Hardware Order Book:** 1024 orders, 256 price levels, sub-microsecond BBO tracking

### 2. Performance Metrics

| Component | Latency | Validation |
|-----------|---------|------------|
| UDP/IP Parser | < 2 μs | 1000+ packet stress test |
| ITCH Decoder | < 1 μs | Multi-symbol filtering |
| Order Processing | 120-170 ns | Full lifecycle (A/E/X/D/U) |
| BBO Update | 2.6 μs | Real-time price level scan |
| **Total Pipeline** | **< 5 μs** | **Hardware-verified** |

**Comparison:**
- Software (OS network stack): 10-100+ μs, non-deterministic
- This FPGA implementation: < 5 μs, deterministic

### 3. Production Techniques Demonstrated

**Clock Domain Crossing:**
- Gray code FIFO synchronization (25 MHz → 100 MHz)
- 2-FF synchronizer chains for single-bit signals
- Valid-gated multi-bit bus capture
- XDC constraints (ASYNC_REG, set_false_path)

**Memory Architecture:**
- BRAM inference using Xilinx templates (Simple Dual-Port, Read-First Single-Port)
- 1024 × 130-bit order storage (4 BRAM36 blocks)
- 256 × 82-bit price level table (1 BRAM36 block)
- Read-modify-write pipeline handling (2-cycle latency)

**State Machine Design:**
- Multi-stage FSMs with deterministic latency
- Pipeline balancing for timing closure
- Error recovery and edge case handling

**Debug Methodology:**
- Strategic UART instrumentation (state visibility, performance counters)
- Systematic root cause analysis
- Architectural refactoring based on performance data (event-driven → real-time rewrite resolved 99% failure rate)

---

## Technical Skills Matrix

### HDL & FPGA Architecture
- ✅ VHDL design (complex state machines, memory systems, protocol parsers)
- ✅ BRAM inference and optimization
- ✅ Multi-stage FSM pipelines
- ✅ Timing closure and critical path optimization

### Network & Protocol Processing
- ✅ Ethernet/MII physical layer
- ✅ UDP/IP stack implementation
- ✅ NASDAQ ITCH 5.0 protocol (9 message types)
- ✅ Binary protocol parsing (big-endian, checksums)

### Clock Domain Crossing & Timing
- ✅ Gray code FIFO synchronizers
- ✅ Metastability protection
- ✅ XDC constraint management
- ✅ Multi-clock domain systems (25 MHz PHY, 100 MHz processing)

### Verification & Debug
- ✅ Self-checking VHDL testbenches
- ✅ Python/Scapy automated testing (1000+ packet stress tests)
- ✅ Hardware validation on real FPGA
- ✅ Systematic troubleshooting methodology

### Trading Domain Knowledge
- ✅ Order book mechanics (bid/ask levels, price-time priority)
- ✅ Market data formats (ITCH 5.0 order lifecycle)
- ✅ Latency requirements (HFT microsecond sensitivity)
- ✅ Symbol filtering and message routing

---

## Project Highlights

### Project 06: UDP/IP Network Stack
**Problem Solved:** Reliable Ethernet packet parsing at wire speed
**Key Innovation:** Real-time byte-by-byte architecture eliminated CDC race conditions (1% → 100% success rate)
**Validation:** 1000+ packet stress test, comprehensive timing constraints

### Project 07: NASDAQ ITCH 5.0 Parser
**Problem Solved:** Hardware market data decoder with symbol filtering
**Architecture:** Async FIFO with gray code CDC, 9 message types
**Performance:** Deterministic parsing, configurable symbol filtering (AAPL, TSLA, SPY, QQQ, etc.)

### Project 08: Hardware Order Book
**Problem Solved:** Sub-microsecond order book with real-time BBO tracking
**Architecture:** BRAM-based storage (1024 orders, 256 levels), FSM scanner
**Achievement:** 120-170 ns order processing, 2.6 μs BBO update, production-grade BRAM inference
**Debug Case Study:** Systematic BRAM inference troubleshooting (LUTRAM → BRAM template refactoring)

---

## Design Decisions & Trade-offs

### BRAM Template Compliance
**Challenge:** Initial design inferred LUTRAM (distributed RAM) instead of Block RAM
**Solution:** Refactored to exact Xilinx templates (Simple Dual-Port, Read-First Single-Port)
**Result:** Proper BRAM inference, resource savings, timing improvement
**Lesson:** Synthesis tools pattern-match; template compliance is mandatory

### Event-Driven vs Real-Time Architecture
**Challenge:** Event-driven UDP parser had 99% failure rate due to CDC races
**Decision:** Complete rewrite to position-based (byte_index) real-time architecture
**Result:** 1% → 100% success rate, deterministic latency
**Lesson:** Architectural decisions matter more than incremental fixes

### Debug Infrastructure Investment
**Trade-off:** ~500 LUTs for UART debug formatter
**Benefit:** 10x faster debug cycles, systematic root cause identification
**ROI:** BRAM issue diagnosed in 2 build cycles (vs 10+ without visibility)

---

## Resource Utilization (Artix-7 XC7A100T)

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| Slice LUTs | ~10,000 | 63,400 | ~16% |
| Slice Registers | ~8,000 | 126,800 | ~6% |
| BRAM Tiles | 6-8 | 135 | ~5% |
| DSP Slices | 0 | 240 | 0% |

**BRAM Breakdown:**
- Order storage: 4 BRAM36 blocks
- Price level table: 1 BRAM36 block
- Async FIFO (CDC): 1-2 BRAM36 blocks

**Timing:** All designs meet timing (WNS > 0 ns) at 100 MHz processing clock

---

## Development Process

**Workflow:**
- Vivado synthesis/implementation/bitstream generation
- XDC constraint management (timing, pin assignments)
- VHDL testbench simulation
- Hardware validation on Arty A7-100T
- Python/Scapy automated testing
- Git version control with build tracking

**Testing Methodology:**
- Self-checking testbenches with assertions
- 1000+ packet stress tests
- Real-world Ethernet traffic validation
- Performance characterization (latency, throughput)

**Debug Approach:**
- Strategic UART instrumentation
- Waveform analysis (Vivado simulator)
- Systematic root cause analysis
- Performance-driven architectural decisions

---

## Why This Portfolio for Trading Roles?

**Technical Depth:**
- Not just "hello world" FPGA projects—complete trading system pipeline
- Production patterns: CDC, BRAM inference, timing closure, systematic debug
- Performance metrics: actual latency numbers, stress test validation

**Domain Expertise:**
- Active trader background (5 years S&P 500, Nasdaq futures)
- Understands order books, market data, latency requirements
- Speaks both hardware and trading domain languages

**Problem-Solving Demonstrated:**
- Real bugs fixed (CDC races, BRAM inference, timing violations)
- Architectural decisions documented (event-driven → real-time rewrite)
- Trade-offs evaluated (debug instrumentation cost vs benefit)

**Full-Stack Capability:**
- PHY layer → Protocol → Application (complete vertical integration)
- Hardware design + Python testing + documentation
- Ready for production trading FPGA roles

---

## Repository Structure

```
fpga-trading-systems/
├── README.md                          # Portfolio overview
├── PORTFOLIO_SUMMARY.md               # This document
├── 01-rotary-encoder/                 # Foundation: Quadrature decoding
├── 02-button-debouncer/               # Foundation: Metastability protection
├── 03-fifo/                           # Foundation: Flow control, buffering
├── 04-rotary-encoder-buzzer/          # Foundation: Timing control
├── 05-uart-transceiver/               # Foundation: Serial protocols
├── 06-mii-ethernet-udp/               # Core: Network stack (MII/MAC/IP/UDP)
├── 07-itch-parser/                    # Core: NASDAQ ITCH 5.0 decoder
├── 08-order-book/                     # Core: Hardware order book + BBO
└── build.tcl                          # Universal build automation
```

**Key Documentation:**
- Each project: Complete README with architecture, performance, testing
- Main README: Portfolio overview, skills matrix, project summaries
- Source code: Production-style VHDL with comments explaining decisions

---

## Contact & Links

**GitHub:** [https://github.com/adilsondias-engineer/fpga-trading-systems](https://github.com/adilsondias-engineer/fpga-trading-systems)
**LinkedIn:** [https://www.linkedin.com/in/adilsondias](https://www.linkedin.com/in/adilsondias/)

**Portfolio Highlights to Review:**
1. Main README: [README.md](README.md) - Portfolio overview
2. UDP/IP Stack: [06-mii-ethernet-udp/README.md](06-mii-ethernet-udp/README.md)
3. ITCH Parser: [07-itch-parser/README.md](07-itch-parser/README.md)
4. Order Book: [08-order-book/README.md](08-order-book/README.md)

---

**Last Updated:** November 2025
**Status:** Production-ready, hardware-verified on Xilinx Arty A7-100T
