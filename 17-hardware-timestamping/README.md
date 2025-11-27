# Project 17: Hardware Timestamping and Latency Measurement

## Overview

This project implements **kernel-level software timestamping** using Linux's `SO_TIMESTAMPING` socket option to measure packet reception latency with nanosecond precision. It provides a complete latency tracking system with histogram-based percentile calculation and Prometheus metrics export for production monitoring.

### Key Features

- **Kernel-Level Timestamping**: Uses `SO_TIMESTAMPING` to capture packet arrival timestamps at the kernel network stack (~10-50ns precision)
- **Latency Tracking**: Measures kernel-to-application latency with lock-free histogram and percentile calculation
- **Prometheus Integration**: HTTP `/metrics` endpoint for Grafana/Prometheus monitoring
- **Thread-Safe**: Lock-free atomic operations for high-frequency latency recording
- **Configurable**: JSON-based configuration for thresholds, ports, and behavior
- **Production-Ready**: Graceful shutdown, error handling, and resource cleanup

### Why This Matters for HFT

In high-frequency trading, **every nanosecond counts**. Understanding where latency is introduced in your system is critical for optimization. This project measures the latency between:

1. **Kernel RX Timestamp**: When the packet arrives at the network stack (captured by kernel)
2. **Application RX Timestamp**: When your application receives the packet via `recvmsg()`

This `kernel → application` latency is typically **10-100 microseconds** and represents overhead from:
- System call overhead (`recvmsg`)
- Context switching
- CPU scheduling delays
- Memory copying from kernel to userspace

By measuring this latency, you can:
- Identify performance bottlenecks in your packet processing pipeline
- Validate that your system meets latency requirements (e.g., <50μs P99)
- Monitor latency degradation over time in production
- Compare different kernel tuning parameters (kernel bypass, CPU pinning, etc.)

---

## Architecture

### Components

1. **TimestampSocket** ([timestamp_socket.h](include/timestamp_socket.h))
   - UDP socket wrapper with `SO_TIMESTAMPING` support
   - Captures kernel RX timestamp via ancillary data (control messages)
   - Captures application RX timestamp using `clock_gettime()`
   - Computes kernel→app latency in nanoseconds

2. **LatencyTracker** ([latency_tracker.h](include/latency_tracker.h))
   - Lock-free histogram with 25 buckets (50ns to 5s+)
   - Percentile calculation (P50, P90, P95, P99, P99.9)
   - Summary statistics (min, max, mean, stddev)
   - Prometheus format export

3. **PrometheusExporter** ([prometheus_exporter.h](include/prometheus_exporter.h))
   - HTTP server for `/metrics` endpoint (default port 9090)
   - Thread-safe metrics collection
   - Compatible with Prometheus/Grafana

### Data Flow

```
UDP Packet Arrival
      |
      v
[Kernel Network Stack] <-- Kernel RX Timestamp (SO_TIMESTAMPING)
      |
      v
[recvmsg() System Call]
      |
      v
[Application Space] <-- Application RX Timestamp (clock_gettime)
      |
      v
[Latency Calculation] = App RX - Kernel RX
      |
      v
[LatencyTracker] --> Histogram + Percentiles
      |
      v
[PrometheusExporter] --> HTTP /metrics endpoint
      |
      v
[Prometheus/Grafana] --> Production Monitoring
```

---

## Prerequisites

### System Requirements

- **OS**: Linux (kernel 2.6.30+ for `SO_TIMESTAMPING`)
- **CPU**: Any x86_64 or ARM64 processor
- **NIC**: Any standard network interface (no special hardware required)
- **Memory**: ~100 MB for 100k samples

### Software Dependencies

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y build-essential cmake nlohmann-json3-dev

# RHEL/CentOS/Fedora
sudo dnf install -y gcc-c++ cmake json-devel
```

**Required Libraries:**
- C++20 compiler (GCC 10+, Clang 11+)
- CMake 3.20+
- nlohmann/json (JSON parsing)
- pthread (POSIX threads)

---

## Build Instructions

### 1. Build with CMake

```bash
cd 17-hardware-timestamping
mkdir build && cd build
cmake ..
make -j$(nproc)
```

**Build output:**
- `timestamp_demo` - Main executable
- `libtimestamp_lib.a` - Static library for integration

### 2. Build Configuration Options

```bash
# Debug build (with symbols, no optimization)
cmake -DCMAKE_BUILD_TYPE=Debug ..
make -j$(nproc)

