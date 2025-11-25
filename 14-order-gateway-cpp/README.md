# Project 14: C++ Order Gateway - XDP Kernel Bypass + Disruptor IPC

**Platform:** Linux (Windows for legacy UDP mode)
**Technology:** C++20, AF_XDP, LMAX Disruptor, Boost.Asio, MQTT (libmosquitto), Kafka (librdkafka)
**Status:** Completed and tested on hardware

---

## Overview

The C++ Order Gateway is the **middleware layer** of the FPGA trading system, acting as a bridge between the FPGA hardware and application clients. It reads BBO (Best Bid/Offer) data from the FPGA via **AF_XDP kernel bypass** and distributes it using **LMAX Disruptor lock-free IPC** for ultra-low-latency communication.

**Primary Data Flow (Ultra-Low-Latency):**
```
FPGA Order Book (UDP) → XDP Kernel Bypass (0.10 μs) → Disruptor Shared Memory → Market Maker FSM (4.13 μs end-to-end)
```

**Legacy Data Flow (Multi-Protocol Distribution):**
```
FPGA Order Book (UDP) → C++ Gateway → TCP/MQTT/Kafka → Applications
```

---

## Architecture

### Core Components

**Primary Architecture (Ultra-Low-Latency Mode):**
```
┌─────────────────────────────────────────────────────────────┐
│                   C++ Order Gateway (Project 14)             │
│                                                              │
│  ┌────────────────┐     ┌──────────────────────────┐        │
│  │  XDP Listener  │────→│     BBO Parser          │        │
│  │  (AF_XDP)      │     │  (Binary Protocol)       │        │
│  │  Port 5000     │     │                          │        │
│  └────────────────┘     └──────────┬───────────────┘        │
│                                    │                         │
│                                    ↓                         │
│                         ┌──────────────────────┐             │
│                         │  Disruptor Producer  │             │
│                         │  (Lock-Free Publish) │             │
│                         └──────────┬───────────┘             │
│                                    │                         │
└────────────────────────────────────┼─────────────────────────┘
                                     │
                    POSIX Shared Memory (/dev/shm/bbo_ring_gateway)
                    Ring Buffer: 1024 entries × 128 bytes = 131 KB
                    Lock-Free IPC: Atomic sequence numbers
                                     │
┌────────────────────────────────────┼─────────────────────────┐
│                                    ↓                         │
│                         ┌──────────────────────┐             │
│                         │  Disruptor Consumer  │             │
│                         │  (Lock-Free Poll)    │             │
│                         └──────────┬───────────┘             │
│                                    │                         │
│                   Market Maker FSM (Project 15)              │
└─────────────────────────────────────────────────────────────┘
```

**Legacy Architecture (Multi-Protocol Distribution):**
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

### 1. UDP Interface (Standard and XDP Kernel Bypass)
- **Async UDP socket listening** using Boost.Asio (standard mode)
- **AF_XDP kernel bypass** for ultra-low latency (optional, requires Linux + XDP program)
- **Port:** 5000 (configurable)
- **Format:** Binary BBO data packets from FPGA (256-byte packets)

**Standard UDP Performance (Validated):**
- **Average:** 0.20 μs, **P50:** 0.19 μs, **P99:** 0.38 μs
- **Test Load:** 10,000 samples @ 400 Hz (25 seconds sustained)
- **Consistency:** 0.06 μs standard deviation
- **P95:** 0.32 μs (95% of messages under 0.32 μs)

**XDP Kernel Bypass Performance (Validated):**
- **Average:** 0.04 μs, **P50:** 0.03 μs, **P99:** 0.12 μs
- **Test Load:** 78,585 samples @ 400 Hz
- **Consistency:** 0.02 μs standard deviation
- **P95:** 0.08 μs
- **Improvement over standard UDP:** 5× faster average, 7× faster P95
- **See:** [README_XDP.md](README_XDP.md) for XDP setup and implementation details

