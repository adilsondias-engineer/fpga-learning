# Project 14: C++ Order Gateway - UDP High-Performance Data Distribution

**Platform:** Windows/Linux
**Technology:** C++17, Boost.Asio, MQTT (libmosquitto), Kafka (librdkafka)
**Status:** Complete - Hardware Tested

---

## Overview

The C++ Order Gateway is the **middleware layer** of the FPGA trading system, acting as a bridge between the FPGA hardware and multiple application clients. It reads BBO (Best Bid/Offer) data from the FPGA via **UDP** and distributes it to multiple protocols simultaneously.

**Data Flow:**
```
FPGA Order Book (UDP) → C++ Gateway → TCP/MQTT/Kafka → Applications
```

---

## Architecture

### Core Components

```
┌──────────────────────────────────────────────────────────┐
│                   C++ Order Gateway                       │
│                                                           │
│  ┌────────────────┐     ┌──────────────────────────┐     │
│  │  UDP Listener  │────→│     BBO Parser          │     │
│  │  (Async I/O)   │     │  (Binary Protocol)       │     │
│  │  Port 5000     │     │                          │     │
│  └────────────────┘     └──────────┬───────────────┘     │
│                                    │                      │
│                                    ↓                      │
│                         ┌──────────────────┐              │
│                         │  Thread-Safe     │              │
│                         │  BBO Queue       │              │
│                         └─────────┬────────┘              │
│                                   │                       │
│          ┌────────────────────────┼────────────────┐      │
│          ↓                        ↓                ↓      │
│  ┌──────────────┐      ┌──────────────┐  ┌──────────────┐│
│  │ TCP Server   │      │ MQTT Publisher│  │Kafka Producer││
│  │ localhost    │      │ Mosquitto     │  │              ││
│  │ port 9999    │      │ 192.168.0.2   │  │ 192.168.0.203││
│  │              │      │ :1883         │  │ :9092        ││
│  │ JSON output  │      │ v3.1.1        │  │ For future   ││
│  └──────────────┘      └──────────────┘  └──────────────┘│
└──────────────────────────────────────────────────────────┘
```

### Multi-Protocol Distribution

| Protocol | Use Case | Clients | Status |
|----------|----------|---------|--------|
| **TCP** | Java Desktop (low-latency trading terminal) | JavaFX app | ✅ Active |
| **MQTT** | ESP32 IoT + Mobile App (lightweight, mobile-friendly) | ESP32 TFT + .NET MAUI | ✅ Active |
| **Kafka** | Future analytics, data persistence, replay | None yet | 📝 Reserved |

---

## Features

### 1. UDP Interface
- **Async UDP socket listening** using Boost.Asio
- **Port:** 5000 (configurable)
- **Format:** Binary BBO data packets from FPGA
- **Performance:** Ultra-low latency (**2.09 μs avg**, 1.04 μs P50 parse latency)

### 2. BBO Parser
- Parses binary BBO data packets
- Extracts symbol, bid/ask prices, shares, spread
- Direct binary-to-decimal conversion for high performance

### 3. TCP Server
- **Port:** 9999 (configurable)
- **Protocol:** JSON over TCP
- **Clients:** Java desktop trading terminal
- **Format:** Same JSON format as Project 9 (maintains client compatibility)
  ```json
  {
    "type": "bbo",
    "symbol": "AAPL",
    "timestamp": 1699824000123456789,
    "bid": {
      "price": 290.1708,
      "shares": 30
    },
    "ask": {
      "price": 290.2208,
      "shares": 30
    },
    "spread": {
      "price": 0.05,
      "percent": 0.017
    }
  }
  ```

### 4. MQTT Publisher
- **Broker:** Mosquitto @ 192.168.0.2:1883
- **Protocol:** MQTT v3.1.1 (for ESP32/mobile compatibility)
- **Authentication:** trading / trading123
- **Topic:** `bbo_messages`
- **QoS:** 0 (fire-and-forget for low latency)
- **Clients:** ESP32 IoT display, .NET MAUI mobile app

**Why MQTT for IoT/Mobile?**
- ✅ Lightweight protocol (low power consumption)
- ✅ Handles unreliable networks (WiFi/cellular)
- ✅ Low latency (< 100ms)
- ✅ Native support on ESP32 and mobile platforms
- ✅ No dependency issues on Android/iOS

