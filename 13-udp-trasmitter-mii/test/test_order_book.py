#!/usr/bin/env python3
"""
Order Book Test Script - Project 8
Tests hardware order book functionality by sending ITCH messages

Test Scenarios:
1. Build Order Book - Add orders at different prices
2. Order Execution - Reduce shares via Execute messages
3. Order Cancellation - Reduce shares via Cancel messages
4. Order Deletion - Remove orders completely
5. Market Depth - Multiple orders at same price level
6. Order Replace - Modify existing orders
"""

import sys
import os
import time
import argparse
import struct
import random

# Import from send_itch_packets in same directory
from send_itch_packets import ITCHMessageGenerator, send_udp_packet

# Check for Scapy
try:
    from scapy.all import Ether, IP, UDP, Raw, sendp, get_if_list
except ImportError:
    print("\nERROR: ERROR: Scapy not installed")
    print("\nInstall with:")
    print("  pip3 install scapy")
    print("  or")
    print("  pip install scapy")
    sys.exit(1)

# Check for root privileges
if os.name != 'nt':  # Unix/Linux/Mac
    if os.geteuid() != 0:
        print("\nERROR: ERROR: This script requires root privileges")
        print("\nRun with sudo:")
        print(f"  sudo python3 {sys.argv[0]}")
        sys.exit(1)
else:  # Windows
    print("\nNote: Note: On Windows, you may need Administrator privileges")
    print("   If you get errors, run Command Prompt as Administrator\n")

# Configuration
PC_INTERFACE_MAC = "E8-9C-25-7A-5E-0A" # "80:3f:5d:fb:17:63"   # Your USB Ethernet MAC (to find interface)
FPGA_MAC = "00:18:3E:04:5D:E7"           # FPGA MAC address

def get_if_hwaddr_safe(iface):
    """Get MAC address of interface, return None if fails"""
    try:
        from scapy.arch import get_if_hwaddr
        return get_if_hwaddr(iface)
    except:
        return None

def find_interface():
    """
    Find USB Ethernet interface by MAC address
    Returns (interface_name, mac_address) or (None, None)
    """
    interfaces = get_if_list()
    interface_map = {}

    #print("\n📡 Available network interfaces:")
    for i, iface in enumerate(interfaces):
        mac = get_if_hwaddr_safe(iface)
     #  mac_str = f" (MAC: {mac})" if mac else ""
     #  marker = "  ← Your USB" if mac and mac.lower() == PC_INTERFACE_MAC.lower().replace('-', ':') else ""
     #   print(f"  {i+1}. {iface}{mac_str}{marker}")
        interface_map[i] = (iface, mac)

    # Try to auto-detect USB Ethernet by MAC
    # for i, (iface, mac) in interface_map.items():
    #     if mac and mac.lower() == PC_INTERFACE_MAC.lower().replace('-', ':'):
    #         print(f"\n Auto-detected USB Ethernet: {iface} (MAC: {mac})")
    #         confirm = input("Use this interface? (y/n): ").strip().lower()
    #         if confirm == 'y':
    #             return iface, mac

    # # Manual selection if auto-detect fails
    # print("\n⚠ Could not auto-detect USB Ethernet interface")
    # print(f"   Looking for MAC: {PC_INTERFACE_MAC}")
    #print("\nPlease select interface manually:")

    while True:
        try:
            choice = 8 #input(f"Enter number (1-{len(interfaces)}): ").strip()
            idx = int(choice) - 1
            if 0 <= idx < len(interfaces):
                iface, mac = interface_map[idx]
     #           print(f"Selected: {iface} (MAC: {mac})")
                return iface, mac
            else:
                print(f"Invalid choice. Enter 1-{len(interfaces)}")
        except ValueError:
            print("Invalid input. Enter a number.")
        except KeyboardInterrupt:
            print("\n\nCancelled by user")
            sys.exit(0)

def test_build_order_book(iface, target_ip, target_port):
    """Test 1: Build Order Book"""
    gen = ITCHMessageGenerator()

    print("=" * 70)
    print("TEST 1: BUILD ORDER BOOK")
    print("=" * 70)
    print("\nSending Add Order messages for AAPL...")
    time.sleep(1)

    # Add Bid orders
    bids = [
        (150.00, 100), (149.75, 200), (150.25, 150), (149.50, 300)
    ]

    print("\n--- Adding BID orders ---")
    for i, (price, shares) in enumerate(bids, 1):
        print(f"{i}. Add Bid: ${price:.2f}, {shares} shares")
        msg = gen.add_order('AAPL    ', 'B', shares, price)
        send_udp_packet(iface, target_ip, target_port, msg)
        time.sleep(0.5)

    # Add Ask orders
    asks = [
        (151.00, 100), (151.50, 200), (150.75, 150), (152.00, 300)
    ]

    print("\n--- Adding ASK orders ---")
    for i, (price, shares) in enumerate(asks, 1):
        print(f"{i}. Add Ask: ${price:.2f}, {shares} shares")
        msg = gen.add_order('AAPL    ', 'S', shares, price)
        send_udp_packet(iface, target_ip, target_port, msg)
        time.sleep(0.5)

    print("\nEXPECTED BBO: Bid $150.25, Ask $150.75, Spread $0.50")


