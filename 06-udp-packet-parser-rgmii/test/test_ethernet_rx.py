"""
Project 6: UDP Packet Parser - Phase 1A Test Script

Sends various Ethernet frames to the Arty FPGA to test reception.

Requirements:
  pip install scapy

Usage:
  sudo python3 test_ethernet_rx.py

Note: Requires root/admin privileges to send raw Ethernet frames
"""

import sys
import time
from scapy.all import *

# Configuration
FPGA_MAC = "00:0a:35:02:af:9a"  # Arty FPGA MAC address
FPGA_IP = "192.168.1.100"        # Arty FPGA IP address
PC_IP = "192.168.1.1"            # Your PC IP address
INTERFACE = "Ethernet 17"                 # Change to your interface name

# Colors for terminal output
GREEN = '\033[92m'
RED = '\033[91m'
BLUE = '\033[94m'
YELLOW = '\033[93m'
RESET = '\033[0m'

def print_header(text):
    """Print colored header"""
    print(f"\n{BLUE}{'='*70}{RESET}")
    print(f"{BLUE}{text:^70}{RESET}")
    print(f"{BLUE}{'='*70}{RESET}\n")

def print_test(text):
    """Print test description"""
    print(f"{YELLOW}[TEST]{RESET} {text}")

def print_success(text):
    """Print success message"""
    print(f"{GREEN}[PASS]{RESET} {text}")

def print_error(text):
    """Print error message"""
    print(f"{RED}[ERROR]{RESET} {text}")

def send_frame(packet, description, count=1):
    """Send Ethernet frame and report"""
    print_test(f"{description} (sending {count} frame(s))")
    try:
        sendp(packet, iface=INTERFACE, count=count, verbose=False)
        print_success(f"Sent {count} frame(s)")
        time.sleep(0.5)  # Give FPGA time to process
        return True
    except Exception as e:
        print_error(f"Failed to send: {e}")
        return False

def test_basic_ping():
    """Test 1: Basic ICMP ping"""
    print_header("Test 1: Basic ICMP Ping")
    packet = Ether(dst=FPGA_MAC) / IP(dst=FPGA_IP, src=PC_IP) / ICMP()
    send_frame(packet, "ICMP Echo Request", count=5)
    print("Expected: LEDs should increment by 5 (binary: 0101)")

def test_arp_request():
    """Test 2: ARP request"""
    print_header("Test 2: ARP Request")
    packet = Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(pdst=FPGA_IP)
    send_frame(packet, "ARP Who-has request", count=3)
    print("Expected: LEDs should increment by 3 (broadcast frames)")

def test_udp_packet():
    """Test 3: UDP packet (for Phase 2)"""
    print_header("Test 3: UDP Packet")
    packet = Ether(dst=FPGA_MAC) / IP(dst=FPGA_IP, src=PC_IP) / UDP(dport=12345, sport=54321) / Raw(b"Hello FPGA!")
    send_frame(packet, "UDP packet to port 12345", count=10)
    print("Expected: LEDs should increment by 10")

def test_burst():
    """Test 4: Burst of frames"""
    print_header("Test 4: Burst Test")
    packet = Ether(dst=FPGA_MAC) / IP(dst=FPGA_IP, src=PC_IP) / ICMP()
    print_test("Sending 100 frames rapidly")
    try:
        sendp(packet, iface=INTERFACE, count=100, inter=0.001, verbose=False)
        print_success("Sent 100 frames at ~1ms intervals")
        print("Expected: LEDs should increment to 100 (wraps to 4 in 4-bit display)")
    except Exception as e:
        print_error(f"Failed: {e}")

def test_wrong_mac():
    """Test 5: Frame with wrong destination MAC (should be filtered)"""
    print_header("Test 5: MAC Filtering Test")
    packet = Ether(dst="00:11:22:33:44:55") / IP(dst=FPGA_IP, src=PC_IP) / ICMP()
    send_frame(packet, "Frame with WRONG MAC address", count=5)
    print("Expected: LEDs should NOT increment (filtered by MAC)")

