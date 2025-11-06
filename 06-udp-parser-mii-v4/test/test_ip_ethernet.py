#!/usr/bin/env python3
"""
IP Parser Hardware Test Script
Sends various IP packets and verifies FPGA behavior
Automatically detects USB Ethernet interface by MAC address

Requirements:
  pip install scapy

Usage:
  sudo python3 test_ip_ethernet.py           # Auto-detect interface
  sudo python3 test_ip_ethernet.py --test 1  # Run specific test
"""

import sys
import time
import argparse

# Check for Scapy
try:
    from scapy.all import Ether, IP, UDP, TCP, ICMP, Raw, sendp, get_if_list
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
elif os.name == 'nt':
    print("\n📝 Note: On Windows, you may need Administrator privileges")
    print("   If you get errors, run Command Prompt as Administrator\n")

# Configuration
FPGA_MAC = "00:0a:35:02:af:9a"          # FPGA MAC address
FPGA_IP = "192.168.1.100"                # FPGA IP address (not configured, but sent in packets)
SRC_IP = "192.168.1.10"                  # Source IP for test packets
PC_INTERFACE_MAC = "80:3f:5d:fb:17:63"   # Your USB Ethernet MAC (to find interface)

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

    print("\n📡 Available network interfaces:")
    for i, iface in enumerate(interfaces):
        mac = get_if_hwaddr_safe(iface)
        mac_str = f" (MAC: {mac})" if mac else ""
        print(f"  {i+1}. {iface}{mac_str}")
        interface_map[i] = (iface, mac)

    # Try to auto-detect USB Ethernet by MAC
    for i, (iface, mac) in interface_map.items():
        if mac and mac.lower() == PC_INTERFACE_MAC.lower().replace('-', ':'):
            print(f"\n✓ Auto-detected USB Ethernet: {iface} (MAC: {mac})")
            confirm = input("Use this interface? (y/n): ").strip().lower()
            if confirm == 'y' or confirm == '':
                return iface, mac

    # Manual selection
    print(f"\n⚠ Could not auto-detect USB Ethernet with MAC {PC_INTERFACE_MAC}")
    print("   Please select manually:\n")

    while True:
        try:
            choice = input("Enter interface number or name: ").strip()
            # Try as number first
            try:
                idx = int(choice) - 1
                if 0 <= idx < len(interfaces):
                    iface = interfaces[idx]
                    mac = get_if_hwaddr_safe(iface)
                    return iface, mac
            except ValueError:
                pass
            # Try as name
            if choice in interfaces:
                mac = get_if_hwaddr_safe(choice)
                return choice, mac
            print("❌ Invalid selection. Try again.")
        except KeyboardInterrupt:
            print("\n\nAborted.")
            sys.exit(0)

def send_test_packet(iface, description, packet):
    """Send a test packet and display info"""
    print(f"\n{'='*60}")
    print(f"Test: {description}")
    print(f"{'='*60}")
    print(f"Packet summary: {packet.summary()}")

    # Build packet to calculate auto-fields (length, checksum)
    # This forces Scapy to compute all checksums and lengths
    built_packet = packet.__class__(bytes(packet))

    if IP in built_packet:
        ip_layer = built_packet[IP]
        print(f"IP: {ip_layer.src} -> {ip_layer.dst}")
        print(f"Protocol: {ip_layer.proto} ({ip_layer.sprintf('%IP.proto%')})")

        # Handle length field
        if ip_layer.len is not None:
            print(f"Total Length: {ip_layer.len}")
        else:
            print(f"Total Length: auto")

        # Handle checksum field
        if ip_layer.chksum is not None:
            print(f"Checksum: 0x{ip_layer.chksum:04X}")
        else:
            print(f"Checksum: auto")

    print(f"\nSending packet on {iface}...")
    try:
        sendp(built_packet, iface=iface, verbose=False)
        print("✓ Sent successfully!")
    except Exception as e:
        print(f"❌ Error sending packet: {e}")
        return False

    time.sleep(0.5)
    return True

def test_valid_udp(iface):
    """Test 1: Valid UDP packet"""
    pkt = Ether(dst=FPGA_MAC) / IP(src=SRC_IP, dst=FPGA_IP) / UDP(sport=12345, dport=80) / Raw(b"Hello FPGA")
    if send_test_packet(iface, "Valid UDP Packet", pkt):
        print("\nExpected behavior:")
        print("  - LED increments")
        print("  - Protocol = 0x11 (UDP)")
        print("  - In Mode 2: LED shows 0x1 (0x11 & 0xF)")

def test_valid_tcp(iface):
    """Test 2: Valid TCP packet"""
    pkt = Ether(dst=FPGA_MAC) / IP(src=SRC_IP, dst=FPGA_IP) / TCP(sport=443, dport=80)
    if send_test_packet(iface, "Valid TCP Packet", pkt):
        print("\nExpected behavior:")
        print("  - LED increments")
        print("  - Protocol = 0x06 (TCP)")
        print("  - In Mode 2: LED shows 0x6")

