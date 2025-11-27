# Project 16: Order Execution Engine + Simulated Exchange

**Platform:** Linux
**Technology:** C++20, FIX Protocol 4.2, LMAX Disruptor, Boost.Asio
**Status:** Architecture complete, implementation in progress

---

## Overview

Project 16 implements an ultra-low-latency order execution engine that consumes trading decisions from Project 15 (Market Maker FSM) and executes orders via FIX protocol. Includes a simulated exchange for testing without live market connectivity.

**Data Flow:**
```
Project 15 (Market Maker)
    ↓ Disruptor IPC (/dev/shm/order_ring_mm)
Project 16 (Order Execution Engine)
    ↓ FIX Protocol (TCP)
Simulated Exchange
    ↓ Execution Reports (FIX)
Project 16 (Fill Handler)
    ↓ Disruptor IPC (/dev/shm/fill_ring_oe)
Project 15 (Position Tracker Update)
```

---

## Architecture

### Components

**1. Order Execution Engine (Main Process)**
- Consumes order requests from Project 15 via Disruptor
- Encodes orders as FIX NewOrderSingle messages
- Sends to exchange via TCP/FIX session
- Receives ExecutionReports from exchange
- Publishes fill notifications back to Project 15

**2. Simulated Exchange (Separate Process)**
- FIX acceptor (listens on port 5001)
- Accepts FIX Logon
- Receives NewOrderSingle messages
- Immediately generates fills
- Sends ExecutionReports back

**3. Shared Data Structures**
- `OrderRequest`: Fixed-size order data (Project 15 → Project 16)
- `FillNotification`: Fixed-size fill data (Project 16 → Project 15)
- `OrderRingBuffer`: Lock-free IPC for orders
- `FillRingBuffer`: Lock-free IPC for fills

---

## Features

### Order Execution Engine

**FIX Protocol Support:**
- FIX 4.2 protocol encoding/decoding
- NewOrderSingle (MsgType=D)
- ExecutionReport (MsgType=8)
- Logon/Logout (MsgType=A/5)
- Heartbeat (MsgType=0)

**Order Lifecycle:**
```
NEW → PENDING_NEW → ACTIVE → FILLED
                             ↓
                      (or REJECTED)
```

**Performance Targets:**
- Order entry: < 10 μs (Disruptor read → FIX send)
- Fill processing: < 5 μs (FIX receive → Disruptor publish)

### Simulated Exchange

**Features:**
- Immediate fill generation (configurable delay)
- FIX 4.2 acceptor
- Execution reports with realistic format
- Configurable fill ratio and reject rate

**Configuration:**
```json
{
  "simulated_latency_us": 50,
  "simulated_fill_ratio": 1.0,
  "simulated_reject_rate": 0.0
}
```

---

## Build Instructions

### Prerequisites

```bash
# Install dependencies
sudo apt-get install -y cmake g++ libboost-all-dev
```

### Build

```bash
cd 16-order-execution
mkdir build && cd build
cmake ..
make -j$(nproc)
```

### Executables

- `order_execution_engine`: Main execution engine
- `simulated_exchange`: Mock exchange

---

## Usage

### 1. Start Simulated Exchange

```bash
cd build
./simulated_exchange
```

Output:
```
[info] Starting Simulated Exchange...
[info] Simulated Exchange started on port 5001
```

### 2. Start Order Execution Engine

```bash
cd build
./order_execution_engine
```

Output:
```
[info] Starting Order Execution Engine...
[info] Order Execution Engine initialized
[info] Connected to exchange at localhost:5001
[info] Sent FIX Logon
[info] Order Execution Engine running...
```

### 3. Start Project 15 (Market Maker)

Project 15 sends orders to Project 16 via Disruptor.

---

## Configuration