# Release build (optimized, -O3)
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
```

### 3. Installation

```bash
sudo make install
```

**Installed files:**
- `/usr/local/bin/timestamp_demo` - Executable
- `/usr/local/lib/libtimestamp_lib.a` - Static library
- `/usr/local/include/timestamp/*.h` - Headers

---

## Usage

### 1. Basic Usage

```bash
cd build
./timestamp_demo
```

**Default behavior:**
- Listens on UDP port **5000** (shares with Order Gateway via SO_REUSEPORT)
- Prometheus metrics on port **9090**
- Prints statistics every 5 seconds
- Samples ~50% of packets for latency measurement

### 2. Custom Configuration

```bash
./timestamp_demo ../config.json
```

**Configuration File** (`config.json`):
```json
{
  "udp_port": 5000,
  "metrics_port": 9090,
  "interface": "",
  "warning_threshold_ns": 100000,
  "critical_threshold_ns": 1000000,
  "max_samples": 100000,
  "enable_console_output": true,
  "stats_interval_ms": 5000
}
```

**Note:** Port 5000 is shared with the Order Gateway (Project 14) using **SO_REUSEPORT**, which allows both processes to bind to the same port. The kernel load-balances incoming UDP packets between them, so this demo samples approximately 50% of packets for latency measurement.

**Configuration Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `udp_port` | int | 5000 | UDP port to listen for packets (5000 = FPGA market data) |
| `metrics_port` | int | 9090 | HTTP port for Prometheus `/metrics` endpoint |
| `interface` | string | "" | Network interface (e.g., "eno2"), empty for any |
| `warning_threshold_ns` | int | 100000 | Latency threshold (ns) for warning logs (100μs) |
| `critical_threshold_ns` | int | 1000000 | Latency threshold (ns) for critical logs (1ms) |
| `max_samples` | int | 100000 | Maximum samples to store for percentile calculation |
| `enable_console_output` | bool | true | Print per-packet latency to console (disable for production) |
| `stats_interval_ms` | int | 5000 | Interval (ms) to print statistics summary |

### 3. Test Packet Sender

Send test UDP packets to measure latency:

```bash
# Terminal 1: Run timestamp demo
./timestamp_demo

# Terminal 2: Send test packets
echo "test packet" | nc -u localhost 5000

# Or use Python
python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.sendto(b'test', ('localhost', 5000))"
```

### 4. View Prometheus Metrics

```bash
curl http://localhost:9090/metrics
```

**Example output:**
```
# HELP latency_kernel_to_app_ns Latency histogram (nanoseconds)
# TYPE latency_kernel_to_app_ns histogram
latency_kernel_to_app_ns_bucket{le="50"} 0
latency_kernel_to_app_ns_bucket{le="100"} 0
latency_kernel_to_app_ns_bucket{le="200"} 0
latency_kernel_to_app_ns_bucket{le="500"} 0
latency_kernel_to_app_ns_bucket{le="1000"} 12
latency_kernel_to_app_ns_bucket{le="2000"} 45
latency_kernel_to_app_ns_bucket{le="5000"} 89
latency_kernel_to_app_ns_bucket{le="10000"} 156
latency_kernel_to_app_ns_bucket{le="+Inf"} 200
latency_kernel_to_app_ns_sum 456789
latency_kernel_to_app_ns_count 200

# HELP latency_kernel_to_app_percentile_ns Latency percentiles (nanoseconds)
# TYPE latency_kernel_to_app_percentile_ns gauge
latency_kernel_to_app_percentile_ns{percentile="p50"} 2345
latency_kernel_to_app_percentile_ns{percentile="p90"} 5678
latency_kernel_to_app_percentile_ns{percentile="p95"} 7890
latency_kernel_to_app_percentile_ns{percentile="p99"} 12345
latency_kernel_to_app_percentile_ns{percentile="p99_9"} 23456
```

---

## Integration with Projects 14-15-16

### Option 1: Library Integration

Link against `libtimestamp_lib.a` to add timestamping to your existing projects.

**Example: Add timestamping to Project 14 Order Gateway**

```cpp
// In 14-order-gateway/src/main.cpp
#include <timestamp_socket.h>
#include <latency_tracker.h>

using namespace timestamp;

int main() {
    // Create timestamping socket (instead of raw UDP socket)
    TimestampSocket socket(12345);

    // Create latency tracker
    LatencyTracker tracker("order_gateway_rx", 100000);

    // Existing order gateway logic...
    OrderGateway gateway;

    while (running) {
        // Receive packet with timestamp
        TimestampedPacket packet = socket.receive_with_timestamp();

        // Record latency
        tracker.record_latency(packet.kernel_to_app_ns);

        // Process packet (existing code)
        gateway.process_packet(packet.data, packet.data_len);
    }
}
```

**CMakeLists.txt modification:**
```cmake
# Add timestamping library
target_link_libraries(order_gateway
    PRIVATE
        timestamp_lib  # Add this line
        disruptor
)
```

### Option 2: Standalone Monitoring

Run `timestamp_demo` alongside existing projects to monitor network latency:

```bash
# Terminal 1: Order Gateway (Project 14)
cd 14-order-gateway/build
./order_gateway

# Terminal 2: Market Maker (Project 15)
cd 15-market-maker/build
./market_maker

# Terminal 3: Order Execution Engine (Project 16)
cd 16-order-execution/build
./order_execution_engine

# Terminal 4: Latency Monitor (Project 17)
cd 17-hardware-timestamping/build
./timestamp_demo
```

---

## Performance Characteristics

### Expected Latency Ranges

| Scenario | Typical Latency | P99 Latency |
|----------|----------------|-------------|
| **Loopback (localhost)** | 1-5 μs | 10-20 μs |
| **LAN (1 GbE)** | 10-50 μs | 100-200 μs |
| **LAN (10 GbE)** | 5-20 μs | 50-100 μs |
| **Kernel Bypass (DPDK)** | 0.5-2 μs | 5-10 μs |
| **Hardware Timestamping** | 0.1-1 μs | 2-5 μs |

### Measurement Overhead

- **Per-packet overhead**: ~100-200 ns (atomic histogram update)
- **Memory usage**: ~800 KB for 100k samples
- **CPU usage**: <1% (background stats thread)

### Lock-Free Histogram Design

The `LatencyTracker` uses **atomic operations** for thread-safe histogram updates without locks:

```cpp
// Lock-free histogram update
void LatencyTracker::record_latency(uint64_t latency_ns) {
    size_t bucket_idx = find_bucket(latency_ns);
    histogram_[bucket_idx].fetch_add(1, std::memory_order_relaxed);

    count_.fetch_add(1, std::memory_order_relaxed);
    sum_ns_.fetch_add(latency_ns, std::memory_order_relaxed);

    // Lock-free min/max update via CAS loop
    uint64_t current_min = min_ns_.load(std::memory_order_relaxed);
    while (latency_ns < current_min &&
           !min_ns_.compare_exchange_weak(current_min, latency_ns)) {}
}
```

**Why lock-free matters:**
- No mutex contention in high-frequency packet processing
- Sub-microsecond overhead per measurement
- Suitable for >1M packets/sec throughput

---

## Prometheus/Grafana Integration

### 1. Prometheus Configuration

Add to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'hardware_timestamping'
    static_configs:
      - targets: ['localhost:9090']
        labels:
          service: 'timestamp_demo'
          project: 'project17'
```

### 2. Grafana Dashboard Queries

**P99 Latency Over Time:**
```promql
latency_kernel_to_app_percentile_ns{percentile="p99"}
```

**Average Latency:**
```promql
rate(latency_kernel_to_app_ns_sum[1m]) / rate(latency_kernel_to_app_ns_count[1m])
```

**Packet Rate:**
```promql
rate(latency_kernel_to_app_ns_count[1m])
```

**Histogram Heatmap:**
```promql
sum(rate(latency_kernel_to_app_ns_bucket[1m])) by (le)
```

### 3. Sample Grafana Dashboard JSON

See [grafana-dashboard.json](docs/grafana-dashboard.json) for complete dashboard configuration.

---

## Troubleshooting

### Issue: "Hardware timestamping not available"

**Cause:** Kernel doesn't support `SO_TIMESTAMPING` (rare on modern Linux)

**Solution:** System falls back to application-level timestamps (still functional)

**Verify kernel support:**
```bash
grep CONFIG_NETWORK_PHY_TIMESTAMPING /boot/config-$(uname -r)
```

### Issue: High latency (>1ms P99)

**Possible causes:**
1. System under heavy load (CPU saturation)
2. CPU frequency scaling enabled (use `performance` governor)
3. NUMA misalignment (packet received on different NUMA node)
4. Interrupt coalescing enabled on NIC

**Solutions:**
```bash
# Disable CPU frequency scaling
sudo cpupower frequency-set -g performance

# Pin interrupts to specific CPU
sudo sh -c "echo 1 > /proc/irq/$(cat /proc/interrupts | grep eth0 | cut -d: -f1)/smp_affinity"

# Disable interrupt coalescing
sudo ethtool -C eth0 rx-usecs 0
```

### Issue: Permission denied on port binding

**Cause:** Ports <1024 require root privileges

**Solution 1:** Use port >1024:
```json
{
  "udp_port": 12345,
  "metrics_port": 9090
}
```

**Solution 2:** Grant CAP_NET_BIND_SERVICE capability:
```bash
sudo setcap 'cap_net_bind_service=+ep' ./timestamp_demo
```

### Issue: Packets not received

**Cause:** Firewall blocking UDP port

**Solution:**
```bash
# Allow UDP port
sudo ufw allow 12345/udp

# Or disable firewall (testing only)
sudo ufw disable
```

---

## Hardware Timestamping Upgrade Path

This project uses **kernel-level software timestamps** for maximum portability. For even lower latency, you can upgrade to **hardware NIC timestamps**.

### Hardware Timestamping Requirements

- **NIC**: Intel i210, Solarflare SFN8542, or Mellanox ConnectX-5+
- **Driver**: PTP-capable NIC driver (e1000e, sfc, mlx5)
- **Kernel**: Linux 3.0+ with PTP clock support

### Code Changes for Hardware Timestamping

**In [timestamp_socket.cpp:63-79](src/timestamp_socket.cpp#L63-L79):**

```cpp
void TimestampSocket::enable_timestamping() {
    // Change from software to hardware timestamps
    int flags = SOF_TIMESTAMPING_RX_HARDWARE |  // Hardware RX timestamp
                SOF_TIMESTAMPING_RAW_HARDWARE |  // Raw hardware clock
                SOF_TIMESTAMPING_OPT_CMSG;

    if (setsockopt(socket_fd_, SOL_SOCKET, SO_TIMESTAMPING, &flags, sizeof(flags)) < 0) {
        // Fall back to software timestamps
        flags = SOF_TIMESTAMPING_RX_SOFTWARE |
                SOF_TIMESTAMPING_SOFTWARE |
                SOF_TIMESTAMPING_OPT_CMSG;
        setsockopt(socket_fd_, SOL_SOCKET, SO_TIMESTAMPING, &flags, sizeof(flags));
    }
}
```

**In [timestamp_socket.cpp:128-143](src/timestamp_socket.cpp#L128-L143):**

```cpp
bool TimestampSocket::extract_kernel_timestamp(struct msghdr* msg, timespec* ts) {
    for (struct cmsghdr* cmsg = CMSG_FIRSTHDR(msg); cmsg; cmsg = CMSG_NXTHDR(msg, cmsg)) {
        if (cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_TIMESTAMPING) {
            struct scm_timestamping* tss = (struct scm_timestamping*)CMSG_DATA(cmsg);

            // Use hardware timestamp (index 2) if available
            if (tss->ts[2].tv_sec != 0 || tss->ts[2].tv_nsec != 0) {
                *ts = tss->ts[2];  // Hardware timestamp
            } else {
                *ts = tss->ts[0];  // Fall back to software timestamp
            }
            return true;
        }
    }
    return false;
}
```

**Verify hardware timestamping:**
```bash
# Check NIC capabilities
sudo ethtool -T eth0

# Should show:
# Hardware Transmit Timestamp Modes:
#   hardware-transmit
# Hardware Receive Timestamp Modes:
#   hardware-receive
```

---

## Comparison: Software vs Hardware Timestamps

| Feature | Kernel Software | Hardware NIC |
|---------|----------------|--------------|
| **Precision** | ~10-50 ns | ~1-10 ns |
| **Latency** | ~10-100 μs | ~1-10 μs |
| **CPU Overhead** | Minimal (~100 ns) | Near-zero |
| **NIC Requirement** | Any NIC | Intel i210, Solarflare, Mellanox |
| **Cost** | $0 (software only) | $100-$500 (specialized NIC) |
| **Portability** | Works everywhere | Linux 3.0+ with PTP NIC |
| **Use Case** | Development, testing, most HFT | Ultra-low-latency HFT (<1μs) |

**Recommendation:** Start with kernel software timestamps (current implementation). Upgrade to hardware timestamps only if you need <5μs latency.

---

## Testing and Validation

### 1. Unit Testing

```bash
# Build tests (TODO: add unit tests)
cd build
cmake -DBUILD_TESTS=ON ..
make tests
./run_tests
```

### 2. Load Testing

```bash
# Terminal 1: Run timestamp demo
./timestamp_demo

# Terminal 2: Generate load (1000 packets/sec)
for i in {1..1000}; do
    echo "packet $i" | nc -u -w0 localhost 12345
    sleep 0.001
done
```

### 3. Latency Verification

Compare measured latency with `tcpdump`:

```bash
# Terminal 1: Capture packets
sudo tcpdump -i lo -w capture.pcap udp port 5000

# Terminal 2: Run timestamp demo
./timestamp_demo

# Terminal 3: Send packet
echo "test" | nc -u localhost 12345

# Analyze capture
tcpdump -r capture.pcap -ttt
```

---

## Next Steps

### Integration Roadmap

1. **Project 14 (Order Gateway)**: Add timestamping to incoming FIX orders
2. **Project 15 (Market Maker)**: Track FSM state transition latencies
3. **Project 16 (Order Execution)**: Measure matching engine latency
4. **End-to-End Latency**: Track order → fill round-trip time

### Performance Optimizations

1. **CPU Pinning**: Pin timestamp_demo to dedicated CPU core
2. **NUMA Tuning**: Bind process to same NUMA node as NIC
3. **Kernel Tuning**: Disable CPU idle states, use `isolcpus`
4. **Network Tuning**: Optimize NIC ring buffer sizes, interrupt moderation

**Important Note on RT Scheduling**: Enabling RT scheduling for **all** components simultaneously can cause severe CPU contention and performance degradation. Real-world testing shows that selective RT scheduling (only for critical components) yields better results than blanket RT priority across the entire system. Consider:
- Running P17 without RT priority for monitoring (measurement overhead ~100-200ns is acceptable)
- Reserving RT priority only for P14 (Order Gateway) and data plane components
- Testing with RT disabled first to establish baseline performance

### Production Monitoring

1. **Grafana Dashboards**: Create dashboards for P50/P90/P99 latency
2. **Alerting**: Set alerts for P99 >100μs
3. **Capacity Planning**: Monitor histogram distribution over time
4. **Correlation Analysis**: Correlate latency spikes with system events

---

## References

### Linux Kernel Documentation

- [SO_TIMESTAMPING Documentation](https://www.kernel.org/doc/Documentation/networking/timestamping.txt)
- [PTP Hardware Clock Support](https://www.kernel.org/doc/html/latest/driver-api/ptp.html)
- [Network Stack Timestamping](https://lwn.net/Articles/325812/)

### Papers and Articles

- "Precision Time Protocol (PTP) in Linux" - Linux Foundation
- "Nanosecond Timestamping on Commodity Hardware" - NSDI 2018
- "Low-Latency Networking in Linux" - Red Hat Performance Blog

### Related Projects

- **DPDK** (Data Plane Development Kit): Kernel bypass for <1μs latency
- **Solarflare OpenOnload**: User-space network stack
- **XDP** (eXpress Data Path): Kernel-level packet processing

---

## License

This project is part of the FPGA Trading Systems portfolio and follows the same license as the parent repository.

---

## Contact

For questions, issues, or contributions, please open an issue in the parent repository.