**XDP + Disruptor Integration Performance (Validated):**
- **Average:** 0.10 μs, **P50:** 0.09 μs, **P99:** 0.29 μs
- **Test Load:** 78,514 samples @ 400 Hz
- **End-to-End Latency:** 4.13 μs (FPGA → Market Maker FSM in Project 15)
- **Improvement over TCP Mode:** 3× faster (12.73 μs → 4.13 μs)
- **IPC Method:** LMAX Disruptor lock-free ring buffer (131 KB shared memory)
- **Note:** Slightly higher than raw XDP due to Disruptor publish overhead, but enables ultra-low-latency IPC

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

### 6. Disruptor IPC (Ultra-Low-Latency Mode)
- **Architecture:** LMAX Disruptor lock-free ring buffer
- **Shared Memory:** `/dev/shm/bbo_ring_gateway` (POSIX shm)
- **Ring Buffer Size:** 1024 entries × 128 bytes = 131,328 bytes
- **IPC Method:** Lock-free atomic operations (memory_order_acquire/release)
- **Consumer:** Project 15 (Market Maker FSM)
- **Performance:** 0.10 μs publish latency, 4.13 μs end-to-end

**Disruptor Pattern Benefits:**
- ✅ Zero-copy shared memory (no TCP/socket overhead)
- ✅ Lock-free synchronization (atomic sequence numbers)
- ✅ Cache-line aligned structures (prevents false sharing)
- ✅ Power-of-2 ring buffer (fast modulo using bitwise AND)
- ✅ 3× faster than TCP IPC (12.73 μs → 4.13 μs)

**Critical Implementation Details:**
- Fixed-size data structures (char arrays, not std::string/vector)
- Template parameter `RingBuffer<T, size_t N>` for fixed array
- Signal handlers must be minimal (only set flag, no cleanup)
- Latency measurement at BBO creation, not at read time

**Enable Disruptor Mode:**
```bash
# Run gateway with Disruptor IPC enabled
./order_gateway 0.0.0.0 5000 --use-xdp --enable-disruptor
```

### 7. CSV Logging (Optional)
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

### Building with XDP Support (Linux Only)

**Additional Prerequisites:**
- Linux kernel 5.4+ with XDP support
- libbpf-dev (BPF library)
- libxdp-dev (XDP library)
- clang/llvm (for compiling BPF programs)
- xdp-tools (for loading XDP programs)

**Install Dependencies:**
```bash
# Ubuntu/Debian
sudo apt-get install -y libbpf-dev libxdp-dev clang llvm xdp-tools

# Or build from source
git clone https://github.com/libbpf/libbpf
cd libbpf/src
make
sudo make install
```

**Build with XDP:**
```bash
mkdir build
cd build
cmake -DUSE_XDP=ON ..
make -j$(nproc)
```

**XDP Program Setup:**

1. **Load XDP program** (redirects UDP packets to AF_XDP socket):
```bash
# Reload XDP program (safe, can run multiple times)
./reload_xdp.sh

# Or manually:
sudo xdp-loader load -m native -s xdp eno2 build/xdp_prog.o
```

2. **Verify XDP program loaded:**
```bash
sudo xdp-loader status eno2
# Should show: xdp_prog.o loaded in native mode
```

3. **Configure network queues** (critical for stability):
```bash
# Check current queue configuration
ethtool -l eno2

# Set combined channels to 4 (required for queue_id 3)
sudo ethtool -L eno2 combined 4

# Verify RSS (Receive Side Scaling) distributes to queue 3
# Monitor which queue receives packets:
sudo cat /sys/kernel/debug/tracing/trace_pipe | grep xdp
```

4. **Run gateway with XDP:**
```bash
# Grant network capabilities
sudo setcap cap_net_raw,cap_net_admin,cap_sys_nice=eip ./build/order_gateway

# Run with XDP (use queue_id 3, the only stable configuration)
sudo ./build/order_gateway 0.0.0.0 5000 --use-xdp --xdp-interface eno2 --xdp-queue-id 3

# With debug logging to troubleshoot
sudo ./build/order_gateway 0.0.0.0 5000 --use-xdp --xdp-interface eno2 --xdp-queue-id 3 --enable-xdp-debug
```

