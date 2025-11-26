# Project 16: Order Execution Engine - Architecture Plan

**Date:** November 2025
**Status:** Planning Phase
**Technology:** C++20, FIX Protocol, Disruptor IPC, Lock-Free Queues

---

## Overview

Project 16 implements a high-performance **Order Execution Engine** that consumes trading decisions from Project 15 (Market Maker FSM) and executes orders via FIX protocol to simulated or real exchanges. This completes the full trading loop: Market Data → Strategy → Execution → Fill Management.

**Position in Architecture:**
```
Project 13 (FPGA Order Book)
    ↓ UDP BBO (0.10 μs)
Project 14 (XDP Gateway)
    ↓ Disruptor IPC (0.50 μs)
Project 15 (Market Maker FSM)
    ↓ Order Generation (3.23 μs)
Project 16 (Order Execution Engine) ← NEW
    ↓ FIX Protocol
Exchange (Simulated or Real)
    ↓ Execution Reports
Project 16 (Fill Handler)
    ↓ Position Updates
Project 15 (Position Tracker)
```

---

## Key Design Goals

1. **Ultra-Low-Latency Order Submission:** Sub-10 μs order entry latency
2. **FIX Protocol Support:** Industry-standard FIX 4.2/4.4 for exchange connectivity
3. **Disruptor Integration:** Lock-free IPC with Project 15 for order flow
4. **Order Lifecycle Management:** New → Pending → Filled/Rejected/Cancelled states
5. **Risk Controls:** Pre-trade checks before order submission
6. **Drop Copy:** Real-time order/fill logging for compliance
7. **Simulated Exchange Mode:** Testing without live market connectivity

---

## Architecture

### Data Flow