**config.json:**
```json
{
  "fix": {
    "protocol_version": "FIX.4.2",
    "sender_comp_id": "MMFIRM",
    "target_comp_id": "SIMEXCH",
    "heartbeat_interval_sec": 30
  },
  "exchange": {
    "mode": "simulated",
    "host": "localhost",
    "port": 5001
  },
  "disruptor": {
    "order_queue_path": "/dev/shm/order_ring_mm",
    "fill_queue_path": "/dev/shm/fill_ring_oe"
  },
  "performance": {
    "enable_rt": true,
    "cpu_cores": [4, 5],
    "rt_priority": 60
  }
}
```

---

## FIX Protocol

### NewOrderSingle Example

```
8=FIX.4.2|9=176|35=D|49=MMFIRM|56=SIMEXCH|34=1|52=20251125-12:30:00|
11=MM0000000001|21=1|55=AAPL|54=1|60=20251125-12:30:00|38=100|40=2|44=150.50|
59=0|10=123|
```

**Key Fields:**
- Tag 11: ClOrdID (Order ID)
- Tag 55: Symbol
- Tag 54: Side (1=Buy, 2=Sell)
- Tag 38: OrderQty
- Tag 40: OrdType (1=Market, 2=Limit)
- Tag 44: Price (for limit orders)

### ExecutionReport Example

```
8=FIX.4.2|9=200|35=8|49=SIMEXCH|56=MMFIRM|34=2|52=20251125-12:30:00|
11=MM0000000001|17=EXEC001|150=2|39=2|55=AAPL|54=1|38=100|14=100|151=0|
6=150.50|31=150.50|32=100|10=145|
```

**Key Fields:**
- Tag 17: ExecID
- Tag 150: ExecType (2=Fill)
- Tag 39: OrdStatus (2=Filled)
- Tag 14: CumQty (cumulative quantity)
- Tag 6: AvgPx (average price)
- Tag 31: LastPx (fill price)
- Tag 32: LastQty (fill quantity)

---

## Data Structures

### OrderRequest (Project 15 → Project 16)

```cpp
struct OrderRequest {
    char order_id[32];      // Unique order ID
    char symbol[16];        // Symbol (e.g., "AAPL")
    char side;              // 'B' = Buy, 'S' = Sell
    char order_type;        // 'L' = Limit, 'M' = Market
    char time_in_force;     // 'D' = Day, 'I' = IOC
    double price;           // Limit price
    uint32_t quantity;      // Shares
    int64_t timestamp_ns;   // Creation timestamp
    bool valid;
};
```

### FillNotification (Project 16 → Project 15)

```cpp
struct FillNotification {
    char order_id[32];      // Original order ID
    char exec_id[32];       // Execution ID
    char symbol[16];        // Symbol
    char side;              // 'B' = Buy, 'S' = Sell
    uint32_t fill_qty;      // Shares filled
    uint32_t cum_qty;       // Total shares filled
    double avg_price;       // Average fill price
    int64_t transact_time;  // Exchange timestamp
    bool is_complete;       // Fully filled?
    bool valid;
};
```

---

## Performance Metrics

### Latency Targets

| Stage | Target | Notes |
|-------|--------|-------|
| Disruptor order poll | < 0.50 μs | Lock-free read |
| FIX encoding | < 1.00 μs | String formatting |
| TCP send | < 5.00 μs | Kernel stack |
| **Total: Order Entry** | **< 7.00 μs** | End-to-end |
| Exchange processing | 10-100 μs | Simulated |
| FIX decode | < 1.00 μs | String parsing |
| Fill processing | < 0.50 μs | Logic |
| Disruptor fill publish | < 0.50 μs | Lock-free write |
| **Total: Fill Processing** | **< 2.00 μs** | End-to-end |

### End-to-End Latency

```
Order Decision (Project 15) → Order Execution Engine → Exchange
    4.13 μs (current)             7.00 μs (target)      50 μs (simulated)
                                                            ↓
                                                    Fill Processing
                                                        2.00 μs
                                                            ↓
                                            Position Update (Project 15)

Total: ~65 μs (Order Decision → Position Update)
```

---

## Project Structure

