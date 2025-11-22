#!/bin/bash
# CPU profiling script for Project 14 using perf

cd /work/projects/fpga-trading-systems/14-order-gateway-cpp/build

echo "==================================================================="
echo "Project 14 - CPU Profiling with perf"
echo "==================================================================="
echo ""
echo "This will run the gateway for 90 seconds and collect CPU samples"
echo "Make sure to start the ITCH feed in another terminal first!"
echo ""
echo "Starting profiling in 5 seconds..."
sleep 5

# Run perf record to capture CPU samples
# -g: Enable call-graph (stack trace) recording
# -F 999: Sample at 999 Hz (good balance)
# --call-graph dwarf: Use DWARF for better stack traces
# -e cycles: Sample CPU cycles
sudo perf record -g -F 999 --call-graph dwarf -e cycles \
    taskset -c 2-5 ./order_gateway 0.0.0.0 5000 \
    --enable-rt \
    --quiet \
    --benchmark \
    --disable-tcp \
    --disable-mqtt \
    --disable-kafka \
    --disable-logger &

PERF_PID=$!

echo ""
echo "Profiling started (PID: $PERF_PID)"
echo "Recording for 90 seconds..."
echo ""

# Wait 90 seconds
sleep 90

# Stop the gateway
echo "Stopping gateway..."
sudo kill -INT $PERF_PID
sleep 2

echo ""
echo "==================================================================="
echo "Generating performance report..."
echo "==================================================================="
echo ""

# Generate text report
sudo perf report --stdio > perf_report.txt

# Show top functions
echo "Top 20 CPU-consuming functions:"
echo "-------------------------------------------------------------------"
sudo perf report --stdio --sort comm,dso,symbol --percent-limit 0.5 | head -40

echo ""
echo "==================================================================="
echo "Detailed report saved to: perf_report.txt"
echo "Raw data saved to: perf.data"
echo ""
echo "To view interactive report:"
echo "  sudo perf report"
echo ""
echo "To view flamegraph (if installed):"
echo "  sudo perf script | stackcollapse-perf.pl | flamegraph.pl > flamegraph.svg"
echo "==================================================================="