```
┌────────────────────────────────────────────────────────────┐
│              Project 15 (Market Maker FSM)                  │
│  Quote Generation → Order Decision                          │
└────────────────────────┬───────────────────────────────────┘
                         │
        POSIX Shared Memory (/dev/shm/order_ring_mm)
        Ring Buffer: 1024 entries × 256 bytes = 256 KB
        Lock-Free IPC: Order submission queue
                         │
┌────────────────────────┴───────────────────────────────────┐
│              Project 16 (Order Execution Engine)            │
│                                                             │
│  ┌────────────────┐     ┌──────────────────────────┐       │
│  │  Disruptor     │────→│   Pre-Trade Risk         │       │
│  │  Consumer      │     │   (Duplicate check,      │       │
│  │  (Order Queue) │     │    position limits)      │       │
│  └────────────────┘     └──────────┬───────────────┘       │
│                                    │                        │
│                                    ↓                        │
│                         ┌──────────────────┐                │
│                         │  Order Manager   │                │
│                         │  (State Machine) │                │
│                         └─────────┬────────┘                │
│                                   │                         │
│          ┌────────────────────────┼────────────────┐        │
│          ↓                        ↓                ↓        │
│  ┌──────────────┐      ┌──────────────┐  ┌──────────────┐  │
│  │ FIX Encoder  │      │ Order Book   │  │ Drop Copy    │  │
│  │ (NewOrder)   │      │ (Local State)│  │ Logger       │  │
│  └──────┬───────┘      └──────────────┘  └──────────────┘  │
│         │                                                   │
│         ↓                                                   │
│  ┌──────────────────────────────┐                          │
│  │     FIX Session Manager      │                          │
│  │  (Logon, Heartbeat, Resend)  │                          │
│  └──────────┬───────────────────┘                          │
│             │                                               │
└─────────────┼───────────────────────────────────────────────┘
              │
              ↓ TCP/IP
┌─────────────────────────────────┐
│   Exchange / Simulated Exchange │
│   (FIX Acceptor)                │
└─────────────┬───────────────────┘
              │ Execution Reports
              ↓
┌─────────────────────────────────────────────────────────────┐
│              Project 16 (Fill Handler)                       │
│                                                              │
│  ┌────────────────┐     ┌──────────────────────────┐        │
│  │  FIX Decoder   │────→│   Fill Validator         │        │
│  │  (ExecReport)  │     │   (Order ID matching)    │        │
│  └────────────────┘     └──────────┬───────────────┘        │
│                                    │                         │
│                                    ↓                         │
│                         ┌──────────────────┐                 │
│                         │  Fill Manager    │                 │
│                         │  (Position Update)│                │
│                         └─────────┬────────┘                 │
│                                   │                          │
│                                   ↓                          │
│                         Disruptor Producer                   │
│                         (Fill notifications to Project 15)   │
└──────────────────────────┬──────────────────────────────────┘
                           │
        POSIX Shared Memory (/dev/shm/fill_ring_oe)
        Ring Buffer: 1024 entries × 256 bytes = 256 KB
        Lock-Free IPC: Fill notification queue
                           │
┌──────────────────────────┴──────────────────────────────────┐
│              Project 15 (Position Tracker Update)            │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Disruptor Consumer (Order Intake)

**Purpose:** Consume order requests from Project 15 via shared memory

**Data Structure:**
```cpp
struct OrderRequest {
    char order_id[32];          // Unique order ID
    char symbol[16];            // Symbol (AAPL, TSLA, etc.)
    char side;                  // 'B' = Buy, 'S' = Sell
    double price;               // Limit price
    uint32_t quantity;          // Shares
    char order_type;            // 'L' = Limit, 'M' = Market
    char time_in_force;         // 'D' = Day, 'I' = IOC, 'F' = FOK
    int64_t timestamp_ns;       // Order creation time
    bool valid;
};
```

**Operation:**
- Poll `/dev/shm/order_ring_mm` for new orders from Project 15
- Validate order structure (symbol, price, quantity)
- Pass to pre-trade risk engine

---

### 2. Pre-Trade Risk Engine

**Purpose:** Validate orders before submission to exchange

**Risk Checks:**
1. **Duplicate Order Check:** Prevent double-submission
2. **Position Limit Check:** max_position per symbol (from Project 15 config)
3. **Notional Limit Check:** max_notional exposure
4. **Price Collar Check:** Prevent fat-finger errors (price within N% of BBO)
5. **Rate Limiting:** Max orders per second per symbol
6. **Market Hours Check:** Trading hours validation

**Implementation:**
```cpp
class PreTradeRisk {
public:
    enum class RiskResult {
        APPROVED,
        REJECTED_DUPLICATE,
        REJECTED_POSITION_LIMIT,
        REJECTED_NOTIONAL_LIMIT,
        REJECTED_PRICE_COLLAR,
        REJECTED_RATE_LIMIT,
        REJECTED_MARKET_CLOSED
    };

    RiskResult validate(const OrderRequest& order);

private:
    std::unordered_map<std::string, int32_t> positions_;  // symbol → position
    std::unordered_map<std::string, double> notional_;    // symbol → exposure
    std::unordered_set<std::string> pending_orders_;      // order_id set
    RateLimiter rate_limiter_;
};
```

---

### 3. Order Manager (State Machine)

**Purpose:** Manage order lifecycle state transitions

**Order States:**
```cpp
enum class OrderState {
    NEW,              // Order created, not yet sent
    PENDING_NEW,      // NewOrderSingle sent, awaiting ack
    ACTIVE,           // Order accepted by exchange
    PARTIALLY_FILLED, // Partial execution
    FILLED,           // Fully executed
    PENDING_CANCEL,   // CancelRequest sent
    CANCELLED,        // Cancel confirmed
    REJECTED          // Order rejected by exchange or risk
};
```

**State Transitions:**
```
NEW → PENDING_NEW → ACTIVE → PARTIALLY_FILLED → FILLED
                      ↓             ↓
                  CANCELLED ← PENDING_CANCEL
                      ↓
                  REJECTED