```
16-order-execution/
├── src/
│   ├── fix_encoder.cpp              # FIX message encoding
│   ├── fix_decoder.cpp              # FIX message decoding
│   ├── order_execution_engine.cpp   # Main execution engine
│   └── simulated_exchange_main.cpp  # Simulated exchange
├── include/
│   ├── fix_encoder.h
│   ├── fix_decoder.h
│   └── simulated_exchange.h
├── CMakeLists.txt
├── config.json
└── README.md
```

**Common Files (Shared with Project 15):**
```
common/
├── order_data.h                 # OrderRequest, FillNotification
└── disruptor/
    ├── OrderRingBuffer.h        # Order IPC
    └── FillRingBuffer.h         # Fill IPC
```

---

## Integration with Project 15

Project 15 enhancements required:

### 1. Order Generation

**New Components:**
- `OrderProducer`: Sends orders to Project 16 via Disruptor
- Order ID generation (MM0000000001, MM0000000002, etc.)
- Order creation based on market maker quotes

### 2. Fill Handling

**New Components:**
- Fill notification consumer
- Position update on fills
- PnL calculation update

### 3. Configuration

**Updated config.json:**
```json
{
  "enable_order_execution": true,
  "order_ring_path": "/dev/shm/order_ring_mm",
  "fill_ring_path": "/dev/shm/fill_ring_oe"
}
```

---

## Testing

### Manual Testing

1. Start simulated exchange
2. Start order execution engine
3. Start Project 15 (market maker)
4. Observe logs for order flow:
   - Project 15: "Sent order: MM0000000001 AAPL 100 @150.50"
   - Project 16: "Processing order: MM0000000001..."
   - Exchange: "Received order: MM0000000001..."
   - Exchange: "Sent fill for order MM0000000001: 100 @ 150.50"
   - Project 16: "Received ExecutionReport: MM0000000001 ExecType=2 Status=2"
   - Project 15: "Received fill: MM0000000001 100 @ 150.50"

### Performance Testing

```bash
# Monitor latency metrics
grep "latency" order_execution_engine.log

# Check order throughput
grep "Processed" order_execution_engine.log | tail -1
```

---

## Troubleshooting

### "Failed to open order shared memory"

**Cause:** Shared memory not created by Project 15

**Solution:**
```bash
# Ensure Project 15 creates the order ring buffer
# Check if shared memory exists
ls -lh /dev/shm/order_ring_mm
```

### "Failed to connect to exchange"

**Cause:** Simulated exchange not running

**Solution:**
```bash
# Start simulated exchange first
./simulated_exchange &

# Then start order execution engine
./order_execution_engine
```

### "No fills received"

**Cause:** Fill ring buffer not mapped correctly

**Solution:**
```bash
# Check shared memory permissions
ls -lh /dev/shm/fill_ring_oe

# Ensure both processes have read/write access
chmod 666 /dev/shm/fill_ring_oe
```

---

## Future Enhancements

**Phase 1 (Current):**
- ✓ Basic FIX protocol (NewOrderSingle, ExecutionReport)
- ✓ Simulated exchange with immediate fills
- ✓ Disruptor IPC integration

**Phase 2 (Planned):**
- Cancel/Replace support (OrderCancelRequest, OrderCancelReplaceRequest)
- Pre-trade risk checks (duplicate, position limits, price collars)
- Drop copy logging for compliance
- Order state management (pending, active, filled)

**Phase 3 (Future):**
- Real exchange connectivity (replace simulated exchange)
- Multi-venue support
- Smart order routing
- Advanced order types (IOC, FOK, Stop, etc.)

---

## Related Projects

- [Project 14 - Order Gateway (XDP)](../14-order-gateway-cpp/README.md) - Market data source
- [Project 15 - Market Maker FSM](../15-market-maker/README.md) - Trading strategy
- [System Architecture](../docs/SYSTEM_ARCHITECTURE.md) - Complete system overview

---

**Build Time:** ~30 seconds
**Status:** Core architecture implemented, integration testing in progress
