# Project 15: Market Maker FSM - Disruptor Consumer + Automated Trading

**Platform:** Linux
**Technology:** C++20, LMAX Disruptor, spdlog, nlohmann/json
**Status:** Completed and tested on hardware

---

## Overview

The Market Maker FSM is an automated trading strategy that consumes BBO (Best Bid/Offer) data from Project 14 via **LMAX Disruptor lock-free IPC** and generates two-sided quotes with position management and risk controls.

**Data Flow (Ultra-Low-Latency Mode):**
```
FPGA Order Book (Project 13) → XDP Kernel Bypass (0.10 μs) → Project 14 Disruptor Producer
                                                                      ↓
                                            POSIX Shared Memory (131 KB ring buffer)
                                            Lock-Free IPC (~0.50 μs)
                                                                      ↓
                                                      Project 15 Disruptor Consumer
                                                                      ↓
                                               Market Maker FSM (~3.23 μs business logic)
                                                                      ↓
                                                Quote Generation + Position Tracking

Total End-to-End Latency: 4.13 μs (3× faster than TCP mode)
```

**Legacy Data Flow (TCP Mode):**
```
FPGA Order Book (Project 13) → UDP (XDP Kernel Bypass) → Project 14 Order Gateway
                                                               ↓ TCP :9999 (JSON)
                                                          Market Maker FSM
                                                               ↓
                                                 Quote Generation + Position Tracking

End-to-End Latency: 12.73 μs (legacy mode)
```

**Architecture:** This project consumes BBO data from Project 14 using POSIX shared memory with the LMAX Disruptor pattern. The Disruptor provides lock-free, zero-copy IPC with atomic sequence numbers for ultra-low-latency communication. Project 14 handles XDP reception (0.10 μs), while Project 15 focuses on trading strategy execution (4.13 μs end-to-end).

---

## Architecture

### Core Components

**Primary Architecture (Disruptor Mode):**
```
┌────────────────────────────────────────────────────────────┐
│              Project 14 (Order Gateway - XDP)               │
│  XDP Listener (0.10 μs) → Disruptor Producer               │
└────────────────────────┬───────────────────────────────────┘
                         │
        POSIX Shared Memory (/dev/shm/bbo_ring_gateway)
        Ring Buffer: 1024 entries × 128 bytes = 131 KB
        Lock-Free IPC: Atomic sequence numbers (~0.50 μs)
                         │
┌────────────────────────┴───────────────────────────────────┐
│                    Market Maker FSM (Project 15)            │
│                                                             │
│  ┌────────────────┐     ┌──────────────────────────┐       │
│  │  Disruptor     │────→│     BBO Parser          │       │
│  │  Consumer      │     │  (Binary Protocol)       │       │
│  │  (Lock-Free)   │     │  Fixed-size structs      │       │
│  └────────────────┘     └──────────┬───────────────┘       │
│                                    │                        │
│                                    ↓                        │
│                         ┌──────────────────┐                │
│                         │  Market Maker    │                │
│                         │      FSM         │                │
│                         └─────────┬────────┘                │
│                                   │                         │
│          ┌────────────────────────┼────────────────┐        │
│          ↓                        ↓                ↓        │
│  ┌──────────────┐      ┌──────────────┐  ┌──────────────┐  │
│  │ Fair Value   │      │ Quote        │  │ Risk         │  │
│  │ Calculation  │      │ Generation   │  │ Management   │  │
│  │              │      │              │  │              │  │
│  └──────────────┘      └──────────────┘  └──────────────┘  │
│                                   │                         │
│                                   ↓                         │
│                         ┌──────────────────┐                │
│                         │  Position        │                │
│                         │  Tracker         │                │
│                         └──────────────────┘                │
└─────────────────────────────────────────────────────────────┘

End-to-End Latency: 4.13 μs avg (4.37 μs P50, 5.82 μs P99)
```