```

**Order Book Storage:**
```cpp
class OrderBook {
public:
    void add_order(const Order& order);
    void update_order(const std::string& order_id, OrderState state);
    Order* get_order(const std::string& order_id);
    std::vector<Order*> get_active_orders(const std::string& symbol);

private:
    std::unordered_map<std::string, Order> orders_;  // order_id → Order
    std::unordered_map<std::string, std::vector<std::string>> symbol_orders_;  // symbol → order_ids
};
```

---

### 4. FIX Protocol Engine

**Purpose:** Encode/decode FIX messages for exchange communication

**FIX Message Types:**
- **Outbound:**
  - Logon (MsgType=A)
  - Heartbeat (MsgType=0)
  - TestRequest (MsgType=1)
  - NewOrderSingle (MsgType=D)
  - OrderCancelRequest (MsgType=F)
  - OrderCancelReplaceRequest (MsgType=G)
  - Logout (MsgType=5)

- **Inbound:**
  - Logon (MsgType=A)
  - Heartbeat (MsgType=0)
  - TestRequest (MsgType=1)
  - ExecutionReport (MsgType=8)
  - Reject (MsgType=3)
  - Logout (MsgType=5)

**NewOrderSingle Example (FIX 4.2):**
```
8=FIX.4.2|9=176|35=D|49=MMFIRM|56=EXCHANGE|34=5|52=20251125-12:30:00|
11=ORD123456|21=1|55=AAPL|54=1|60=20251125-12:30:00|38=100|40=2|44=150.50|
59=0|10=123|
```

**Implementation:**
```cpp
class FIXEncoder {
public:
    std::string encode_new_order(const OrderRequest& order);
    std::string encode_cancel(const std::string& order_id, const std::string& orig_order_id);
    std::string encode_heartbeat();
    std::string encode_logon(const std::string& sender_comp_id, const std::string& target_comp_id);

private:
    uint32_t seq_num_;
    std::string calculate_checksum(const std::string& msg);
};

class FIXDecoder {
public:
    struct ExecutionReport {
        std::string order_id;       // Tag 11
        std::string exec_id;        // Tag 17
        char exec_type;             // Tag 150 (0=New, 1=PartialFill, 2=Fill, etc.)
        char order_status;          // Tag 39 (0=New, 1=PartialFill, 2=Filled, etc.)
        std::string symbol;         // Tag 55
        char side;                  // Tag 54
        uint32_t order_qty;         // Tag 38
        uint32_t cum_qty;           // Tag 14
        double avg_price;           // Tag 6
        int64_t transact_time;      // Tag 60
    };

    ExecutionReport decode_execution_report(const std::string& fix_msg);
    bool validate_checksum(const std::string& fix_msg);
};
```

---

### 5. FIX Session Manager

**Purpose:** Maintain FIX session state (logon, heartbeat, sequence numbers)

**Session Management:**
```cpp
class FIXSession {
public:
    enum class State {
        DISCONNECTED,
        CONNECTING,
        LOGGED_IN,
        HEARTBEAT_TIMEOUT,
        LOGGING_OUT
    };

    void connect(const std::string& host, uint16_t port);
    void logon(const std::string& sender_comp_id, const std::string& target_comp_id);
    void send_heartbeat();
    void logout();

    bool is_logged_in() const { return state_ == State::LOGGED_IN; }
    uint32_t next_seq_num() { return ++outbound_seq_num_; }

private:
    State state_;
    std::string sender_comp_id_;
    std::string target_comp_id_;
    uint32_t outbound_seq_num_;
    uint32_t inbound_seq_num_;
    std::chrono::steady_clock::time_point last_heartbeat_;
    boost::asio::ip::tcp::socket socket_;
};
```

**Heartbeat Management:**
- Send heartbeat every 30 seconds (configurable)
- Detect missed heartbeats (timeout = 90 seconds)
- Automatic reconnection on timeout

---

### 6. Fill Handler

**Purpose:** Process execution reports and update positions

**Fill Processing:**
```cpp
class FillHandler {
public:
    void process_execution_report(const FIXDecoder::ExecutionReport& exec_report);

private:
    void handle_new_ack(const FIXDecoder::ExecutionReport& exec_report);
    void handle_partial_fill(const FIXDecoder::ExecutionReport& exec_report);
    void handle_fill(const FIXDecoder::ExecutionReport& exec_report);
    void handle_cancelled(const FIXDecoder::ExecutionReport& exec_report);
    void handle_rejected(const FIXDecoder::ExecutionReport& exec_report);