def test_valid_icmp(iface):
    """Test 3: Valid ICMP packet (ping)"""
    pkt = Ether(dst=FPGA_MAC) / IP(src=SRC_IP, dst=FPGA_IP) / ICMP()
    if send_test_packet(iface, "Valid ICMP Packet (Ping)", pkt):
        print("\nExpected behavior:")
        print("  - LED increments")
        print("  - Protocol = 0x01 (ICMP)")
        print("  - In Mode 2: LED shows 0x1")

def test_invalid_checksum(iface):
    """Test 4: IP packet with corrupted checksum"""
    # Build packet first to get correct checksum
    pkt = Ether(dst=FPGA_MAC) / IP(src=SRC_IP, dst=FPGA_IP) / UDP() / Raw(b"test")

    # Build to calculate checksum, then corrupt it
    pkt = pkt.__class__(bytes(pkt))
    pkt[IP].chksum = 0xFFFF  # Wrong value

    # Delete checksum so it doesn't get recalculated
    del pkt[IP].chksum
    pkt[IP].chksum = 0xFFFF

    if send_test_packet(iface, "Invalid Checksum", pkt):
        print("\nExpected behavior:")
        print("  - LED does NOT increment")
        print("  - Error flag set (red LED)")
        print("  - IP parser should reject this packet")

def test_wrong_mac(iface):
    """Test 5: Packet to wrong MAC (should be filtered by MAC parser)"""
    pkt = Ether(dst="FF:FF:FF:FF:FF:FF") / IP(src=SRC_IP, dst=FPGA_IP) / UDP()
    if send_test_packet(iface, "Wrong Destination MAC (Broadcast)", pkt):
        print("\nExpected behavior:")
        print("  - No response (filtered by MAC parser)")
        print("  - FPGA only accepts unicast to 00:0a:35:02:af:9a")

def test_burst(iface, count=10):
    """Test 6: Burst of packets"""
    print(f"\n{'='*60}")
    print(f"Test: Burst of {count} UDP Packets")
    print(f"{'='*60}")

    success_count = 0
    for i in range(count):
        pkt = Ether(dst=FPGA_MAC) / IP(src=SRC_IP, dst=FPGA_IP) / UDP() / Raw(f"Packet {i}".encode())
        try:
            sendp(pkt, iface=iface, verbose=False)
            success_count += 1
        except Exception as e:
            print(f"Error sending packet {i}: {e}")
        time.sleep(0.1)

    print(f"\nSent {success_count}/{count} packets successfully")
    print(f"\nExpected behavior:")
    print(f"  - LED shows count (0x{count:X})")
    print(f"  - In Mode 2: Should show protocol 0x1 (UDP)")

def main():
    parser = argparse.ArgumentParser(description="Test FPGA IP parser")
    parser.add_argument("--test", type=int, help="Run specific test only (1-6)")
    parser.add_argument("--burst", type=int, default=10, help="Burst packet count (default: 10)")

    args = parser.parse_args()

    print("="*60)
    print("FPGA IP Parser Hardware Test")
    print("="*60)

    # Find interface
    iface, mac = find_interface()

    if not iface:
        print("\n❌ No interface selected")
        sys.exit(1)

    print(f"\nConfiguration:")
    print(f"  Interface: {iface}")
    if mac:
        print(f"  PC MAC: {mac}")
    print(f"  FPGA MAC: {FPGA_MAC}")
    print(f"  FPGA IP: {FPGA_IP} (target, not configured on FPGA)")
    print("="*60)

    print("\n📋 Display Modes (press BTN3 to cycle):")
    print("  Mode 0: MAC frame count")
    print("  Mode 1: MDIO registers")
    print("  Mode 2: IP protocol (last packet)")
    print("="*60)

    input("\nPress Enter to start tests...")

    try:
        if args.test:
            # Run specific test
            tests = {
                1: lambda: test_valid_udp(iface),
                2: lambda: test_valid_tcp(iface),
                3: lambda: test_valid_icmp(iface),
                4: lambda: test_invalid_checksum(iface),
                5: lambda: test_wrong_mac(iface),
                6: lambda: test_burst(iface, args.burst)
            }
            if args.test in tests:
                tests[args.test]()
            else:
                print(f"Invalid test number: {args.test}")
        else:
            # Run all tests
            test_valid_udp(iface)
            time.sleep(2)

            test_valid_tcp(iface)
            time.sleep(2)

            test_valid_icmp(iface)
            time.sleep(2)

            test_invalid_checksum(iface)
            time.sleep(2)

            test_wrong_mac(iface)
            time.sleep(2)

            test_burst(iface, args.burst)

    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
    except Exception as e:
        import traceback
        print(f"\n❌ Error: {e}")
        print("\nTraceback:")
        traceback.print_exc()

    print("\n" + "="*60)
    print("Tests Complete")
    print("="*60)
    print("\n💡 Tips:")
    print("  - Use BTN3 to cycle display modes")
    print("  - Mode 0 shows total frame count")
    print("  - Mode 2 shows last IP protocol (lower 4 bits)")
    print("  - Check LD4 Green for frame activity")
    print("  - Check LD4 Red for errors")
    print("="*60)

if __name__ == "__main__":
    main()
