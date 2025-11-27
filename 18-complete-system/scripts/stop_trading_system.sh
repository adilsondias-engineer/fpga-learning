#!/bin/bash

# Project 18: Complete Trading System - Shutdown Script
# This script stops all trading system components

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}FPGA Trading System - Shutdown${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Find orchestrator process
ORCHESTRATOR_PID=$(pgrep -f "trading_system_orchestrator")

if [ -z "$ORCHESTRATOR_PID" ]; then
    echo -e "${YELLOW}Orchestrator not running${NC}"
else
    echo -e "${YELLOW}Stopping orchestrator (PID: $ORCHESTRATOR_PID)...${NC}"
    kill -TERM $ORCHESTRATOR_PID

    # Wait for graceful shutdown
    for i in {1..10}; do
        if ! kill -0 $ORCHESTRATOR_PID 2>/dev/null; then
            echo -e "${GREEN}Orchestrator stopped gracefully${NC}"
            break
        fi
        sleep 1
    done

    # Force kill if still running
    if kill -0 $ORCHESTRATOR_PID 2>/dev/null; then
        echo -e "${RED}Orchestrator didn't stop gracefully, sending SIGKILL${NC}"
        kill -KILL $ORCHESTRATOR_PID
    fi
fi

# Stop individual components if still running
echo ""
echo -e "${YELLOW}Checking for remaining component processes...${NC}"

COMPONENT_NAMES=("order_gateway" "market_maker" "order_execution_engine")

for comp in "${COMPONENT_NAMES[@]}"; do
    COMP_PID=$(pgrep -f "$comp")
    if [ -n "$COMP_PID" ]; then
        echo -e "  Stopping $comp (PID: $COMP_PID)..."
        kill -TERM $COMP_PID 2>/dev/null || true
        sleep 1
        kill -KILL $COMP_PID 2>/dev/null || true
    fi
done

# Cleanup shared memory
echo ""
echo -e "${YELLOW}Cleaning up shared memory...${NC}"

if [ -e "/dev/shm/order_ring_mm" ]; then
    rm -f /dev/shm/order_ring_mm
    echo "  Removed /dev/shm/order_ring_mm"
fi

if [ -e "/dev/shm/fill_ring_oe" ]; then
    rm -f /dev/shm/fill_ring_oe
    echo "  Removed /dev/shm/fill_ring_oe"
fi

echo ""
echo -e "${GREEN}Trading system stopped${NC}"
