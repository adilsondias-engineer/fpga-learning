#!/usr/bin/env python3
"""
MII Ethernet Test Script
Sends test frames to Arty A7 via Ethernet
Tests frame reception and LED counting
"""

from scapy.all import Ether, IP, ICMP, sendp, get_if_list
import sys
import time

# Arty A7 MAC address (from design)
ARTY_MAC = "00:0a:35:02:af:9a"

def list_interfaces():
    """List available network interfaces"""
    print("\n=== Available Network Interfaces ===")
    interfaces = get_if_list()
    for i, iface in enumerate(interfaces):
        print(f"{i}: {iface}")
    print()

def send_test_frames(interface, count=10):
    """Send test Ethernet frames to Arty"""
    
    print(f"\n=== Sending {count} test frames to {ARTY_MAC} ===")
    print(f"Interface: {interface}")
    print(f"Watch the LEDs on your Arty A7 board...")
    print()
    
    for i in range(count):
        # Create simple Ethernet frame with ICMP ping
        frame = Ether(dst=ARTY_MAC) / IP(dst="192.168.1.100") / ICMP(seq=i)
        
        # Send frame
        sendp(frame, iface=interface, verbose=False)
        print(f"Sent frame {i+1}/{count}")
        time.sleep(0.5)  # 500ms between frames
    
    print("\n✓ All frames sent!")
    print("\nExpected behavior:")
    print("- LED0-3 should increment in binary (0001, 0010, 0011, ...)")
    print("- LED0 (green) should blink briefly on each frame")
    print("- LED1 (blue) should be ON (PHY ready)")
    print()

def main():
    print("="*60)
    print("MII Ethernet Frame Sender - Arty A7 Test")
    print("="*60)
    
    # List interfaces
    list_interfaces()
    
    # Get interface from user
    if len(sys.argv) > 1:
        interface = sys.argv[1]
    else:
        interface = input("Enter interface name (or number): ").strip()
        
        # Allow user to enter interface by number
        interfaces = get_if_list()
        try:
            idx = int(interface)
            if 0 <= idx < len(interfaces):
                interface = interfaces[idx]
            else:
                print(f"Error: Invalid interface number")
                return
        except ValueError:
            pass  # User entered interface name, not number
    
    # Get frame count
    if len(sys.argv) > 2:
        try:
            count = int(sys.argv[2])
        except ValueError:
            count = 10
    else:
        count = 10
    
    # Verify interface exists
    if interface not in get_if_list():
        print(f"Error: Interface '{interface}' not found")
        list_interfaces()
        return
    
    # Send frames
    try:
        send_test_frames(interface, count)
    except PermissionError:
        print("\n❌ Permission denied!")
        print("Run with sudo: sudo python3 test_mii_ethernet.py")
        return
    except Exception as e:
        print(f"\n❌ Error: {e}")
        return

if __name__ == "__main__":
    main()