#!/usr/bin/env python3
"""
Simple Ethernet Frame Sender for Project 6 Testing

Sends raw Ethernet frames directly to FPGA MAC address.
No IP/ARP needed - tests pure MAC layer reception.

Requirements:
  pip install scapy

Usage:
  sudo python3 simple_test.py
"""

import sys

# Check for Scapy
try:
    from scapy.all import Ether, sendp, get_if_list
except ImportError:
    print("\n❌ ERROR: Scapy not installed")
    print("\nInstall with:")
    print("  pip3 install scapy")
    print("  or")
    print("  pip install scapy")
    sys.exit(1)

# Check for root privileges
import os
if os.name != 'nt' and os.geteuid() != 0:
    print("\n❌ ERROR: This script requires root privileges")
    print("\nRun with sudo:")
    print(f"  sudo python3 {sys.argv[0]}")
    sys.exit(1)

# Configuration
FPGA_MAC = "00:0a:35:02:af:9a"  # FPGA MAC address
MY_MAC = "80:3f:5d:fb:17:63"    # Your USB Ethernet MAC address (source)
PC_INTERFACE_MAC = "80:3f:5d:fb:17:63"  # USB Ethernet adapter MAC (to find interface) "E8:9C:25:7A:5E:0A"

print("\n" + "="*70)
print("Project 6: Simple Ethernet Frame Test")
print("="*70)

# Function to get interface MAC address
def get_if_hwaddr_safe(iface):
    """Get MAC address of interface, return None if fails"""
    try:
        from scapy.arch import get_if_hwaddr
        return get_if_hwaddr(iface)
    except:
        return None

# List interfaces with MAC addresses
print("\n📡 Available network interfaces:")
interfaces = get_if_list()
interface_map = {}
for i, iface in enumerate(interfaces):
    mac = get_if_hwaddr_safe(iface)
    mac_str = f" (MAC: {mac})" if mac else ""
    print(f"  {i+1}. {iface}{mac_str}")
    interface_map[i] = (iface, mac)

# Try to auto-detect USB Ethernet by MAC
interface = None
for i, (iface, mac) in interface_map.items():
    if mac and mac.lower() == PC_INTERFACE_MAC.lower().replace('-', ':'):
        interface = iface
        print(f"\n✓ Auto-detected USB Ethernet: {iface} (MAC: {mac})")
        break

if interface is None:
    # Manual selection
    print(f"\n⚠ Could not auto-detect USB Ethernet with MAC {PC_INTERFACE_MAC}")
    print("   Please select manually:")
    print("\n")
if interface is None:
    # Manual selection
    print(f"\n⚠ Could not auto-detect USB Ethernet with MAC {PC_INTERFACE_MAC}")
    print("   Please select manually:")
    print("\n")
    while True:
        try:
            choice = input("Enter interface number or name: ").strip()
            # Try as number first
            try:
                idx = int(choice) - 1
                if 0 <= idx < len(interfaces):
                    interface = interfaces[idx]
                    break
            except ValueError:
                pass
            # Try as name
            if choice in interfaces:
                interface = choice
                break
            print("❌ Invalid selection. Try again.")
        except KeyboardInterrupt:
            print("\n\nAborted.")
            sys.exit(0)
else:
    # Confirm auto-detected interface
    confirm = input("\nUse this interface? (y/n): ").strip().lower()
    if confirm != 'y' and confirm != '':
        print("\nManual selection:")
        while True:
            try:
                choice = input("Enter interface number or name: ").strip()
                try:
                    idx = int(choice) - 1
                    if 0 <= idx < len(interfaces):
                        interface = interfaces[idx]
                        break
                except ValueError:
                    pass
                if choice in interfaces:
                    interface = choice
                    break
                print("❌ Invalid selection. Try again.")
            except KeyboardInterrupt:
                print("\n\nAborted.")
                sys.exit(0)

print(f"\n✓ Using interface: {interface}")

# Menu
print("\n" + "="*70)
print("Test Menu")
print("="*70)
print("\n1. Send 1 frame   (test basic reception)")
print("2. Send 10 frames  (count to 10)")
print("3. Send 100 frames (stress test)")
print("4. Continuous      (Ctrl+C to stop)")
print("0. Exit")

while True:
    print("\n")
    try:
        choice = input("Select test (0-4): ").strip()
        
        if choice == '0':
            print("\nExiting...")
            break
            
        elif choice == '1':
            count = 1
        elif choice == '2':
            count = 10
        elif choice == '3':
            count = 100
        elif choice == '4':
            count = None  # Continuous
        else:
            print("❌ Invalid choice")
            continue
        
        # Create Ethernet frame
        frame = Ether(dst=FPGA_MAC, src=MY_MAC, type=0x0800) / b"Hello FPGA!"
        
        if count is None:
            # Continuous mode
            print("\n📡 Sending frames continuously...")
            print("   Press Ctrl+C to stop")
            print()
            sent = 0
            try:
                while True:
                    sendp(frame, iface=interface, verbose=False)
                    sent += 1
                    if sent % 10 == 0:
                        print(f"\r   Sent: {sent} frames", end='', flush=True)
            except KeyboardInterrupt:
                print(f"\n\n✓ Sent {sent} frames total")
        else:
            # Fixed count
            print(f"\n📡 Sending {count} frame(s) to {FPGA_MAC}...")
            sendp(frame, iface=interface, count=count, verbose=False)
            print(f"✓ Sent {count} frame(s)")
            print(f"\n💡 Expected LED count: {count % 16} (displays lower 4 bits)")
            
    except KeyboardInterrupt:
        print("\n\nReturning to menu...")
        continue
    except Exception as e:
        print(f"\n❌ Error: {e}")
        continue

print("\nDone! 🎉")