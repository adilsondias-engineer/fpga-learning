#!/usr/bin/env python3
"""
Phase 1F (v5) UDP Parser Integration Test Script
Tests complete Ethernet pipeline: MAC → IP → UDP parsing
Automatically detects USB Ethernet interface by MAC address

Requirements:
  pip install scapy

Usage:
  sudo python3 test_udp_parser_v5.py           # Auto-detect interface, run all tests
  sudo python3 test_udp_parser_v5.py --test 1  # Run specific test
  sudo python3 test_udp_parser_v5.py --burst 20 # Custom burst size
"""

import sys
import time
import argparse

# Check for Scapy
try:
    from scapy.all import Ether, IP, UDP, TCP, Raw, sendp, get_if_list
except ImportError:
    print("\nERROR: ERROR: Scapy not installed")
    print("\nInstall with:")
    print("  pip3 install scapy")
    sys.exit(1)

# Check for root privileges
import os
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
FPGA_MAC = "00:0a:35:02:af:9a"          # FPGA MAC address
FPGA_IP = "192.168.1.100"                # FPGA IP address (not configured, but used in packets)
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
            print(f"\n Auto-detected USB Ethernet: {iface} (MAC: {mac})")
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
    
    if UDP in packet:
        print(f"  UDP: {packet[UDP].sport} -> {packet[UDP].dport}")
        print(f"  Payload length: {len(packet[UDP].payload)} bytes")
        print(f"  UDP Length: {packet[UDP].len}")
        chksum = packet[UDP].chksum
        print(f"  UDP Checksum: 0x{chksum:04X}" if chksum is not None else "  UDP Checksum: (auto)")
    
    print(f"\nSending...")
    sendp(packet, iface=iface, verbose=False)
    print(" Sent!")
    print(f"{'='*70}")

def test_udp_port_80(iface):
    """Test 1: Valid UDP to port 80 (HTTP)"""
    pkt = Ether(dst=FPGA_MAC) / \
          IP(src=SRC_IP, dst=FPGA_IP) / \
          UDP(dport=80, sport=12345) / \
          Raw(b"GET / HTTP/1.1\r\n")
    send_test_packet(iface, "Valid UDP to port 80 (HTTP)", pkt)
    print("Expected:")
    print("  - Mode 3 LEDs cycle showing: 0x0 → 0x0 → 0x5 → 0x0 (port 80 = 0x0050)")
    print("  - LD4 Green flashes")
    print("  - udp_valid asserted")

def test_udp_port_53(iface):
    """Test 2: Valid UDP to port 53 (DNS)"""
    pkt = Ether(dst=FPGA_MAC) / \
          IP(src=SRC_IP, dst=FPGA_IP) / \
          UDP(dport=53, sport=49320) / \
          Raw(b"DNSQUERY")
    send_test_packet(iface, "Valid UDP to port 53 (DNS)", pkt)
    print("Expected:")
    print("  - Mode 3 LEDs cycle showing: 0x0 → 0x0 → 0x3 → 0x5 (port 53 = 0x0035)")
    print("  - LD4 Green flashes")

def test_udp_port_443(iface):
    """Test 3: Valid UDP to port 443 (HTTPS)"""
    pkt = Ether(dst=FPGA_MAC) / \
          IP(src=SRC_IP, dst=FPGA_IP) / \
          UDP(dport=443, sport=55000) / \
          Raw(b"TLS_DATA")
    send_test_packet(iface, "Valid UDP to port 443 (HTTPS)", pkt)
    print("Expected:")
    print("  - Mode 3 LEDs cycle showing: 0x0 → 0x1 → 0xB → 0xB (port 443 = 0x01BB)")
    print("  - LD4 Green flashes")

def test_udp_checksum_disabled(iface):
    """Test 4: UDP with checksum disabled (0x0000)"""
    pkt = Ether(dst=FPGA_MAC) / \
          IP(src=SRC_IP, dst=FPGA_IP) / \
          UDP(dport=8080, sport=1234, chksum=0)
    send_test_packet(iface, "UDP with checksum=0 (disabled)", pkt)
    print("Expected:")
    print("  - Packet accepted (checksum 0 = valid per RFC 768)")
    print("  - Mode 3 shows port 8080 = 0x1F90")

def test_tcp_packet(iface):
    """Test 5: TCP packet (should be ignored by UDP parser)"""
    pkt = Ether(dst=FPGA_MAC) / \
          IP(src=SRC_IP, dst=FPGA_IP) / \
          TCP(dport=80, sport=12345)
    send_test_packet(iface, "TCP packet (protocol=6, should ignore)", pkt)
    print("Expected:")
    print("  - UDP parser stays in IDLE (protocol != 0x11)")
    print("  - Mode 2 shows 0x6 (TCP protocol)")
    print("  - Mode 3 shows last UDP port (no update)")