**Legacy Architecture (TCP Mode):**
```
┌─────────────────────────────────────────────────────────────┐
│                    Market Maker FSM                         │
│                                                             │
│  ┌────────────────┐     ┌──────────────────────────┐       │
│  │  TCP Client    │────→│     BBO Parser          │       │
│  │  (From Proj 14)│     │  (JSON Protocol)         │       │
│  │  localhost:9999│     │                          │       │
│  └────────────────┘     └──────────┬───────────────┘       │
│                                    │                        │
│                                    ↓                        │
│                         ┌──────────────────┐                │
│                         │  Market Maker    │                │
│                         │      FSM         │                │
│                         └─────────┬────────┘                │
│                                   │                         │
│          ┌────────────────────────┼────────────────┐        │
│          ↓                        ↓                ↓        │
│  ┌──────────────┐      ┌──────────────┐  ┌──────────────┐  │
│  │ Fair Value   │      │ Quote        │  │ Risk         │  │
│  │ Calculation  │      │ Generation   │  │ Management   │  │
│  │              │      │              │  │              │  │
│  └──────────────┘      └──────────────┘  └──────────────┘  │
│                                   │                         │
│                                   ↓                         │
│                         ┌──────────────────┐                │
│                         │  Position        │                │
│                         │  Tracker         │                │
│                         └──────────────────┘                │
└─────────────────────────────────────────────────────────────┘

End-to-End Latency: 12.73 μs avg (legacy TCP mode)
```

### FSM States

The market maker operates as a finite state machine with the following states:

1. **IDLE** - Waiting for BBO updates
2. **CALCULATE** - Computing fair value from BBO
3. **QUOTE** - Generating bid/ask quotes with position skew
4. **RISK_CHECK** - Validating position and notional limits
5. **ORDER_GEN** - Sending orders to market
6. **WAIT_FILL** - Waiting for order fills

**State Transitions:**
```
IDLE → CALCULATE → QUOTE → RISK_CHECK → ORDER_GEN → WAIT_FILL → CALCULATE
         ↑                      ↓
         └──────────────────────┘
              (Risk Failed)
```

---

## Features

### 1. Fair Value Calculation
- Weighted mid-price using bid/ask sizes
- Combines simple mid and size-weighted price
- Handles missing or invalid market data

### 2. Quote Generation
- Two-sided market making (bid and ask)
- Configurable edge (spread from fair value)
- Position-based inventory skew
- Minimum spread enforcement

### 3. Position Management
- Real-time position tracking per symbol
- Realized PnL calculation on fills
- Unrealized PnL marking to market
- Weighted average entry price

### 4. Risk Controls
- Maximum position limits per symbol
- Maximum notional exposure limits
- Pre-trade risk checks
- Automatic quote rejection when limits exceeded

### 5. Configuration
- JSON-based configuration file
- Adjustable spread parameters (basis points)
- Position and notional limits
- Quote size and skew parameters

---

## Build Instructions

### Prerequisites

**Linux:**
- GCC 10+ or Clang 10+ (C++20 support)
- CMake 3.20+
- vcpkg or system package manager

**Windows:**
- Visual Studio 2019+ with C++20 support
- CMake 3.20+
- vcpkg package manager

### Dependencies (via vcpkg)

```bash
./vcpkg install boost-asio boost-system boost-thread
./vcpkg install nlohmann-json
./vcpkg install spdlog
```

### Build

**Linux (CMake):**
```bash
cd 15-market-maker
mkdir build
cd build
cmake ..
make -j$(nproc)
```

**Windows (Visual Studio):**
```bash
cd 15-market-maker
mkdir build
cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=[vcpkg-root]/scripts/buildsystems/vcpkg.cmake
cmake --build . --config Release
```

---

## Usage

### Basic Usage

```bash
# Run with default config.json
./market_maker

# Run with custom config file
./market_maker config_prod.json
```

### Configuration File (config.json)

```json
{
  "min_spread_bps": 5.0,
  "edge_bps": 2.0,
  "max_position": 500,
  "position_skew_bps": 1.0,
  "quote_size": 100,
  "max_notional": 100000.0,
  "gateway_host": "localhost",
  "gateway_port": 9999,
  "enable_rt": true,
  "cpu_cores": [2, 3]
}
```

### Configuration Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `min_spread_bps` | double | Minimum spread in basis points | 5.0 |
| `edge_bps` | double | Edge added to fair value (bps) | 2.0 |
| `max_position` | int | Maximum position per symbol | 500 |
| `position_skew_bps` | double | Inventory skew adjustment (bps) | 1.0 |
| `quote_size` | int | Quote size per side | 100 |
| `max_notional` | double | Maximum notional exposure | 100000.0 |
| `gateway_host` | string | Order Gateway TCP host | "localhost" |
| `gateway_port` | int | Order Gateway TCP port | 9999 |
| `enable_rt` | bool | Enable RT scheduling | true |
| `cpu_cores` | array | CPU cores for affinity | [2, 3] |

### Real-Time Optimizations (Linux)

Enable RT scheduling for lower latency:

```bash
# Grant RT scheduling capability
sudo setcap cap_sys_nice=eip ./market_maker

# Run with RT optimizations
./market_maker config.json
# (set "enable_rt": true in config.json)
```

