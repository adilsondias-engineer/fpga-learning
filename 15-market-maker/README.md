# Project 15: Market Maker FSM - Automated Quote Generation

**Platform:** Linux/Windows
**Technology:** C++20, Boost.Asio, spdlog, nlohmann/json
**Status:** Complete

---

## Overview

The Market Maker FSM is an automated trading strategy that consumes BBO (Best Bid/Offer) data directly from the FPGA via UDP and generates two-sided quotes with position management and risk controls.

**Data Flow:**
```
FPGA Order Book (Project 13) → UDP BBO Packets (Port 5000) → Market Maker FSM
                                                                     ↓
                                                       Quote Generation + Position Tracking
```

**Note:** This project receives UDP BBO data directly from the FPGA (Project 13), replacing the need for the Order Gateway (Project 14) in the data flow. Both projects listen on port 5000 for the same FPGA UDP stream, but serve different purposes - Project 14 for multi-protocol distribution, Project 15 for automated trading logic.

---

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                    Market Maker FSM                         │
│                                                             │
│  ┌────────────────┐     ┌──────────────────────────┐       │
│  │  UDP Listener  │────→│     BBO Parser          │       │
│  │  (From FPGA)   │     │  (Binary Protocol)       │       │
│  │  Port 5000     │     │                          │       │
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
  "udp_ip": "0.0.0.0",
  "udp_port": 5000,
  "enable_rt": false,
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
| `udp_ip` | string | UDP bind address | "0.0.0.0" |
| `udp_port` | int | UDP listen port | 5000 |
| `enable_rt` | bool | Enable RT scheduling | false |
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
│   ├── udp_listener.cpp        # UDP listener (from Project 14)
│   └── bbo_parser.cpp          # BBO parser (from Project 14)
├── include/
│   ├── market_maker_fsm.h      # FSM class definition
│   ├── position_tracker.h      # Position tracker
│   ├── order_types.h           # BBO, Quote, Order, Fill structs
│   ├── udp_listener.h          # UDP listener interface
│   └── bbo_parser.h            # BBO parser interface
├── config.json                 # Configuration file
└── CMakeLists.txt             # Build configuration
```

---

## Example Output

```
[info] Loaded config from config.json
[info] MarketMakerFSM initialized with config: spread=5 bps, edge=2 bps, max_pos=500, skew=1 bps
[info] Market Maker FSM running (UDP 0.0.0.0:5000)
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

### Latency

The market maker is designed for sub-microsecond decision-making:

| Component | Latency | Notes |
|-----------|---------|-------|
| BBO Parse | 0.20 μs | From Project 14 |
| Fair Value Calc | < 0.1 μs | Simple arithmetic |
| Quote Generation | < 0.1 μs | Price calculation + skew |
| Risk Check | < 0.05 μs | Position limit checks |
| **Total Decision** | **< 0.5 μs** | BBO → Quote ready |

### Throughput

- Handles 10,000+ BBO updates/second
- Single-threaded FSM processing
- Lock-free position updates

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

- **[13-udp-transmitter-mii/](../13-udp-transmitter-mii/)** - FPGA order book with UDP BBO transmission (data source)
- **[14-order-gateway-cpp/](../14-order-gateway-cpp/)** - Multi-protocol gateway (alternative consumer of FPGA UDP)
- **[16-order-execution/](../16-order-execution/)** - Order execution engine (future)

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
   - Lock-free data structures
   - SIMD for calculations
   - Zero-copy message passing

---

**Build Time:** ~10 seconds
**Status:** Complete implementation with simulated fills