### 5. Kafka Producer
- **Broker:** 192.168.0.203:9092
- **Topic:** `bbo_messages`
- **Key:** Symbol name (for partitioning)
- **Status:** Gateway publishes to Kafka, but **no consumers implemented yet**

**Kafka Reserved for Future Use:**
- Time-series database integration
- Historical replay for backtesting
- Analytics pipelines (Spark, Flink)
- Machine learning feature generation
- Microservices integration

**Why NOT Kafka for mobile/IoT?**
- ❌ Heavy protocol overhead (battery drain)
- ❌ Persistent TCP connections required
- ❌ Native library dependencies (Android issues)
- ❌ Designed for backend services, not edge devices

### 6. CSV Logging (Optional)
- Logs all BBO updates to CSV file
- Format: `timestamp,symbol,bid_price,bid_shares,ask_price,ask_shares,spread`
- Useful for debugging and offline analysis

---

## Build Instructions

### Prerequisites

**Windows:**
- Visual Studio 2019+ with C++17 support
- vcpkg package manager

**Linux:**
- GCC 7+ or Clang 5+
- CMake 3.15+

### Dependencies (via vcpkg)

```bash
# Install vcpkg (if not already installed)
git clone https://github.com/Microsoft/vcpkg.git
cd vcpkg
./bootstrap-vcpkg.sh  # or bootstrap-vcpkg.bat on Windows
./vcpkg integrate install

# Install dependencies
./vcpkg install boost-asio boost-system boost-thread
./vcpkg install nlohmann-json
./vcpkg install librdkafka
./vcpkg install mosquitto
```

### Build

**Windows (Visual Studio):**
```bash
# Open solution in Visual Studio
# Build → Build Solution (Ctrl+Shift+B)
# Or use command line:
msbuild 09-order-gateway-cpp.sln /p:Configuration=Release
```

**Linux (CMake):**
```bash
mkdir build
cd build
cmake ..
make -j$(nproc)
```

---

## Usage

### Basic Usage

```bash
# Windows
order_gateway.exe 0.0.0.0 5000

# Linux
./order_gateway 0.0.0.0 5000
```

### With Options

```bash
# Custom UDP IP and port
order_gateway.exe 192.168.1.100 5000

# Custom TCP port
order_gateway.exe 0.0.0.0 5000 --tcp-port 9999

# Enable CSV logging
order_gateway.exe 0.0.0.0 5000 --csv-file bbo_log.csv

# Custom MQTT broker
order_gateway.exe 0.0.0.0 5000 --mqtt-broker mqtt://192.168.0.2:1883 --mqtt-topic bbo_messages

# Custom Kafka broker
order_gateway.exe 0.0.0.0 5000 --kafka-broker 192.168.0.203:9092 --kafka-topic bbo_messages

# All options combined
order_gateway.exe 0.0.0.0 5000 --tcp-port 9999 --csv-file bbo_log.csv --mqtt-broker mqtt://192.168.0.2:1883
```

### Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `udp_ip` | UDP IP address to bind (0.0.0.0 for all) | **Required** |
| `udp_port` | UDP port to listen on | **Required** |
| `--tcp-port` | TCP server port | 9999 |
| `--csv-file` | CSV log file path | None (disabled) |
| `--mqtt-broker` | MQTT broker URL | mqtt://192.168.0.2:1883 |
| `--mqtt-topic` | MQTT topic name | bbo_messages |
| `--kafka-broker` | Kafka broker URL | 192.168.0.203:9092 |
| `--kafka-topic` | Kafka topic name | bbo_messages |
| `--disable-tcp` | Disable TCP server | false |
| `--disable-mqtt` | Disable MQTT publisher | false |
| `--disable-kafka` | Disable Kafka producer | false |
| `--disable-logger` | Disable CSV logger | false |
| `--enable-rt` | Enable RT scheduling + CPU pinning | false |

---

## System Integration

### Full Data Flow