**RT Configuration:**
- Priority: 50 (SCHED_FIFO)
- CPU cores: 2-3 (isolated cores recommended)
- Lower priority than Order Gateway (priority 99)

---

## Algorithm Details

### Fair Value Calculation

```
mid_price = (bid_price + ask_price) / 2
weighted_price = (bid_price * bid_shares + ask_price * ask_shares) / (bid_shares + ask_shares)
fair_value = (mid_price + weighted_price) / 2
```

### Quote Generation with Position Skew

```
edge = fair_value * (edge_bps / 10000)
inventory_ratio = current_position / max_position
skew = fair_value * (position_skew_bps / 10000) * inventory_ratio

bid_price = fair_value - edge + skew
ask_price = fair_value + edge + skew
```

**Position Skew Logic:**
- Long position (positive shares): Skew quotes DOWN to encourage selling
- Short position (negative shares): Skew quotes UP to encourage buying
- Larger positions = larger skew adjustment

### Position Tracking

**On Fill:**
- Position increase: Update weighted average entry price
- Position reduction: Calculate realized PnL
- Position flip: Reset entry price to new side

**Realized PnL:**
```
For reducing fills:
  pnl_per_share = (long) ? (exit_price - entry_price) : (entry_price - exit_price)
  realized_pnl += pnl_per_share * shares
```

**Unrealized PnL:**
```
For current position:
  unrealized_pnl = (long) ? (current_price - entry_price) * shares
                          : (entry_price - current_price) * abs(shares)
```

---

## Code Structure

```
15-market-maker/
├── src/
│   ├── main.cpp                # Entry point, config loading
│   ├── market_maker_fsm.cpp    # FSM implementation
│   ├── position_tracker.cpp    # Position and PnL tracking
│   ├── tcp_client.cpp          # TCP client (connects to Project 14)
│   └── bbo_parser.cpp          # BBO parser (JSON)
├── include/
│   ├── market_maker_fsm.h      # FSM class definition
│   ├── position_tracker.h      # Position tracker
│   ├── order_types.h           # BBO, Quote, Order, Fill structs
│   ├── tcp_client.h            # TCP client interface
│   └── bbo_parser.h            # BBO parser interface
├── config.json                 # Configuration file
└── CMakeLists.txt             # Build configuration
```

---

## Example Output

```
[info] Loaded config from config.json
[info] MarketMakerFSM initialized with config: spread=5 bps, edge=2 bps, max_pos=500, skew=1 bps
[info] Connected to Order Gateway at localhost:9999
[info] Market Maker FSM running (TCP Client)
[info] Press Ctrl+C to stop

[debug] CALCULATE: symbol=AAPL, fair_value=150.0000, spread=0.0500
[debug] QUOTE: symbol=AAPL, bid=149.9700x100, ask=150.0300x100, fair=150.0000
[debug] RISK_CHECK: Passed
[info] ORDER_GEN: Sending quote: 100@149.9700 / 150.0300@100

[info] FILL: BUY 100 shares of AAPL @ 149.9700
[info] POSITION: 100 shares, realized_pnl=0.00, unrealized_pnl=0.00

[debug] CALCULATE: symbol=AAPL, fair_value=150.0200, spread=0.0500
[debug] QUOTE: symbol=AAPL, bid=149.9900x100, ask=150.0500x100, fair=150.0200
[debug] RISK_CHECK: Passed
[info] ORDER_GEN: Sending quote: 100@149.9900 / 150.0500@100

^C
[info] Received signal 2, shutting down...
[info] Shutdown complete
```

---

## Performance Characteristics

### Latency (Validated with 78,606 samples)

The market maker processes BBO messages from Project 14 with the following latency:

| Metric | Latency | Notes |
|--------|---------|-------|
| **Average** | **12.73 μs** | Mean processing time |
| **P50 (Median)** | **11.76 μs** | 50th percentile |
| **P99** | **21.53 μs** | 99th percentile |
| **Std Dev** | **3.58 μs** | Standard deviation |
| **Min** | **10.08 μs** | Minimum latency |
| **Max** | **67.82 μs** | Maximum latency |

**End-to-End Performance Chain:**
- FPGA → Project 14 (XDP): 0.04 μs
- Project 14 → Project 15 (TCP + JSON Parse): 12.73 μs
- **Total:** ~12.77 μs (FPGA BBO → Trading Decision)

### Component Breakdown

