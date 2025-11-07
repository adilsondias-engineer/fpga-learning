#!/usr/bin/env python3
"""
IP Parser Hardware Test Script
Sends various IP packets and verifies FPGA behavior
Automatically detects USB Ethernet interface by MAC address

Requirements:
  pip install scapy

Usage:
  sudo python3 test_ip_ethernet.py           # Auto-detect interface, run all tests
  sudo python3 test_ip_ethernet.py --test 1  # Run specific test
  sudo python3 test_ip_ethernet.py --burst 20 # Custom burst size
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
if os.name != 'nt':  # Unix/Linux/Mac
    if os.geteuid() != 0:
        print("\n❌ ERROR: This script requires root privileges")
        print("\nRun with sudo:")
        print(f"  sudo python3 {sys.argv[0]}")
        sys.exit(1)
else:  # Windows
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
        marker = "  ← Your USB" if mac and mac.lower() == PC_INTERFACE_MAC.lower().replace('-', ':') else ""
        print(f"  {i+1}. {iface}{mac_str}{marker}")
        interface_map[i] = (iface, mac)
    
    # Try to auto-detect USB Ethernet by MAC
    for i, (iface, mac) in interface_map.items():
        if mac and mac.lower() == PC_INTERFACE_MAC.lower().replace('-', ':'):
            print(f"\n✓ Auto-detected USB Ethernet: {iface} (MAC: {mac})")
            confirm = input("Use this interface? (y/n): ").strip().lower()
            if confirm == 'y':
                return iface, mac
    
    # Manual selection if auto-detect fails
    print("\n⚠ Could not auto-detect USB Ethernet interface")
    print(f"   Looking for MAC: {PC_INTERFACE_MAC}")
    print("\nPlease select interface manually:")
    
    while True:
        try:
            choice = input(f"Enter number (1-{len(interfaces)}): ").strip()
            idx = int(choice) - 1
            if 0 <= idx < len(interfaces):
                iface, mac = interface_map[idx]
                print(f"Selected: {iface} (MAC: {mac})")
                return iface, mac
            else:
                print(f"Invalid choice. Enter 1-{len(interfaces)}")
        except ValueError:
            print("Invalid input. Enter a number.")
        except KeyboardInterrupt:
            print("\n\nCancelled by user")
            sys.exit(0)

def send_test_packet(iface, description, packet):
    """Send a test packet and display info"""
    print(f"\n{'='*70}")
    print(f"Test: {description}")
    print(f"{'='*70}")
    print(f"Packet summary: {packet.summary()}")
    
    if IP in packet:
        print(f"  IP: {packet[IP].src} -> {packet[IP].dst}")
        print(f"  Protocol: {packet[IP].proto} ({packet[IP].sprintf('%IP.proto%')})")
        print(f"  Total Length: {packet[IP].len} bytes")
        chksum = packet[IP].chksum
        print(f"  Checksum: 0x{chksum:04X}" if chksum is not None else "  Checksum: (auto)")
    
    print(f"\nSending...")
    sendp(packet, iface=iface, verbose=False)
    print("✓ Sent!")
    print(f"{'='*70}")

def test_valid_udp(iface):
    """Test 1: Valid UDP packet to port 80"""
    pkt = Ether(dst=FPGA_MAC) / IP(src=SRC_IP, dst=FPGA_IP) / UDP(dport=80, sport=12345) / Raw(b"GET / HTTP/1.1\r\n")
    send_test_packet(iface, "Valid UDP packet (port 80)", pkt)
    print("Expected: Mode 2 LEDs show 0x1 (UDP=17=0x11, lower 4 bits=0x1)")

def test_valid_tcp(iface):
    """Test 2: Valid TCP packet to port 443"""
    pkt = Ether(dst=FPGA_MAC) / IP(src=SRC_IP, dst=FPGA_IP) / TCP(dport=443, sport=54321)
    send_test_packet(iface, "Valid TCP packet (port 443)", pkt)
    print("Expected: Mode 2 LEDs show 0x6 (TCP=6)")

def test_valid_icmp(iface):
    """Test 3: Valid ICMP echo request (ping)"""
    pkt = Ether(dst=FPGA_MAC) / IP(src=SRC_IP, dst=FPGA_IP) / ICMP()
    send_test_packet(iface, "Valid ICMP Echo Request (ping)", pkt)
    print("Expected: Mode 2 LEDs show 0x1 (ICMP=1)")

def test_invalid_checksum(iface):
    """Test 4: IP packet with bad checksum (should be rejected)"""
    pkt = Ether(dst=FPGA_MAC) / IP(src=SRC_IP, dst=FPGA_IP, chksum=0x0000) / UDP(dport=80)
    send_test_packet(iface, "Invalid IP checksum (should reject)", pkt)
    print("Expected: LD4 Red flashes (checksum error)")
    print("Expected: Mode 0 counter does NOT increment")

def test_wrong_mac(iface):
    """Test 5: Correct IP but wrong MAC (should be rejected by MAC parser)"""
    pkt = Ether(dst="ff:ff:ff:ff:ff:ff") / IP(src=SRC_IP, dst=FPGA_IP) / UDP(dport=80)
    send_test_packet(iface, "Wrong MAC address (should reject)", pkt)
    print("Expected: No LED changes (MAC mismatch)")

def test_wrong_ip_version(iface):
    """Test 6: IPv6 packet (wrong EtherType 0x86DD, should be ignored)"""
    # Scapy doesn't easily let us send malformed IPv4, so we test with IPv6
    print(f"\n{'='*70}")
    print("Test: IPv6 packet (wrong EtherType)")
    print(f"{'='*70}")
    print("Skipping: Would require manual frame construction")
    print("Expected: IP parser ignores (EtherType != 0x0800)")
    print(f"{'='*70}")

def test_burst(iface, count=10):
    """Test 7: Burst of valid packets"""
    print(f"\n{'='*70}")
    print(f"Test: Burst of {count} UDP packets")
    print(f"{'='*70}")
    
    for i in range(count):
        pkt = Ether(dst=FPGA_MAC) / IP(src=SRC_IP, dst=FPGA_IP) / UDP(dport=80+i) / Raw(f"Packet {i}".encode())
        sendp(pkt, iface=iface, verbose=False)
        print(f"  Sent packet {i+1}/{count}", end='\r')
        time.sleep(0.1)
    
    print(f"\n✓ Sent {count} packets!")
    print(f"Expected: Mode 0 counter increments by {count}")
    print(f"{'='*70}")

def test_fragmented(iface):
    """Test 8: Fragmented IP packet (should reject - IHL != 5)"""
    print(f"\n{'='*70}")
    print("Test: IP packet with options (IHL != 5)")
    print(f"{'='*70}")
    print("Skipping: Requires manual frame construction with IP options")
    print("Expected: LD5 Red flashes (version/IHL error)")
    print(f"{'='*70}")

def main():
    parser = argparse.ArgumentParser(description="IP Parser Hardware Test")
    parser.add_argument('--test', type=int, help='Run specific test number (1-7)')
    parser.add_argument('--burst', type=int, default=10, help='Number of packets for burst test (default: 10)')
    args = parser.parse_args()
    
    print("\n" + "="*70)
    print("  IP PARSER HARDWARE TEST - Phase 1D")
    print("="*70)
    print(f"  FPGA MAC: {FPGA_MAC}")
    print(f"  FPGA IP:  {FPGA_IP} (not configured, just used in packets)")
    print(f"  Src IP:   {SRC_IP}")
    print("="*70)
    
    # Find interface
    iface, mac = find_interface()
    
    print("\n" + "="*70)
    print(f"  Using Interface: {iface}")
    print(f"  MAC Address: {mac}")
    print("="*70)
    
    print("\n💡 Before starting:")
    print("  1. Program FPGA with Phase 1D bitstream")
    print("  2. Connect USB Ethernet to FPGA")
    print("  3. Verify PHY link is up (check MDIO display mode)")
    print("  4. Note starting LED counter value")
    print("="*70)
    
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
                6: lambda: test_wrong_ip_version(iface),
                7: lambda: test_burst(iface, args.burst),
                8: lambda: test_fragmented(iface)
            }
            if args.test in tests:
                tests[args.test]()
            else:
                print(f"Invalid test number: {args.test}")
                print("Valid tests: 1-8")
        else:
            # Run all tests
            print("\nRunning all tests...\n")
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
            
            test_wrong_ip_version(iface)
            time.sleep(2)
            
            test_burst(iface, args.burst)
            time.sleep(2)
            
            test_fragmented(iface)
    
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
    
    print("\n" + "="*70)
    print("  TESTS COMPLETE")
    print("="*70)
    print("\n💡 Verification Tips:")
    print("  - Use BTN3 to cycle display modes")
    print("  - Mode 0: Total frame count (should increment)")
    print("  - Mode 1: MDIO registers (cycles automatically)")
    print("  - Mode 2: Last IP protocol (lower 4 bits on LEDs)")
    print("    • 0x1 = ICMP or UDP (17 & 0xF)")
    print("    • 0x6 = TCP")
    print("  - LD4 Green: Frame activity (flashes on each frame)")
    print("  - LD4 Red: Checksum error (flashes on invalid checksum)")
    print("  - LD5 Red: Version/IHL error (flashes on invalid header)")
    print("="*70)
    print("\n✓ Ready for Phase 1E: UDP Parser!")
    print("="*70)

if __name__ == "__main__":
    main()