```
┌──────────────┐
│ FPGA         │ UDP
│ Order Book   │ @ Port 5000
│ (8 symbols)  │
└──────┬───────┘
       │
       ↓  Binary BBO packets
┌──────────────────────────────┐
│ C++ Order Gateway            │
│ - Parse binary → decimal     │
│ - Multi-protocol fanout      │
└──┬────────┬────────┬─────────┘
   │        │        │
   │        │        └──→ [Kafka: Future Analytics]
   │        │
   │        └──→ [MQTT Broker: 192.168.0.2:1883]
   │                 ↓
   │            ┌─────────┬──────────────┐
   │            ↓         ↓              ↓
   │         ESP32    Mobile App    (Future IoT)
   │         TFT      .NET MAUI
   │
   └──→ [TCP: localhost:9999]
            ↓
      Java Desktop
      Trading Terminal
```

### Currently Active Clients

1. **Java Desktop (TCP)** - [12-java-desktop-trading-terminal/](../12-java-desktop-trading-terminal/)
   - Live BBO table with charts
   - Order entry with risk checks
   - Real-time updates via TCP JSON stream

2. **ESP32 IoT Display (MQTT)** - [10-esp32-ticker/](../10-esp32-ticker/)
   - 1.8" TFT LCD color display
   - Real-time ticker for trading floor
   - Low power consumption

3. **Mobile App (MQTT)** - [11-mobile-app/](../11-mobile-app/)
   - .NET MAUI (Android/iOS/Windows)
   - Real-time BBO monitoring
   - Cross-platform support

### Future Kafka Consumers (Not Yet Implemented)

- Analytics dashboard (time-series charts)
- Data archival service (InfluxDB, TimescaleDB)
- Backtesting engine (historical replay)
- ML feature pipeline (real-time + historical)

---

## Performance Characteristics

### Latency Measurements (Baseline - No RT Optimizations)

| Stage | Latency | Notes |
|-------|---------|-------|
| UDP Receive | < 1 µs | Network I/O (included in parse) |
| BBO Parse | **2.09 µs avg** | Binary parse (measured) |
| TCP Publish | ~10-50 µs | localhost |
| MQTT Publish | ~50-100 µs | LAN |
| Kafka Publish | ~100-200 µs | LAN |
| **Total: FPGA → TCP** | **~15-100 µs** | End-to-end |

**Measured Performance:**
```
=== Project 14 (UDP) Performance Metrics ===
Samples:  3,789
Avg:      2.09 μs
Min:      0.42 μs
Max:      45.84 μs
P50:      1.04 μs
P95:      7.01 μs
P99:      11.91 μs
StdDev:   2.51 μs
```

**Test Conditions:**
- Duration: 16.9 seconds
- Total messages: 7,000
- Average rate: 415 messages/second
- Errors: 0

### Throughput

- **Max BBO rate:** > 10,000 updates/sec
- **Tested:** 415 messages/sec (7,000 messages in 16.9 seconds)
- **CPU usage:** < 5% on modern CPU

### Performance vs Project 9 (UART)

| Metric | Project 9 (UART) | Project 14 (UDP) | Improvement |
|--------|------------------|------------------|-------------|
| Avg Latency | 10.67 µs | **2.09 µs** | **5.1x faster** |
| P50 Latency | 6.32 µs | **1.04 µs** | **6.1x faster** |
| P95 Latency | 26.33 µs | **7.01 µs** | **3.8x faster** |
| P99 Latency | 50.92 µs | **11.91 µs** | **4.3x faster** |
| Max Latency | 86.14 µs | **45.84 µs** | **1.9x faster** |
| Samples | 1,292 | **3,789** | 2.9x more data |
| Transport | Serial @ 115200 baud | UDP network | Network superior |

**Key Insight:** UDP provides **~5x average latency improvement** over UART, with the P50 latency showing the most dramatic improvement at **6.1x faster**. The UDP transport layer eliminates the serial bottleneck, allowing the binary BBO parser to operate at its maximum efficiency.

### Real-Time Optimizations

The gateway supports optional real-time optimizations for ultra-low latency applications:

#### CPU Isolation (System-Level)

Isolated CPU cores prevent OS scheduling interference:

