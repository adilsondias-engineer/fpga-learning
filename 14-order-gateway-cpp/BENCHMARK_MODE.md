# Benchmark Mode Implementation

## Overview

Benchmark mode is a **single-threaded, parse-only** configuration that eliminates thread synchronization overhead to measure the true UDP parsing performance.

## Problem Statement

After CPU profiling with `perf`, analysis showed that **21% of CPU time** was spent on pthread synchronization (mutex + condition variable), not on BBO parsing:

```
CPU Time Breakdown (before benchmark mode):
    21%   pthread synchronization (mutex + cond_var)
    70%   Kernel (scheduling, futex, context switches)
     0.68% BBO parsing (actual work!)
     8%   Boost.Asio + other
```

The multi-threaded architecture (UDP thread → queue → publish thread) was the bottleneck, not the parsing logic itself.

## Solution: Benchmark Mode

Benchmark mode bypasses the multi-threaded architecture:

**Normal Mode:**
```
UDP Thread → Queue (mutex/cv) → Publish Thread → Distribution
```

**Benchmark Mode:**
```
UDP Callback → Parse → Done (no queue, no threads, no distribution)
```

## Implementation

### 1. Configuration Flag

Added `benchmark_mode` flag to `OrderGateway::Config`:

```cpp
// Benchmark mode (single-threaded, no queue, parse-only)
bool benchmark_mode = false;
```

### 2. Thread Creation Skip

Modified `OrderGateway::start()` to skip thread creation in benchmark mode:

```cpp
if (config_.benchmark_mode)
{
    std::cout << "[BENCHMARK] Single-threaded mode enabled (no queue overhead)" << std::endl;
    // No threads needed - processing happens in UDP callback
}
else
{
    udp_thread_ = std::thread(&OrderGateway::udpThreadFunc, this);
    publish_thread_ = std::thread(&OrderGateway::publishThreadFunc, this);
}
```

### 3. Graceful Shutdown

Modified `OrderGateway::stop()` to handle benchmark mode:

```cpp
if (!config_.benchmark_mode)
{
    // Notify threads to wake up
    queue_cv_.notify_all();
}
// ... stop listener ...
if (!config_.benchmark_mode)
{
    // Wait for threads to finish
    if (udp_thread_.joinable()) { udp_thread_.join(); }
    if (publish_thread_.joinable()) { publish_thread_.join(); }
}
```

### 4. CLI Flag

Added `--benchmark` flag to command-line interface:

```bash
./order_gateway 0.0.0.0 5000 --benchmark --quiet --disable-tcp --disable-mqtt --disable-kafka --disable-logger
```

## Usage

### Test Script

```bash
cd /work/projects/fpga-trading-systems/14-order-gateway-cpp/build
../test_performance.sh
```

The script automatically runs with:
- `--benchmark` - Single-threaded mode
- `--quiet` - No console output
- `--enable-rt` - Real-time scheduling
- `--disable-tcp` - No TCP distribution
- `--disable-mqtt` - No MQTT distribution
- `--disable-kafka` - No Kafka distribution
- `--disable-logger` - No CSV logging

### Manual Run

```bash
# Terminal 1: Start ITCH feed
python3 /work/projects/fpga-trading-systems/scripts/itch_live_feed.py

# Terminal 2: Run gateway in benchmark mode
cd /work/projects/fpga-trading-systems/14-order-gateway-cpp/build
sudo taskset -c 2-5 ./order_gateway 0.0.0.0 5000 \
  --enable-rt \
  --quiet \
  --benchmark \
  --disable-tcp \
  --disable-mqtt \
  --disable-kafka \
  --disable-logger
```

Press Ctrl+C after 30+ seconds to collect latency stats.

## Expected Performance

### Before (Multi-threaded with all optimizations)
- **Latency:** ~0.30-0.33 μs average
- **Bottleneck:** pthread mutex/condition variable (21% CPU)

### After (Benchmark mode)
- **Latency:** ~0.10-0.15 μs average (expected)
- **CPU usage:** BBO parsing only (no thread overhead)

## What Gets Measured

In benchmark mode, the latency measurement captures:
1. **UDP receive** - `socket.async_receive_from()`
2. **BBO parsing** - `BBOParser::parseBBOData()`
3. **Queue push** - `bbo_queue_.push()` (internal to UDPListener, minimal overhead)

What is **eliminated**:
- Thread synchronization (mutex lock/unlock)
- Condition variable signaling
- Context switches between threads
- Kernel futex operations
- Queue operations between threads

## Files Modified

1. **[order_gateway.h](include/order_gateway.h:70)** - Added `benchmark_mode` flag
2. **[order_gateway.cpp](src/order_gateway.cpp:92-103)** - Skip thread creation
3. **[order_gateway.cpp](src/order_gateway.cpp:167-190)** - Skip thread joins
4. **[main.cpp](src/main.cpp:88)** - Added `benchmark_mode` variable
5. **[main.cpp](src/main.cpp:160-163)** - CLI parsing for `--benchmark`
6. **[main.cpp](src/main.cpp:192)** - Config assignment
7. **[test_performance.sh](test_performance.sh:29)** - Added `--benchmark` flag
8. **[profile_performance.sh](profile_performance.sh:25)** - Added `--benchmark` flag

## Verification

To verify benchmark mode is working:

```bash
# Run the gateway and check output
./order_gateway 0.0.0.0 5000 --benchmark

# Expected output:
# [BENCHMARK] Single-threaded mode enabled (no queue overhead)
# Order Gateway started
# ...
```

## CPU Profiling in Benchmark Mode

To profile CPU usage in benchmark mode:

```bash
cd /work/projects/fpga-trading-systems/14-order-gateway-cpp
./profile_performance.sh
```

Expected hot functions:
- **BBOParser::parseBBOData** - Should be #1 now (30-40% CPU)
- **Kernel UDP receive** - 15-25% CPU
- **Boost.Asio** - 10-15% CPU
- **pthread/mutex** - **Should be 0%** (eliminated)

## Notes

- Benchmark mode is **single-threaded** - the UDPListener runs in its own thread via `io_context`, but there are no worker threads
- The UDPListener still uses an internal queue (`bbo_queue_`), but it's never read from in benchmark mode
- This is intentional - measurement captures parse latency without modifying the UDPListener architecture
- In a production deployment, you would use normal mode with all protocols enabled

## Next Steps

After measuring benchmark mode performance:

1. Compare latency: benchmark vs normal mode
2. If benchmark mode is significantly faster (>2x), consider optimizing the queue implementation
3. If benchmark mode is similar, the parsing itself may need optimization
4. Document final performance numbers in [PROJECT_14_SUMMARY.md](../PROJECT_14_SUMMARY.md)