def test_udp_burst(iface, count=10):
    """Test 6: Burst of UDP packets to different ports"""
    print(f"\n{'='*70}")
    print(f"Test: Burst of {count} UDP packets to different ports")
    print(f"{'='*70}")
    
    ports = [80, 53, 443, 8080, 3000, 5000, 6000, 7000, 8000, 9000]
    
    for i in range(count):
        port = ports[i % len(ports)]
        pkt = Ether(dst=FPGA_MAC) / \
              IP(src=SRC_IP, dst=FPGA_IP) / \
              UDP(dport=port, sport=50000+i) / \
              Raw(f"Packet {i}".encode())
        sendp(pkt, iface=iface, verbose=False)
        print(f"  Sent packet {i+1}/{count} to port {port}", end='\r')
        time.sleep(0.1)
    
    print(f"\n Sent {count} packets!")
    print(f"Expected:")
    print(f"  - Mode 0 counter increments by {count}")
    print(f"  - Mode 3 shows last port sent")
    print(f"  - LD4 Green flashes multiple times")
    print(f"{'='*70}")

def test_udp_length_mismatch(iface):
    """Test 7: UDP with length mismatch (should be caught)"""
    pkt = Ether(dst=FPGA_MAC) / \
          IP(src=SRC_IP, dst=FPGA_IP) / \
          UDP(dport=9999, sport=1111)
    
    # Manually corrupt UDP length
    frame_bytes = bytearray(bytes(pkt))
    # UDP length is at byte 38-39 (14 MAC + 20 IP + 4 UDP offset)
    frame_bytes[38] = 0x01  # Set length to 0x0100 = 256 bytes
    frame_bytes[39] = 0x00
    
    print(f"\n{'='*70}")
    print("Test: UDP with length mismatch error")
    print(f"{'='*70}")
    print("Sending corrupted packet...")
    sendp(bytes(frame_bytes), iface=iface, verbose=False)
    print(" Sent!")
    print("\nExpected:")
    print("  - LD5 Red flashes (length error)")
    print("  - udp_length_err asserted")
    print("  - Packet rejected")
    print(f"{'='*70}")

def test_min_udp(iface):
    """Test 8: Minimum UDP packet (header only, no payload)"""
    pkt = Ether(dst=FPGA_MAC) / \
          IP(src=SRC_IP, dst=FPGA_IP) / \
          UDP(dport=1, sport=2)
    send_test_packet(iface, "Minimum UDP packet (8 bytes, no payload)", pkt)
    print("Expected:")
    print("  - Packet accepted")
    print("  - Mode 3 shows port 1 = 0x0001")
    print("  - No payload_valid pulses")

def main():
    parser = argparse.ArgumentParser(description="v5 UDP Parser Integration Test")
    parser.add_argument('--test', type=int, help='Run specific test number (1-8)')
    parser.add_argument('--burst', type=int, default=10, help='Number of packets for burst test (default: 10)')
    args = parser.parse_args()
    
    print("\n" + "="*70)
    print("  UDP PARSER INTEGRATION TEST - Phase 1F (v5)")
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
    print("  1. Program FPGA with Phase 1F (v5) bitstream")
    print("  2. Connect USB Ethernet to FPGA")
    print("  3. Verify PHY link is up (check Mode 1 MDIO display)")
    print("  4. Press BTN3 to cycle to Mode 3 (UDP ports)")
    print("  5. Note starting LED counter value (Mode 0)")
    print("="*70)
    
    input("\nPress Enter to start tests...")
    
    try:
        if args.test:
            # Run specific test
            tests = {
                1: lambda: test_udp_port_80(iface),
                2: lambda: test_udp_port_53(iface),
                3: lambda: test_udp_port_443(iface),
                4: lambda: test_udp_checksum_disabled(iface),
                5: lambda: test_tcp_packet(iface),
                6: lambda: test_udp_burst(iface, args.burst),
                7: lambda: test_udp_length_mismatch(iface),
                8: lambda: test_min_udp(iface)
            }
            if args.test in tests:
                tests[args.test]()
            else:
                print(f"Invalid test number: {args.test}")
                print("Valid tests: 1-8")
        else:
            # Run all tests
            print("\nRunning all tests...\n")
            test_udp_port_80(iface)
            time.sleep(3)
            
            test_udp_port_53(iface)
            time.sleep(3)
            
            test_udp_port_443(iface)
            time.sleep(3)
            
            test_udp_checksum_disabled(iface)
            time.sleep(3)
            
            test_tcp_packet(iface)
            time.sleep(3)
            
            test_udp_burst(iface, args.burst)
            time.sleep(3)
            
            test_udp_length_mismatch(iface)
            time.sleep(3)
            
            test_min_udp(iface)
    
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
    print("  - Use BTN3 to cycle display modes:")
    print("    • Mode 0: Total frame count")
    print("    • Mode 1: MDIO registers (cycles)")
    print("    • Mode 2: IP protocol (0x11 = UDP, 0x06 = TCP)")
    print("    • Mode 3: UDP destination port (nibbles cycle)")
    print("\n  - LED Indicators:")
    print("    • LD4 Green: Frame activity (flashes on each frame)")
    print("    • LD4 Red: IP checksum error")
    print("    • LD5 Red: UDP length error")
    print("    • LD4 Blue: PHY ready")
    print("="*70)
    print("\n Phase 1F complete!")
    print(" Ready for Phase 2: Market Data Protocols!")
    print("="*70)

if __name__ == "__main__":
    main()