    void notify_position_tracker(const std::string& symbol, int32_t qty_delta, double avg_price);

    OrderBook* order_book_;
    DisruptorProducer* fill_producer_;  // Notify Project 15
};
```

**Fill Notification to Project 15:**
```cpp
struct FillNotification {
    char order_id[32];
    char symbol[16];
    char side;                  // 'B' = Buy, 'S' = Sell
    uint32_t fill_qty;          // Shares filled this report
    uint32_t cum_qty;           // Total shares filled
    double avg_price;           // Average fill price
    int64_t transact_time;      // Exchange timestamp
    bool is_complete;           // true if fully filled
};
```

---

### 7. Drop Copy Logger

**Purpose:** Compliance logging of all orders and fills

**Log Format (CSV):**
```csv
timestamp,order_id,symbol,side,price,quantity,order_type,state,fill_qty,fill_price,exec_id
2025-11-25T12:30:00.123456,ORD123,AAPL,B,150.50,100,L,PENDING_NEW,0,0.00,
2025-11-25T12:30:00.234567,ORD123,AAPL,B,150.50,100,L,ACTIVE,0,0.00,EXEC001
2025-11-25T12:30:01.345678,ORD123,AAPL,B,150.50,100,L,FILLED,100,150.48,EXEC002
```

**Implementation:**
```cpp
class DropCopyLogger {
public:
    void log_order_new(const OrderRequest& order);
    void log_order_ack(const std::string& order_id, const std::string& exec_id);
    void log_order_fill(const std::string& order_id, const FIXDecoder::ExecutionReport& exec_report);
    void log_order_cancel(const std::string& order_id);
    void log_order_reject(const std::string& order_id, const std::string& reason);

private:
    std::ofstream log_file_;
    std::mutex log_mutex_;
};
```

---

### 8. Simulated Exchange (Testing Mode)

**Purpose:** Mock exchange for testing without live connectivity

**Features:**
- Accept FIX NewOrderSingle messages
- Generate synthetic ExecutionReports
- Configurable fill simulation:
  - Immediate fills (IOC orders)
  - Partial fills (configurable fill ratio)
  - Random reject rate
  - Latency simulation (configurable delay)

**Implementation:**
```cpp
class SimulatedExchange {
public:
    void start(uint16_t port);
    void configure_fill_latency(uint64_t latency_us);
    void configure_fill_ratio(double ratio);  // 0.0 - 1.0
    void configure_reject_rate(double rate);  // 0.0 - 1.0

private:
    void handle_new_order(const std::string& fix_msg);
    void generate_execution_report(const OrderRequest& order, char exec_type);

