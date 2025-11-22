#!/bin/bash
# Quick benchmark runner - sets capabilities and runs with correct flags
# This is a simplified version without perf profiling

cd /work/projects/fpga-trading-systems/14-order-gateway-cpp/build

echo "==================================================================="
echo "Project 14 - Benchmark Mode Test"
echo "==================================================================="
echo ""

# Set capabilities on the binary (needed after rebuild)
echo "Setting CAP_SYS_NICE capability..."
sudo setcap cap_sys_nice=eip ./order_gateway

# Verify capabilities
CAPS=$(getcap ./order_gateway)
if [ -z "$CAPS" ]; then
    echo "WARNING: Failed to set capabilities, RT optimizations may not work"
    echo "Continuing anyway..."
else
    echo "Capabilities set: $CAPS"
fi

echo ""
echo "Configuration:"
echo "  - Benchmark mode: ENABLED (single-threaded, parse-only)"
echo "  - Console output: DISABLED (--quiet)"
echo "  - All distribution: DISABLED"
echo "  - RT scheduling: ENABLED"
echo "  - CPU cores: 2-5 (isolated)"
echo ""
echo "Will run for 30 seconds then auto-stop"
echo ""
echo "==================================================================="
echo ""
# Run without sudo since we have capabilities, with timeout
timeout 30 taskset -c 2-5 ./order_gateway 0.0.0.0 5000 \
  --enable-rt \
  --quiet \
  --benchmark \
  --disable-tcp \
  --disable-mqtt \
  --disable-kafka \
  --disable-logger

echo ""
echo "==================================================================="
echo "Benchmark complete - check project14_latency.csv for results"
echo "==================================================================="