```bash
# Add to /etc/default/grub
GRUB_CMDLINE_LINUX="isolcpus=2,3,4,5 nohz_full=2,3,4,5 rcu_nocbs=2,3,4,5"

# Update GRUB and reboot
sudo update-grub
sudo reboot

# Verify isolation
cat /proc/cmdline | grep isolcpus
```

**Impact:** Running on isolated core 2 via `taskset -c 2` achieved **26% latency reduction** (2.09 μs → 1.54 μs avg).

#### RT Scheduling and CPU Pinning (Code-Level)

Enable real-time scheduling with the `--enable-rt` flag:

```bash
# Grant CAP_SYS_NICE capability (required for SCHED_FIFO)
sudo setcap cap_sys_nice=eip ./order_gateway

# Run with RT optimizations
./order_gateway 192.168.0.99 5000 --enable-rt
```

**What `--enable-rt` does:**
- Applies `SCHED_FIFO` real-time scheduling to critical threads
- Pins UDP thread to isolated core 2 (priority 80)
- Pins publish thread to isolated core 3 (priority 70)
- Reduces context switches and scheduler jitter

**Thread Configuration:**

| Thread | Priority (1-99) | CPU Core | Purpose |
|--------|-----------------|----------|---------|
| UDP Listener | 80 (highest) | Core 2 | Critical path: UDP receive + parse |
| Publish Thread | 70 (high) | Core 3 | TCP/MQTT/Kafka distribution |

**Implementation:** See [include/common/rt_config.h](include/common/rt_config.h) for `RTConfig` utilities.

**Expected Impact:**
- Further reduction in average latency (target: < 1.5 μs)
- Lower tail latencies (P95, P99)
- Reduced jitter (standard deviation)
- More deterministic performance

**Performance Results:** See [docs/performance_benchmark.md](../docs/performance_benchmark.md) for detailed RT optimization results.

---

## Code Structure

```
14-order-gateway-cpp/
├── src/
│   ├── main.cpp              # Entry point, argument parsing
│   ├── order_gateway.cpp     # Main gateway orchestration
│   ├── udp_listener.cpp      # Async UDP listening (Boost.Asio)
│   ├── bbo_parser.cpp        # Binary → decimal parser
│   ├── tcp_server.cpp        # JSON TCP server
│   ├── mqtt.cpp              # MQTT publisher (libmosquitto)
│   ├── kafka_producer.cpp    # Kafka producer (librdkafka)
│   └── csv_logger.cpp        # CSV file logging
├── include/
│   ├── order_gateway.h
│   ├── udp_listener.h
│   ├── bbo_parser.h
│   ├── tcp_server.h
│   ├── mqtt.h
│   ├── kafka_producer.h
│   ├── csv_logger.h
│   └── common/
│       ├── perf_monitor.h    # Performance monitoring
│       └── rt_config.h        # RT scheduling utilities
├── vcpkg.json                # Dependency manifest
└── CMakeLists.txt            # Build configuration
```

---

## Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Language** | C++17 | Modern C++ with STL |
| **Async I/O** | Boost.Asio 1.89+ | UDP, TCP sockets |
| **Threading** | Boost.Thread | Multi-threaded architecture |
| **JSON** | nlohmann/json 3.11+ | TCP output serialization |
| **MQTT** | libmosquitto 2.0+ | IoT/mobile publish |
| **Kafka** | librdkafka 2.6+ | Future analytics |
| **Performance** | High-res clock | Latency measurement |
| **Logging** | std::cout | Console output |

---

## Configuration

### Default Configuration (in `main.cpp`)

```cpp
#define DEFAULT_MQTT_BROKER_URL "mqtt://192.168.0.2:1883"
#define DEFAULT_MQTT_CLIENT_ID "order_gateway"
#define DEFAULT_MQTT_USERNAME "trading"
#define DEFAULT_MQTT_PASSWORD "trading123"
#define DEFAULT_MQTT_TOPIC "bbo_messages"

#define DEFAULT_KAFKA_BROKER_URL "192.168.0.203:9092"
#define DEFAULT_KAFKA_CLIENT_ID "order_gateway"
#define DEFAULT_KAFKA_TOPIC "bbo_messages"
```

### UDP Configuration