    boost::asio::ip::tcp::acceptor acceptor_;
    std::mt19937 rng_;
};
```

---

## Performance Targets

### Latency Breakdown

| Stage | Target Latency | Notes |
|-------|----------------|-------|
| Order intake (Disruptor poll) | < 0.50 μs | Lock-free shared memory read |
| Pre-trade risk checks | < 0.50 μs | Hash lookups, bounds checks |
| FIX encoding | < 1.00 μs | String formatting |
| TCP send (localhost) | < 5.00 μs | Kernel TCP stack |
| **Total: Order Generation → FIX Send** | **< 7.00 μs** | Order entry latency |
| Exchange processing (simulated) | 10-100 μs | Configurable |
| FIX decode (exec report) | < 1.00 μs | String parsing |
| Fill processing | < 0.50 μs | Order book update |
| Position update (Disruptor publish) | < 0.50 μs | Lock-free shared memory write |
| **Total: Fill Receipt → Position Update** | **< 2.00 μs** | Fill processing latency |

**End-to-End Target:**
- **Order Decision (Project 15) → Exchange:** < 10 μs
- **Exchange Fill → Position Update (Project 15):** < 15 μs

---

## Configuration

**config.json:**
```json
{
  "fix": {
    "protocol_version": "FIX.4.2",
    "sender_comp_id": "MMFIRM",
    "target_comp_id": "EXCHANGE",
    "heartbeat_interval_sec": 30,
    "heartbeat_timeout_sec": 90
  },
  "exchange": {
    "mode": "simulated",
    "host": "localhost",
    "port": 5001,
    "simulated_latency_us": 50,
    "simulated_fill_ratio": 1.0,
    "simulated_reject_rate": 0.0
  },
  "risk": {
    "enable_duplicate_check": true,
    "enable_position_limit": true,
    "enable_notional_limit": true,
    "enable_price_collar": true,
    "price_collar_percent": 10.0,
    "rate_limit_per_sec": 100
  },
  "disruptor": {
    "order_queue_path": "/dev/shm/order_ring_mm",
    "fill_queue_path": "/dev/shm/fill_ring_oe"
  },
  "logging": {
    "drop_copy_file": "drop_copy.csv",
    "enable_console_log": true,
    "log_level": "info"
  },
  "performance": {
    "enable_rt": true,
    "cpu_cores": [4, 5],
    "rt_priority": 60
  }
}
```

---

## Project Structure

```
16-order-execution-engine/
├── src/
│   ├── main.cpp                      # Entry point, signal handling
│   ├── order_execution_engine.cpp    # Main orchestrator
│   ├── disruptor_consumer.cpp        # Order intake from Project 15
│   ├── pre_trade_risk.cpp            # Risk checks
│   ├── order_manager.cpp             # Order lifecycle FSM
│   ├── order_book.cpp                # Local order state
│   ├── fix_encoder.cpp               # FIX message encoding
│   ├── fix_decoder.cpp               # FIX message decoding
│   ├── fix_session.cpp               # FIX session management
│   ├── fill_handler.cpp              # Execution report processing
│   ├── drop_copy_logger.cpp          # Compliance logging
│   ├── simulated_exchange.cpp        # Mock exchange for testing
│   └── disruptor_producer.cpp        # Fill notifications to Project 15
├── include/
│   ├── order_execution_engine.h
│   ├── disruptor_consumer.h
│   ├── pre_trade_risk.h
│   ├── order_manager.h
│   ├── order_book.h
│   ├── fix_encoder.h
│   ├── fix_decoder.h
│   ├── fix_session.h
│   ├── fill_handler.h
│   ├── drop_copy_logger.h
│   ├── simulated_exchange.h
│   ├── disruptor_producer.h
│   ├── order_types.h                 # Shared data structures
│   └── common/
│       ├── perf_monitor.h            # Latency measurement
│       └── rt_config.h               # RT scheduling
├── tests/
│   ├── test_fix_encoder.cpp
│   ├── test_fix_decoder.cpp
│   ├── test_order_manager.cpp
│   ├── test_pre_trade_risk.cpp
│   └── test_simulated_exchange.cpp
├── CMakeLists.txt
├── vcpkg.json
├── config.json
└── README.md
```

---

## Dependencies

**vcpkg.json:**
```json
{
  "name": "order-execution-engine",
  "version": "1.0.0",
  "dependencies": [
    "boost-asio",
    "spdlog",
    "nlohmann-json",
    "gtest"
  ]
}
```

**Additional:**
- Common Disruptor headers from `../common/disruptor/`
- Common BBO data structures from `../common/bbo_data.h`

---

## Testing Strategy

### Unit Tests
1. **FIX Encoding/Decoding:** Validate message parsing and generation
2. **Pre-Trade Risk:** Test all risk rejection scenarios
3. **Order Manager:** Test state transitions
4. **Simulated Exchange:** Validate fill generation

### Integration Tests
1. **Project 15 → Project 16:** End-to-end order flow via Disruptor
2. **FIX Session:** Connect to simulated exchange, send orders
3. **Fill Loop:** Order submission → Fill → Position update

### Performance Tests
1. **Latency Benchmark:** Measure order entry and fill processing latency
2. **Throughput Test:** Max orders/sec sustainable
3. **Stress Test:** 10,000 orders, verify no drops

---

## Risk Considerations

### Pre-Production Validation
1. **Order Reconciliation:** All orders logged before submission
2. **Position Reconciliation:** Compare Project 15 positions with fill notifications
3. **FIX Sequence Gaps:** Detect and handle missing execution reports
4. **Duplicate Prevention:** Critical - prevent double-order submission

### Failure Modes
1. **Exchange Disconnect:** Queue orders, reconnect, resend
2. **Fill Timeout:** Cancel stale orders
3. **Position Drift:** Periodic position reconciliation
4. **Memory Exhaustion:** Ring buffer full → block Project 15

---

## Future Enhancements (Post-MVP)

1. **Multi-Venue Support:** Connect to multiple exchanges simultaneously
2. **Smart Order Routing:** Route orders to best venue (price, liquidity)
3. **FPGA Order Submission:** Move FIX encoding to FPGA for sub-microsecond latency
4. **Hardware Timestamping:** NIC-level timestamps for accurate TCA
5. **Cancel-Replace Optimization:** Modify orders instead of cancel-resend
6. **IOC/FOK Support:** Immediate-or-Cancel and Fill-or-Kill order types
7. **Market Data Integration:** Use real-time quotes for price collar checks
8. **Post-Trade Analytics:** TCA (Transaction Cost Analysis), slippage measurement

---

## Success Metrics

### Functional Requirements
- ✓ Accept orders from Project 15 via Disruptor
- ✓ Pre-trade risk checks operational
- ✓ FIX protocol connectivity established
- ✓ Order lifecycle management functional
- ✓ Fill handling and position updates working
- ✓ Drop copy logging complete

### Performance Requirements
- ✓ Order entry latency < 10 μs (P99)
- ✓ Fill processing latency < 5 μs (P99)
- ✓ Sustained throughput > 1,000 orders/sec
- ✓ Zero order drops under normal load

### Risk Requirements
- ✓ 100% duplicate detection accuracy
- ✓ Position limits enforced pre-trade
- ✓ All orders logged before submission
- ✓ Graceful degradation on exchange disconnect

---

## Timeline Estimate

| Phase | Tasks | Estimated Time |
|-------|-------|----------------|
| **Phase 1: Core Infrastructure** | Project setup, Disruptor integration, order types | 10 hours |
| **Phase 2: FIX Protocol** | FIX encoder/decoder, session management | 15 hours |
| **Phase 3: Order Manager** | State machine, order book, lifecycle | 12 hours |
| **Phase 4: Risk Engine** | Pre-trade checks, rate limiting | 8 hours |
| **Phase 5: Fill Handler** | Execution report processing, position updates | 10 hours |
| **Phase 6: Simulated Exchange** | Mock exchange for testing | 8 hours |
| **Phase 7: Testing** | Unit tests, integration tests, performance tests | 12 hours |
| **Phase 8: Documentation** | README, architecture docs, lessons learned | 5 hours |
| **Total** | | **80 hours** |

---

## References

### FIX Protocol
- [FIX Protocol 4.2 Specification](https://www.fixtrading.org/standards/fix-4-2/)
- [FIX Protocol 4.4 Specification](https://www.fixtrading.org/standards/fix-4-4/)
- [QuickFIX C++ Library](https://www.quickfixengine.org/) - Reference implementation

### Order Execution Systems
- [Trading System Architecture - Martin Fowler](https://martinfowler.com/articles/trading-system.html)
- [Low-Latency Order Execution](https://www.youtube.com/watch?v=NH1Tta7purM) - CppCon talk

### Risk Management
- [Pre-Trade Risk Controls - SEC Guidance](https://www.sec.gov/rules/final/2010/34-63241.pdf)
- [Market Access Rule 15c3-5](https://www.sec.gov/rules/final/2010/34-63241.pdf)

---

**Next Steps:**
1. Review and approve architecture plan
2. Create Project 16 directory structure
3. Implement Phase 1 (Core Infrastructure)
4. Begin FIX protocol integration (Phase 2)