**Important Notes:**
- **Queue Configuration:** Only `combined 4` with `queue_id 3` is stable. Other combinations may kill network connectivity.
- **Unload Before Network Changes:** Run `sudo xdp-loader unload eno2 --all` before changing network settings.
- **Root Required:** XDP requires root privileges or CAP_NET_RAW + CAP_NET_ADMIN capabilities.
- **See Also:** [README_XDP.md](README_XDP.md) for detailed XDP architecture and troubleshooting.

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

# XDP mode (kernel bypass)
./order_gateway 0.0.0.0 5000 --use-xdp --xdp-interface eno2 --xdp-queue-id 3

# XDP mode with debug logging
./order_gateway 0.0.0.0 5000 --use-xdp --xdp-interface eno2 --xdp-queue-id 3 --enable-xdp-debug
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
| `--use-xdp` | Use AF_XDP for kernel bypass (requires XDP program loaded) | false |
| `--xdp-interface` | Network interface for XDP (e.g., eno2) | eno2 |
| `--xdp-queue-id` | XDP queue ID (must match RX queue packets arrive on) | 0 |
| `--enable-xdp-debug` | Enable XDP debug logging (verbose ring status, map operations) | false |
| `--enable-disruptor` | Enable Disruptor IPC (POSIX shared memory to Project 15) | false |

**Note:** XDP options require `USE_XDP` build flag and libxdp library. See [README_XDP.md](README_XDP.md) for XDP setup instructions. Disruptor mode creates shared memory at `/dev/shm/bbo_ring_gateway` for ultra-low-latency IPC with Project 15.

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

### Latency Measurements (Validated with RT Optimizations)

#### Standard UDP Mode

| Stage | Latency | Notes |
|-------|---------|-------|
| UDP Receive | < 0.1 µs | Network I/O (included in parse) |
| BBO Parse | **0.20 µs avg** | Binary parse (validated) |
| TCP Publish | ~10-50 µs | localhost |
| MQTT Publish | ~50-100 µs | LAN |
| Kafka Publish | ~100-200 µs | LAN |
| **Total: FPGA → TCP** | **~15-100 µs** | End-to-end |

**Validated Performance (Standard UDP):**
```
=== Project 14 (UDP) Performance Metrics ===
Samples:  10,000
Avg:      0.20 μs
Min:      0.10 μs
Max:      2.12 μs
P50:      0.19 μs
P95:      0.32 μs
P99:      0.38 μs
StdDev:   0.06 μs
```

**Test Conditions:**
- Duration: 25 seconds
- Total messages: 10,000 (8 symbols)
- Average rate: 400 messages/second (realistic FPGA BBO rate)
- Hardware: AMD Ryzen AI 9 365 w/ Radeon 880M
- Configuration: taskset -c 2-5 (CPU isolation) + SCHED_FIFO RT scheduling
- Errors: 0

**Key Characteristics:**
- **Highly consistent:** Standard deviation only 0.06 μs (30% of average)
- **Predictable tail latency:** P99 at 0.38 μs (2× median)
- **Minimal outliers:** Max 2.12 μs (likely single OS scheduling event)

#### XDP Kernel Bypass Mode

**Validated Performance (AF_XDP):**
```
=== Project 14 (XDP) Performance Metrics ===
Samples:  78,585
Avg:      0.04 μs
Min:      0.03 μs
Max:      0.49 μs
P50:      0.04 μs
P95:      0.08 μs
P99:      0.12 μs
StdDev:   0.02 μs
```

**Test Conditions:**
- Total messages: 78,585 (8 symbols × multiple runs)
- Average rate: 400 messages/second (realistic FPGA BBO rate)
- Hardware: AMD Ryzen AI 9 365 w/ Radeon 880M
- Network: Intel I219-LM (eno2)
- Queue: Combined channel 4, queue_id 3 (only stable configuration)
- XDP Mode: Native (driver-level redirect)
- Errors: 0

