#!/usr/bin/env python3
"""
UDP Listener for FPGA Ethernet Test
Listens for UDP packets from the FPGA on port 5000
"""

import socket
import sys
import time
from datetime import datetime

def listen_udp(port=5000, timeout=10):
    """
    Listen for UDP packets on the specified port

    Args:
        port: UDP port to listen on (default 5000)
        timeout: How long to wait for packets in seconds (default 10)
    """
    # Create UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    # Bind to all interfaces on the specified port
    sock.bind(('', port))
    sock.settimeout(1)  # 1 second timeout for recv

    print(f"Listening for UDP packets on port {port}...")
    print(f"Waiting up to {timeout} seconds for packets...")
    print("-" * 60)

    packet_count = 0
    start_time = time.time()

    try:
        while True:
            elapsed = time.time() - start_time
            if elapsed > timeout and packet_count == 0:
                print(f"\nTimeout: No packets received after {timeout} seconds")
                break

            try:
                data, addr = sock.recvfrom(1024)
                packet_count += 1
                timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]

                print(f"\n[{timestamp}] Packet #{packet_count} from {addr[0]}:{addr[1]}")
                print(f"  Length: {len(data)} bytes")
                print(f"  Data (ASCII): {data.decode('ascii', errors='replace')}")
                print(f"  Data (Hex):   {data.hex()}")

            except socket.timeout:
                # No packet received in this 1-second window, continue
                if packet_count > 0 and elapsed > timeout:
                    # We got some packets and timeout expired
                    break
                continue

    except KeyboardInterrupt:
        print("\n\nInterrupted by user")

    finally:
        sock.close()
        print("-" * 60)
        print(f"Total packets received: {packet_count}")

        if packet_count > 0:
            print("✓ SUCCESS: FPGA is transmitting UDP packets!")
        else:
            print("✗ FAILED: No UDP packets received")
            print("\nTroubleshooting:")
            print("  1. Check that FPGA is programmed and running")
            print("  2. Verify Ethernet cable is connected")
            print("  3. Check that PC IP is 192.168.0.x")
            print("  4. Verify firewall isn't blocking UDP port 5000")
            print("  5. Try running Wireshark to see if packets arrive at all")

if __name__ == "__main__":
    port = 5000
    timeout = 30  # 30 seconds should be plenty for 10 packets

    if len(sys.argv) > 1:
        port = int(sys.argv[1])

    if len(sys.argv) > 2:
        timeout = int(sys.argv[2])

    listen_udp(port, timeout)