- **Protocol:** UDP/IPv4
- **Port:** 5000 (configurable)
- **Bind Address:** 0.0.0.0 (all interfaces)
- **Buffer Size:** 2048 bytes
- **Async Reception:** Boost.Asio event-driven

---

## Troubleshooting

### "UDP bind failed"

**Cause:** Port already in use or permissions issue

**Solution:**
```bash
# Check if port 5000 is already in use
# Linux:
sudo netstat -tulpn | grep 5000
# Or
sudo lsof -i :5000

# Windows:
netstat -ano | findstr :5000

# Kill process using the port or choose different port
```

### "MQTT connection failed"

**Cause:** Mosquitto broker not running or wrong credentials

**Solution:**
```bash
# Test MQTT broker connectivity
mosquitto_sub -h 192.168.0.2 -p 1883 -t bbo_messages -u trading -P trading123 -v

# Check Mosquitto logs
sudo tail -f /var/log/mosquitto/mosquitto.log
```

### "Kafka connection failed"

**Cause:** Kafka broker not running or network issue

**Solution:**
```bash
# Test Kafka connectivity
kafka-console-consumer --bootstrap-server 192.168.0.203:9092 --topic bbo_messages

# Check Kafka status
systemctl status kafka
```

### "No data from FPGA"

**Cause:** FPGA not sending UDP packets or network issue

**Solution:**
1. Check FPGA is receiving ITCH packets
2. Verify network connectivity between FPGA and gateway
3. Use Wireshark to capture UDP packets on port 5000
4. Check firewall rules aren't blocking UDP traffic
5. Verify FPGA is sending to correct IP:port

---

## Example Output

```
Order Gateway started
  UDP IP: 0.0.0.0 @ 5000 port
  TCP Port: 9999
  MQTT Broker: mqtt://192.168.0.2:1883
  MQTT Topic: bbo_messages
  Kafka Broker: 192.168.0.203:9092
  Kafka Topic: bbo_messages

UDP thread started
Publish thread started

[BBO] AAPL    Bid: $290.17 (30) | Ask: $290.22 (30) | Spread: $0.05 (0.02%)
[BBO] TSLA    Bid: $431.34 (20) | Ask: $432.18 (25) | Spread: $0.84 (0.19%)
[BBO] SPY     Bid: $322.96 (50) | Ask: $322.99 (50) | Spread: $0.03 (0.01%)
...

^C
Stopping Order Gateway...

=== Project 14 (UDP) Performance Metrics ===
Samples:  3789
Avg:      2.09 μs
Min:      0.42 μs
Max:      45.84 μs
P50:      1.04 μs
P95:      7.01 μs
P99:      11.91 μs
StdDev:   2.51 μs
[PERF] Saved 3789 samples to project14_latency.csv

UDP thread stopped
Publish thread stopped
Order Gateway stopped
```

---

## Next Steps

### Current Status
✅ Gateway complete and operational
✅ TCP client (Java Desktop) working
✅ MQTT clients (ESP32 + Mobile) working
📝 Kafka consumers not yet implemented

### Future Enhancements (Optional)

1. **Kafka Consumer Services:**
   - Time-series database writer (InfluxDB, TimescaleDB)
   - Analytics dashboard (Grafana, custom web UI)
   - Historical data archival

2. **Performance Optimizations:**
   - Zero-copy buffers for high-frequency data
   - Lock-free queues for thread communication
   - DPDK for kernel bypass (if needed)

3. **Monitoring:**
   - Prometheus metrics export
   - Health check endpoint
   - Performance statistics logging

4. **Reliability:**
   - Automatic reconnection for MQTT/Kafka
   - Circuit breaker pattern
   - Graceful degradation (continue if one protocol fails)

---

## Related Projects

- **[08-order-book/](../08-order-book/)** - FPGA order book (data source)
- **[10-esp32-ticker/](../10-esp32-ticker/)** - ESP32 IoT display (MQTT client)
- **[11-mobile-app/](../11-mobile-app/)** - Mobile app (MQTT client)
- **[12-java-desktop-trading-terminal/](../12-java-desktop-trading-terminal/)** - Java desktop (TCP client)

---

**Build Time:** ~30 seconds
**Hardware Status:** Tested with FPGA UDP transmitter at 5000 port