def test_order_execution(iface, target_ip, target_port):
    """Test 2: Order Execution"""
    gen = ITCHMessageGenerator()

    print("\n" + "=" * 70)
    print("TEST 2: ORDER EXECUTION")
    print("=" * 70)
    time.sleep(1)

    print("1. Execute 50 shares from order 1000003")
    msg = gen.order_executed(1000003, 50)
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)

    print("2. Execute 100 shares from order 1000003 (should remove order)")
    msg = gen.order_executed(1000003, 100)
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)


def test_order_cancellation(iface, target_ip, target_port):
    """Test 3: Order Cancellation"""
    gen = ITCHMessageGenerator()

    print("\n" + "=" * 70)
    print("TEST 3: ORDER CANCELLATION")
    print("=" * 70)
    time.sleep(1)

    print("1. Cancel 50 shares from order 1000001")
    msg = gen.order_cancel(1000001, 50)
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)


def test_order_deletion(iface, target_ip, target_port):
    """Test 4: Order Deletion"""
    gen = ITCHMessageGenerator()

    print("\n" + "=" * 70)
    print("TEST 4: ORDER DELETION")
    print("=" * 70)
    time.sleep(1)

    print("1. Delete order 1000002")
    msg = gen.order_delete(1000002)
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)


def test_multi_symbol(iface, target_ip, target_port):
    """Test 5: Multi-Symbol Order Book"""
    gen = ITCHMessageGenerator()

    print("=" * 70)
    print("TEST 5: MULTI-SYMBOL ORDER BOOK")
    print("=" * 70)
    print("\nTesting all 8 symbols: AAPL, TSLA, SPY, QQQ, GOOGL, MSFT, AMZN, NVDA")
    time.sleep(1)

    # Symbol list with realistic prices
    symbols = [
        ('AAPL    ', 150.00, 150.50),  # Apple
        ('TSLA    ', 250.00, 251.00),  # Tesla
        ('SPY     ', 445.00, 445.10),  # S&P 500 ETF
        ('QQQ     ', 380.00, 380.25),  # NASDAQ ETF
        ('GOOGL   ', 140.00, 140.75),  # Google
        ('MSFT    ', 375.00, 376.00),  # Microsoft
        ('AMZN    ', 145.00, 145.50),  # Amazon
        ('NVDA    ', 495.00, 496.00),  # NVIDIA
    ]

    print("\n--- Adding orders for all symbols ---")
    for symbol, bid_price, ask_price in symbols:
        print(f"\n{symbol.strip()}: Bid ${bid_price:.2f}, Ask ${ask_price:.2f}")

        # Add one bid order
        msg = gen.add_order(symbol, 'B', 100, bid_price)
        send_udp_packet(iface, target_ip, target_port, msg)
        time.sleep(0.3)

        # Add one ask order
        msg = gen.add_order(symbol, 'S', 100, ask_price)
        send_udp_packet(iface, target_ip, target_port, msg)
        time.sleep(0.3)

    print("\n" + "=" * 70)
    print("Multi-symbol test complete!")
    print("Check UART output - should see BBO updates for all 8 symbols")
    print("Round-robin arbiter cycles through symbols every ~40µs")
    print("=" * 70)


def test_all(iface, target_ip, target_port):
    """Run all tests"""
    print("\nHARDWARE ORDER BOOK TEST - AAPL")
    print("=" * 70)
    input("Press Enter to start...")

    test_build_order_book(iface, target_ip, target_port)
    input("\nPress Enter for Test 2...")

    test_order_execution(iface, target_ip, target_port)
    input("\nPress Enter for Test 3...")

    test_order_cancellation(iface, target_ip, target_port)
    input("\nPress Enter for Test 4...")

    test_order_deletion(iface, target_ip, target_port)

    print("\n" + "=" * 70)
    print("ALL TESTS COMPLETE!")
    print("Monitor BBO signals in ILA:")
    print("  - ob_bbo.bid_price / ob_bbo.ask_price")
    print("  - ob_bbo_update strobe")
    print("=" * 70)


def main():
    parser = argparse.ArgumentParser(description='Order Book Test - Project 8')
    parser.add_argument('--target', default='192.168.0.212', help='FPGA IP')
    parser.add_argument('--port', type=int, default=12345, help='UDP port')
    parser.add_argument('--test', choices=['all', 'build', 'execute', 'cancel', 'delete', 'multi'],
                       default='all', help='Test to run')
    args = parser.parse_args()

    print("Finding USB Ethernet interface...")
    iface, mac = find_interface()
    if not iface:
        print("ERROR: USB Ethernet adapter not found!")
        return 1

    print(f"Interface: {iface}, Target: {args.target}:{args.port}\n")

    if args.test == 'all':
        test_all(iface, args.target, args.port)
    elif args.test == 'build':
        test_build_order_book(iface, args.target, args.port)
    elif args.test == 'execute':
        test_order_execution(iface, args.target, args.port)
    elif args.test == 'cancel':
        test_order_cancellation(iface, args.target, args.port)
    elif args.test == 'delete':
        test_order_deletion(iface, args.target, args.port)
    elif args.test == 'multi':
        test_multi_symbol(iface, args.target, args.port)

    return 0


if __name__ == '__main__':
    sys.exit(main())