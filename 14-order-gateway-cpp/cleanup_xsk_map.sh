#!/bin/bash
# Helper script to clean up stale XSK map entries
# Usage: ./cleanup_xsk_map.sh [interface] [queue_id]
#   If queue_id not specified, cleans all queues 0-7

IFACE=${1:-eno2}
QUEUE_ID=${2:-""}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"

# Try to use the C cleanup tool if available (more reliable)
if [ -f "${BUILD_DIR}/cleanup_xsk_map" ]; then
    echo "Using C cleanup tool..."
    if [ -z "$QUEUE_ID" ]; then
        sudo "${BUILD_DIR}/cleanup_xsk_map" "$IFACE"
    else
        sudo "${BUILD_DIR}/cleanup_xsk_map" "$IFACE" "$QUEUE_ID"
    fi
    exit $?
fi

# Fallback to bpftool (may not work for XSK maps)
echo "C cleanup tool not found, using bpftool (may not work for XSK maps)"
echo "Cleaning up XSK map entries for interface $IFACE"

if [ -n "$QUEUE_ID" ]; then
    echo "Target queue: $QUEUE_ID"
else
    echo "Cleaning all queues 0-7"
fi

# Find the xsks_map
MAP_ID=$(sudo bpftool map list 2>/dev/null | grep -i xsk | head -1 | awk '{print $1}')

if [ -z "$MAP_ID" ]; then
    echo "No XSK map found. XDP program may not be loaded."
    echo "Try building the cleanup tool: cd build && make cleanup_xsk_map"
    exit 1
fi

echo "Found XSK map ID: $MAP_ID"

if [ -n "$QUEUE_ID" ]; then
    # Delete the entry for the specified queue
    sudo bpftool map delete id $MAP_ID key $QUEUE_ID 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "Successfully deleted entry for queue $QUEUE_ID"
    else
        echo "Failed to delete entry for queue $QUEUE_ID (may not exist or bpftool doesn't support XSK maps)"
    fi
    
    # Also try to delete queue 0 (commonly has stale entries)
    if [ "$QUEUE_ID" != "0" ]; then
        sudo bpftool map delete id $MAP_ID key 0 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "Also deleted entry for queue 0"
        fi
    fi
else
    # Clean all queues 0-7
    for q in {0..7}; do
        sudo bpftool map delete id $MAP_ID key $q 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "Deleted entry for queue $q"
        fi
    done
fi

echo ""
echo "Note: bpftool may not work for XSK maps. For reliable cleanup, build the C tool:"
echo "  cd build && make cleanup_xsk_map"
echo "Then run this script again."

