#!/bin/bash

# Project 18: Complete Trading System - Startup Script
# This script builds and starts the complete FPGA trading system

set -e

PROJECT_DIR="18-complete-system"
BUILD_DIR="${PROJECT_DIR}/build"
EXECUTABLE="trading_system_orchestrator"
CONFIG_FILE="config/system_config.json"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}FPGA Trading System - Startup${NC}"
echo -e "${GREEN}Project 18: Complete System Integration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if we're in the right directory
if [ ! -d "$PROJECT_DIR" ]; then
    echo -e "${RED}ERROR: Must be run from fpga-trading-systems root directory${NC}"
    exit 1
fi

# Check if all component projects exist
echo -e "${YELLOW}Checking component projects...${NC}"
REQUIRED_PROJECTS=("17-hardware-timestamping" "14-order-gateway" "15-market-maker" "16-order-execution")
for proj in "${REQUIRED_PROJECTS[@]}"; do
    if [ ! -d "$proj" ]; then
        echo -e "${RED}ERROR: Required project '$proj' not found${NC}"
        exit 1
    fi
    echo "  [OK] $proj"
done

# Build orchestrator if needed
if [ ! -d "$BUILD_DIR" ] || [ ! -f "${BUILD_DIR}/${EXECUTABLE}" ]; then
    echo -e "${YELLOW}Building orchestrator...${NC}"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    cmake ..
    make -j$(nproc)
    cd - > /dev/null
    echo -e "${GREEN}Build complete${NC}"
else
    echo -e "${GREEN}Orchestrator already built${NC}"
fi

# Verify executable exists
if [ ! -f "${BUILD_DIR}/${EXECUTABLE}" ]; then
    echo -e "${RED}ERROR: Failed to build ${EXECUTABLE}${NC}"
    exit 1
fi

# Check if component executables exist
echo ""
echo -e "${YELLOW}Checking component executables...${NC}"

COMPONENT_EXECS=(
    "17-hardware-timestamping/build/timestamp_demo"
    "14-order-gateway/build/order_gateway"
    "15-market-maker/build/market_maker"
    "16-order-execution/build/order_execution_engine"
)

MISSING_EXECS=()
for exec in "${COMPONENT_EXECS[@]}"; do
    if [ ! -f "$exec" ]; then
        echo -e "  ${RED}[MISSING]${NC} $exec"
        MISSING_EXECS+=("$exec")
    else
        echo -e "  ${GREEN}[OK]${NC} $exec"
    fi
done

if [ ${#MISSING_EXECS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Missing component executables. Build them first:${NC}"
    for exec in "${MISSING_EXECS[@]}"; do
        dir=$(dirname "$exec")
        echo "  cd $dir && cmake . && make"
    done
    echo ""
    echo -e "${RED}Aborting startup${NC}"
    exit 1
fi

# Cleanup stale shared memory
echo ""
echo -e "${YELLOW}Cleaning up stale shared memory...${NC}"
if [ -e "/dev/shm/order_ring_mm" ]; then
    rm -f /dev/shm/order_ring_mm
    echo "  Removed /dev/shm/order_ring_mm"
fi
if [ -e "/dev/shm/fill_ring_oe" ]; then
    rm -f /dev/shm/fill_ring_oe
    echo "  Removed /dev/shm/fill_ring_oe"
fi

# Start the orchestrator
echo ""
echo -e "${GREEN}Starting Trading System Orchestrator...${NC}"
echo ""

cd "$BUILD_DIR"
./${EXECUTABLE} "../${CONFIG_FILE}"