**Key Characteristics:**
- **Ultra-low latency:** Average 0.04 μs (40 nanoseconds!)
- **Excellent consistency:** Standard deviation only 0.02 μs (50% of average)
- **Tight tail latency:** P99 at 0.12 μs (3× median)
- **Minimal outliers:** Max 0.49 μs (4× lower than standard UDP)
- **5× faster average** than standard UDP (0.04 μs vs 0.20 μs)
- **7× faster P95** than standard UDP (0.08 μs vs 0.32 μs)

#### UDP vs XDP vs XDP+Disruptor Comparison

| Metric | Standard UDP | XDP Kernel Bypass | XDP + Disruptor | Best Improvement |
|--------|--------------|-------------------|-----------------|------------------|
| **Avg Latency** | 0.20 µs | **0.04 µs** | **0.10 µs** | **5× faster (UDP→XDP)** |
| **P50 Latency** | 0.19 µs | **0.04 µs** | **0.09 µs** | **4.8× faster (UDP→XDP)** |
| **P95 Latency** | 0.32 µs | **0.08 µs** | Not measured | **4× faster (UDP→XDP)** |
| **P99 Latency** | 0.38 µs | **0.12 µs** | **0.29 µs** | **3.2× faster (UDP→XDP)** |
| **Std Dev** | 0.06 µs | **0.02 µs** | Not measured | **3× more consistent** |
| **Max Latency** | 2.12 µs | **0.49 µs** | Not measured | **4.3× faster** |
| **Samples** | 10,000 | **78,585** | **78,514** | Large validation datasets |
| **Transport** | Kernel UDP stack | AF_XDP (kernel bypass) | AF_XDP + Disruptor IPC | Zero-copy shared memory |
| **IPC Method** | N/A (parsing only) | N/A (parsing only) | POSIX shm (131 KB) | Lock-free ring buffer |
| **End-to-End** | N/A | N/A | **4.13 µs to Project 15** | 3× faster than TCP mode |

**Key Insights:**
- **XDP eliminates kernel overhead:** 5× average latency improvement by bypassing network stack
- **Tighter tail latencies:** P95 improvement (4×) and much lower max latency (4.3×) shows consistent performance
- **Sub-100ns parsing:** 40 ns average puts parsing well below network jitter
- **Disruptor adds minimal overhead:** 0.06 µs (60 ns) to publish to shared memory ring buffer
- **Disruptor vs TCP IPC:** 3× faster end-to-end (12.73 µs → 4.13 µs) by eliminating socket overhead
- **Validated with large dataset:** 78,514+ samples demonstrate stability and reliability
- **When to use XDP:** For ultra-low latency trading (HFT), market making, or high-frequency analytics
- **When to use Disruptor:** For ultra-low-latency IPC between processes (Project 14 → Project 15)
- **Setup complexity:** XDP requires kernel bypass setup, XDP program loading, and specific queue configuration

### Throughput

- **Max BBO rate:** > 10,000 updates/sec (validated)
- **Realistic load:** 400 messages/sec (matches FPGA BBO output rate)
- **CPU usage:** 2-5% per core (4 isolated cores, taskset -c 2-5)

### Performance vs Project 9 (UART)

| Metric | Project 9 (UART) | Project 14 (UDP) | Improvement |
|--------|------------------|------------------|-------------|
| **Avg Latency** | 10.67 µs | **0.20 µs** | **53× faster** |
| **P50 Latency** | 6.32 µs | **0.19 µs** | **33× faster** |
| **P95 Latency** | 26.33 µs | **0.32 µs** | **82× faster** |
| **P99 Latency** | 50.92 µs | **0.38 µs** | **134× faster** |
| **Std Dev** | 8.04 µs | **0.06 µs** | **134× more consistent** |
| **Max Latency** | 86.14 µs | 2.12 µs | **41× faster** |
| **Samples** | 1,292 | **10,000** | 7.7× more validation data |
| **Transport** | Serial @ 115200 baud | UDP network | Network eliminates bottleneck |

**Key Insights:**
- **53× average latency improvement:** UDP + binary protocol + RT optimization eliminates serial bottleneck
- **Tail latency advantage:** P99 shows 134× improvement, demonstrating consistent low-latency performance
- **Sub-microsecond parsing:** 0.20 μs average puts parsing well below network jitter
- **Validated with realistic load:** 10,000 samples at 400 Hz sustained for 25 seconds

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
- **[15-market-maker/](../15-market-maker/)** - Market maker FSM (TCP client for automated trading)

