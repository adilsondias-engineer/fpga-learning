# FPGA Trading Systems Portfolio - Technical Summary

**Engineer:**  Adilson Dias
**Repository:** [fpga-trading-systems](https://github.com/adilsondias-engineer/fpga-trading-systems)
**Hardware:** Xilinx Arty A7-100T (Artix-7 FPGA)

---

## Executive Summary

**Complete full-stack FPGA trading system** from hardware acceleration to multi-platform applications. Implements wire-to-application processing with sub-5μs FPGA latency + multi-protocol distribution (TCP/MQTT/Kafka) to desktop, mobile, and IoT clients.

**Unique Value Proposition:** 20+ years C++ systems engineering + 5 years active futures trading (S&P 500, Nasdaq) + FPGA hardware acceleration + full-stack application development (C++, Java, .NET, IoT).

**Development Achievement:** 12 complete projects, 300+ hours over 21 days, production-ready system demonstrating end-to-end trading infrastructure.

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

### Systems & Application Development
- ✅ C++ multi-threaded architecture (Boost.Asio async I/O)
- ✅ Protocol integration (TCP, MQTT, Kafka)
- ✅ Mobile development (.NET MAUI, MVVM pattern)
- ✅ Desktop applications (Java, JavaFX)
- ✅ IoT/Embedded (ESP32, Arduino)
- ✅ Cross-platform development challenges

### Protocol Expertise
- ✅ TCP socket programming (JSON streaming, newline delimiters)
- ✅ MQTT (QoS levels, v3.1.1 vs v5.0, broker architecture)
- ✅ Kafka (producers, topics, partitions - reserved for analytics)
- ✅ Protocol selection trade-offs (latency, reliability, power consumption)

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

### Project 09: C++ Order Gateway (Multi-Protocol Distribution)
**Problem Solved:** Bridge FPGA to diverse application types (desktop, mobile, IoT, analytics)
**Architecture:** Multi-threaded gateway with UART reader, BBO parser, three protocol publishers
**Key Innovation:** Single gateway publishes simultaneously to TCP, MQTT, and Kafka—matching protocol to client requirements
**Technologies:** C++17, Boost.Asio, libmosquitto (MQTT), librdkafka, nlohmann/json
**Performance:** < 100 μs UART → protocol latency, handles > 10,000 BBO updates/sec

### Project 10: ESP32 IoT Live Ticker (Physical Display)
**Problem Solved:** Trading floor ticker display with real-time BBO updates
**Hardware:** ESP32-WROOM + 1.8" TFT LCD (ST7735), WiFi-enabled
**Protocol:** MQTT v3.1.1 (lightweight, low power, handles unreliable WiFi)
**Design Decision:** Arduino IDE chosen over ESP-IDF (simpler for demonstration, focuses on MQTT protocol usage)
**Achievement:** Real-time 8-symbol ticker with color-coded bid/ask/spread display

### Project 11: .NET MAUI Mobile App (Cross-Platform)
**Problem Solved:** Mobile BBO terminal for Android/iOS/Windows
**Architecture:** MVVM pattern with CommunityToolkit.Mvvm, MQTT client
**Protocol Choice:** MQTT (not Kafka) due to Android compatibility, network resilience, battery efficiency
**Key Challenge:** MQTTnet 5.x breaking changes (.NET 8 → .NET 10 upgrade), MQTT v3.1.1 compatibility with ESP32
**Technologies:** .NET 10 MAUI, MQTTnet 5.x, System.Text.Json

### Project 12: Java Desktop Trading Terminal
**Problem Solved:** High-performance desktop application for live BBO monitoring with charts
**Architecture:** JavaFX GUI, TCP client (localhost), real-time charting
**Protocol Choice:** TCP (not MQTT/Kafka) for lowest latency on localhost (< 10ms)
**Technologies:** Java 21, JavaFX, Gson, Maven
**Features:** Live BBO table, spread charts, multi-symbol tracking

---

## Complete System Architecture

![System Architecture](docs/system_architecture.png)

**Protocol Selection Strategy:**

| Use Case | Protocol | Why |
|----------|----------|-----|
| Java Desktop | TCP | Lowest latency (< 10ms localhost), simple, no broker overhead |
| ESP32 IoT | MQTT | Lightweight, low power, WiFi resilience, native ESP32 support |
| Mobile App | MQTT | Cross-platform, handles network switching, no native dependencies |
| Future Analytics | Kafka | Data persistence, historical replay, analytics pipelines |

**Key Architectural Lesson:** Match protocol to client requirements—don't force one protocol for everything. Gateway pattern enables protocol diversity without coupling FPGA to applications.

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

**Complete Trading System (Not Just FPGA):**
- End-to-end pipeline: FPGA hardware → C++ gateway → Multi-platform applications
- Production-ready: All 12 projects complete, documented, tested, and integrated
- Real-world architecture: Multi-protocol distribution (TCP/MQTT/Kafka) matching protocol to use case

**Technical Depth:**
- **FPGA:** Production patterns (CDC, BRAM inference, timing closure), systematic debug methodology
- **Systems Programming:** C++ multi-threaded gateway (Boost.Asio, async I/O)
- **Mobile Development:** Cross-platform .NET MAUI with MQTT
- **Desktop Applications:** JavaFX real-time terminal
- **IoT/Embedded:** ESP32 physical ticker display
- Performance metrics: actual latency numbers, stress test validation

**Domain Expertise:**
- Active trader background (5 years S&P 500, Nasdaq futures)
- Understands order books, market data, latency requirements, protocol selection trade-offs
- Speaks hardware, software, trading, and infrastructure languages

**Problem-Solving Demonstrated:**
- **FPGA:** CDC races (99% failure → 100% success), BRAM inference, timing violations
- **Application:** MQTT v3.1.1 vs v5.0 compatibility, MQTTnet 5.x breaking changes, thread confinement
- **Architecture:** Gateway pattern for protocol diversity, documented trade-offs
- Systematic debugging methodology applied across all layers

**Full-Stack Capability:**
- Complete vertical integration: Ethernet PHY → FPGA → Gateway → Desktop/Mobile/IoT
- Multiple languages: VHDL, C++17, Java 21, C# (.NET 10), Arduino (C++)
- Multiple platforms: FPGA, Windows, Linux, Android, iOS, ESP32
- Ready for any trading technology role (FPGA, systems, infrastructure, application)

---

## Repository Structure

```
fpga-trading-systems/
├── README.md                          # Portfolio overview
├── PORTFOLIO_SUMMARY.md               # This document
├── SYSTEM_ARCHITECTURE.md             # Complete system architecture documentation
├── docs/
│   ├── system_architecture.png        # Visual architecture diagram
│   ├── lessons-learned.md             # Technical lessons from all 12 projects
│   └── *.png                          # Screenshots (ESP32, mobile, desktop apps)
├── 01-rotary-encoder/                 # Foundation: Quadrature decoding
├── 02-button-debouncer/               # Foundation: Metastability protection
├── 03-fifo/                           # Foundation: Flow control, buffering
├── 04-rotary-encoder-buzzer/          # Foundation: Timing control
├── 05-uart-transceiver/               # Foundation: Serial protocols
├── 06-mii-ethernet-udp/               # Core: Network stack (MII/MAC/IP/UDP)
├── 07-itch-parser/                    # Core: NASDAQ ITCH 5.0 decoder
├── 08-order-book/                     # Core: Hardware order book + BBO
├── 09-order-gateway-cpp/              # Application: C++ multi-protocol gateway
├── 10-esp32-ticker/                   # Application: ESP32 IoT display (Arduino)
├── 11-mobile-app/                     # Application: .NET MAUI (Android/iOS)
├── 12-java-desktop-trading-terminal/  # Application: Java desktop terminal
└── build.cmd                          # Universal build automation (Windows)
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

**FPGA Hardware Layer:**
1. UDP/IP Stack: [06-mii-ethernet-udp/README.md](06-mii-ethernet-udp/README.md) - Production CDC, 100% reliability
2. ITCH Parser: [07-itch-parser/README.md](07-itch-parser/README.md) - Async FIFO, gray code synchronization
3. Order Book: [08-order-book/README.md](08-order-book/README.md) - BRAM inference, sub-μs latency

**Application Layer:**
4. C++ Gateway: [09-order-gateway-cpp/README.md](09-order-gateway-cpp/README.md) - Multi-protocol distribution
5. ESP32 IoT: [10-esp32-ticker/README.md](10-esp32-ticker/README.md) - Arduino + MQTT physical display
6. Mobile App: [11-mobile-app/README.md](11-mobile-app/README.md) - .NET MAUI cross-platform
7. Java Desktop: [12-java-desktop-trading-terminal/README.md](12-java-desktop-trading-terminal/README.md) - JavaFX terminal

**Architecture & Lessons:**
8. System Architecture: [SYSTEM_ARCHITECTURE.md](SYSTEM_ARCHITECTURE.md) - Complete system design
9. Lessons Learned: [docs/lessons-learned.md](docs/lessons-learned.md) - Technical insights from all 12 projects
10. Visual Diagram: [docs/system_architecture.png](docs/system_architecture.png) - End-to-end architecture

---

**Project Status:** ✅ **COMPLETE** - All 12 projects production-ready (November 2025)
**Development Time:** 300+ hours over 21 days
**System Status:** Fully integrated and operational with "live" NASDAQ ITCH feed(Historic data file simulating live feed)

---

**Last Updated:** November 2025
**Status:** Production-ready, hardware-verified on Xilinx Arty A7-100T