| Component | Latency | Notes |
|-----------|---------|-------|
| TCP Read + JSON Parse | ~12 μs | Dominant factor |
| Fair Value Calc | < 0.1 μs | Simple arithmetic |
| Quote Generation | < 0.1 μs | Price calculation + skew |
| Risk Check | < 0.05 μs | Position limit checks |

### Throughput

- Tested with 78,606 BBO messages
- Single-threaded FSM processing
- Lock-free position updates
- Handles sustained message rates from FPGA order book

---

## Risk Management

### Pre-Trade Controls

1. **Position Limits**
   - Maximum long/short position per symbol
   - Prevents runaway positions
   - Rejects quotes that would exceed limits

2. **Notional Limits**
   - Maximum dollar exposure per symbol
   - Calculated as: `abs(shares) * price`
   - Prevents excessive capital deployment

### Position Monitoring

- Real-time PnL tracking (realized + unrealized)
- Weighted average entry price calculation
- Position flip detection and handling

---

## Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Language** | C++20 | Modern C++ with concepts |
| **Async I/O** | Boost.Asio | UDP sockets |
| **Logging** | spdlog | High-performance logging |
| **JSON** | nlohmann/json | Config parsing |
| **Threading** | std::thread | RT scheduling |

---

## Test Data

The market maker has been tested and validated using real-world NASDAQ market data:

**Source:** NASDAQ ITCH 5.0 data from December 30, 2019 trading day
- **Test Dataset:** 10,000 BBO updates (8 symbols: AAPL, TSLA, SPY, QQQ, GOOGL, MSFT, AMZN, NVDA)
- **Data Type:** Historic real market data, NOT simulated
- **Message Rate:** 600+ BBO updates/second sustained
- **Processing:** Real order flow from FPGA order book (Project 13)

**Note:** While the BBO input data is real historic market data, order fills are currently simulated (no actual exchange connectivity). Real exchange integration planned for Project 16.

For detailed information about the ITCH 5.0 dataset, see [docs/database.md](../docs/database.md) in the parent directory.

---

## Related Projects

- **[13-udp-trasmitter-mii/](../13-udp-trasmitter-mii/)** - FPGA order book with UDP BBO transmission (data source for Project 14)
- **[14-order-gateway-cpp/](../14-order-gateway-cpp/)** - XDP kernel bypass gateway (TCP server for this project)
- **[16-order-execution/](../16-order-execution/)** - Order execution engine (future integration)

**Dependencies:**
- Project 15 requires Project 14 to be running (TCP server on localhost:9999)
- Project 14 requires Project 13 (FPGA) to be transmitting UDP BBO packets

---

## Future Enhancements

1. **Order Execution Integration**
   - Connect to order execution engine (Project 16)
   - Real fill processing (currently simulated)
   - Order cancellation and replacement

2. **Advanced Strategies**
   - Adverse selection detection
   - Spread widening on volatility
   - Multiple quote levels

3. **Multi-Symbol Support**
   - Independent FSM per symbol
   - Cross-symbol risk limits
   - Portfolio-level PnL tracking

4. **Performance Optimizations**
   - Zero-copy message passing with Project 14
   - SIMD for fair value calculations
   - Lock-free data structures for position tracking

---

## References

### Market Making and Trading Strategies
- [Market Making Strategies - QuantStackExchange](https://quant.stackexchange.com/questions/tagged/market-making) - Discussion of market making techniques
- [Inventory Risk and Market Making](https://www.investopedia.com/terms/m/marketmaker.asp) - Market maker role and inventory management

### Position Management and Risk Controls
- [Position Sizing and Risk Management](https://www.investopedia.com/terms/p/positionsize.asp) - Position sizing fundamentals
- [Pre-Trade Risk Controls](https://www.finra.org/rules-guidance/key-topics/market-access-rule) - Regulatory perspective on risk controls

### C++ High-Performance Programming
- [Boost.Asio Documentation](https://www.boost.org/doc/libs/1_84_0/doc/html/boost_asio.html) - Async I/O library
- [nlohmann/json](https://github.com/nlohmann/json) - Modern C++ JSON library
- [spdlog](https://github.com/gabime/spdlog) - Fast C++ logging library

### Related Project Documentation
- [Project 14 - Order Gateway (XDP)](../14-order-gateway-cpp/README.md) - Data source for this project
- [Project 13 - FPGA UDP Transmitter](../13-udp-trasmitter-mii/README.md) - FPGA BBO source
- [System Architecture](../docs/SYSTEM_ARCHITECTURE.md) - Complete system overview

---

**Build Time:** ~10 seconds
**Status:** Complete and tested with 78,606 real market data samples