def test_broadcast():
    """Test 6: Broadcast frame"""
    print_header("Test 6: Broadcast Frame")
    packet = Ether(dst="ff:ff:ff:ff:ff:ff") / IP(dst="255.255.255.255", src=PC_IP) / UDP(dport=12345) / Raw(b"Broadcast!")
    send_frame(packet, "Broadcast frame", count=3)
    print("Expected: LEDs should increment by 3 (accepts broadcast)")

def test_various_sizes():
    """Test 7: Various frame sizes"""
    print_header("Test 7: Frame Size Test")
    
    # Minimum size (64 bytes)
    packet = Ether(dst=FPGA_MAC) / IP(dst=FPGA_IP, src=PC_IP) / Raw(b"X" * 18)
    send_frame(packet, "Minimum frame (64 bytes)", count=1)
    
    # Medium size (500 bytes)
    packet = Ether(dst=FPGA_MAC) / IP(dst=FPGA_IP, src=PC_IP) / Raw(b"X" * 454)
    send_frame(packet, "Medium frame (500 bytes)", count=1)
    
    # Maximum size (1518 bytes)
    packet = Ether(dst=FPGA_MAC) / IP(dst=FPGA_IP, src=PC_IP) / Raw(b"X" * 1472)
    send_frame(packet, "Maximum frame (1518 bytes)", count=1)
    
    print("Expected: LEDs should increment by 3 (all sizes accepted)")

def interactive_menu():
    """Interactive test menu"""
    print_header("Project 6: Ethernet RX Test Suite")
    print(f"FPGA MAC: {FPGA_MAC}")
    print(f"FPGA IP:  {FPGA_IP}")
    print(f"PC IP:    {PC_IP}")
    print(f"Interface: {INTERFACE}\n")
    
    while True:
        print("\nAvailable Tests:")
        print("  1. Basic ICMP Ping (5 frames)")
        print("  2. ARP Request (3 frames)")
        print("  3. UDP Packet (10 frames)")
        print("  4. Burst Test (100 frames)")
        print("  5. MAC Filtering Test (should be filtered)")
        print("  6. Broadcast Frame (3 frames)")
        print("  7. Various Frame Sizes (3 frames)")
        print("  8. Run ALL Tests")
        print("  9. Continuous Ping (Ctrl+C to stop)")
        print("  0. Exit")
        
        choice = input("\nSelect test (0-9): ").strip()
        
        if choice == '1':
            test_basic_ping()
        elif choice == '2':
            test_arp_request()
        elif choice == '3':
            test_udp_packet()
        elif choice == '4':
            test_burst()
        elif choice == '5':
            test_wrong_mac()
        elif choice == '6':
            test_broadcast()
        elif choice == '7':
            test_various_sizes()
        elif choice == '8':
            test_basic_ping()
            test_arp_request()
            test_udp_packet()
            test_burst()
            test_wrong_mac()
            test_broadcast()
            test_various_sizes()
            print_header("ALL TESTS COMPLETE")
        elif choice == '9':
            print_test("Continuous ping - Press Ctrl+C to stop")
            packet = Ether(dst=FPGA_MAC) / IP(dst=FPGA_IP, src=PC_IP) / ICMP()
            try:
                while True:
                    sendp(packet, iface=INTERFACE, verbose=False)
                    time.sleep(1)
            except KeyboardInterrupt:
                print_success("\nStopped continuous ping")
        elif choice == '0':
            print("\nExiting...")
            break
        else:
            print_error("Invalid choice")

def check_privileges():
    """Check if running with root privileges"""
    if os.geteuid() != 0:
        print_error("This script requires root privileges to send raw Ethernet frames")
        print("Please run with sudo:")
        print(f"  sudo python3 {sys.argv[0]}")
        sys.exit(1)

def main():
    """Main entry point"""
    check_privileges()
   
    # List available interfaces
    print("\nAvailable network interfaces:")
    for iface in get_if_list():
        print(f"  - {iface}")
    
    # Confirm interface
    global INTERFACE
    iface_input = input(f"\nUse interface '{INTERFACE}'? (y/n or enter new name): ").strip()
    if iface_input.lower() == 'n':
        INTERFACE = input("Enter interface name: ").strip()
    elif iface_input and iface_input.lower() != 'y':
        INTERFACE = iface_input
    
    print(f"Using interface: {INTERFACE}")
    
    # Run interactive menu
    interactive_menu()

if __name__ == "__main__":
    main()