---

## References

### AF_XDP and Kernel Bypass
- [AF_XDP - Linux Kernel Documentation](https://www.kernel.org/doc/html/latest/networking/af_xdp.html) - Official AF_XDP documentation
- [AF_XDP - DRM/Networking Documentation](https://dri.freedesktop.org/docs/drm/networking/af_xdp.html) - Detailed AF_XDP architecture
- [XDP Tutorial - xdp-project](https://github.com/xdp-project/xdp-tutorial) - Comprehensive XDP tutorial with examples
- [AF_XDP Examples - xdp-project](https://github.com/xdp-project/bpf-examples/blob/main/AF_XDP-example/README.org) - Practical AF_XDP implementation examples
- [DPDK AF_XDP PMD](https://doc.dpdk.org/guides/nics/af_xdp.html) - DPDK's AF_XDP poll mode driver documentation
- [Kernel Bypass Techniques in Linux for HFT](https://lambdafunc.medium.com/kernel-bypass-techniques-in-linux-for-high-frequency-trading-a-deep-dive-de347ccd5407) - Deep dive into kernel bypass for trading systems
- [Kernel Bypass Networking: DPDK, SPDK, io_uring](https://anshadameenza.com/blog/technology/2025-01-15-kernel-bypass-networking-dpdk-spdk-io_uring/) - Comparison of kernel bypass approaches
- [Linux Kernel vs DPDK HTTP Performance](https://talawah.io/blog/linux-kernel-vs-dpdk-http-performance-showdown/) - Performance comparison study

### Ring Buffers and Lock-Free Data Structures
- [LMAX Disruptor - Technical Paper](https://lmax-exchange.github.io/disruptor/disruptor.html) - Official Disruptor pattern documentation
- [Mechanical Sympathy - Martin Thompson](https://mechanical-sympathy.blogspot.com/) - Blog covering Disruptor and performance engineering
- [Imperial HFT - GitHub Repository](https://github.com/0burak/imperial_hft) - Source of Disruptor implementation classes used in Project 14-15
- [Low-Latency Trading Systems - Thesis](https://arxiv.org/abs/2309.04259) - Burak Gunduz thesis on HFT systems with Disruptor pattern
- [Imperial HFT Explanation Video](https://www.youtube.com/watch?v=65XoXkh6VcY) - Video explanation of Disruptor implementation for trading systems
- [Ring Buffers](https://www.snellman.net/blog/archive/2016-12-13-ring-buffers/) - Ring buffer design and implementation
- [eBPF Ring Buffer Optimization](https://ebpfchirp.substack.com/p/challenge-3-ebpf-ring-buffer-optimization) - eBPF ring buffer optimization techniques
- [Lock-Free Programming](https://preshing.com/20120612/an-introduction-to-lock-free-programming/) - Introduction to lock-free programming concepts

### Performance Analysis
- [Brendan Gregg - CPU Flame Graphs](https://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html) - CPU profiling visualization
- [Brendan Gregg - perf Examples](https://www.brendangregg.com/perf.html) - Linux perf tool usage guide
- [Brendan Gregg - Performance Methodology](https://www.brendangregg.com/methodology.html) - Performance analysis methodology

### High-Performance Networking
- [P51: High Performance Networking - University of Cambridge](https://www.cl.cam.ac.uk/teaching/1920/P51/Lecture6.pdf) - Academic perspective on high-performance networking

### Trading Systems Architecture
- [NASDAQ ITCH 5.0 Specification](../docs/NQTVITCHspecification.pdf) - Market data protocol specification (referenced in Project 7)
- [Xilinx Arty A7 Reference Manual](../docs/ARTY_A7_COMPLETE_REFERENCE.md) - FPGA hardware specifications

---

**Build Time:** ~30 seconds
**Hardware Status:** Tested with FPGA UDP transmitter at 5000 port
