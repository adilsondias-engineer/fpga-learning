#!/usr/bin/env python3
"""
UDP Packet Listener - Project 13
Listens for UDP packets from FPGA on port 5001
Displays packet contents and statistics
"""

import socket
import sys
import time
from datetime import datetime

# Configuration
LISTEN_IP = "0.0.0.0"  # Listen on all interfaces
LISTEN_PORT = 5001
BUFFER_SIZE = 1024

def print_hex_dump(data):
    """Print data as hex dump with ASCII"""
    print("\n  Offset  Hex                                              ASCII")
    print("  ------  -----------------------------------------------  ----------------")

    for i in range(0, len(data), 16):
        # Offset
        offset = f"  {i:04X}    "

        # Hex bytes
        hex_part = ""
        ascii_part = ""
        for j in range(16):
            if i + j < len(data):
                byte = data[i + j]
                hex_part += f"{byte:02X} "
                # ASCII representation (printable chars only)
                if 32 <= byte <= 126:
                    ascii_part += chr(byte)
                else:
                    ascii_part += "."
            else:
                hex_part += "   "
                ascii_part += " "

            # Add extra space after 8 bytes
            if j == 7:
                hex_part += " "

        print(f"{offset}{hex_part} {ascii_part}")

def main():
    print("=" * 80)
    print("UDP Packet Listener - FPGA Project 13")
    print("=" * 80)
    print(f"Listening on {LISTEN_IP}:{LISTEN_PORT}")
    print("Press Ctrl+C to stop\n")

    # Create UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    try:
        # Bind to port
        sock.bind((LISTEN_IP, LISTEN_PORT))
        print(f"Successfully bound to port {LISTEN_PORT}")
        print("Waiting for packets...\n")

        packet_count = 0
        start_time = time.time()

        while True:
            # Receive packet
            data, addr = sock.recvfrom(BUFFER_SIZE)
            packet_count += 1
            timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]

            # Print packet info
            print("=" * 80)
            print(f"Packet #{packet_count} at {timestamp}")
            print(f"From: {addr[0]}:{addr[1]}")
            print(f"Size: {len(data)} bytes")

            # Print payload as string (if printable)
            try:
                payload_str = data.decode('ascii')
                if all(32 <= ord(c) <= 126 or c in '\r\n\t' for c in payload_str):
                    print(f"Payload (ASCII): \"{payload_str}\"")
            except:
                pass

            # Print hex dump
            print_hex_dump(data)

            # Statistics
            elapsed = time.time() - start_time
            rate = packet_count / elapsed if elapsed > 0 else 0
            print(f"\nTotal packets: {packet_count} | Rate: {rate:.2f} pkt/s")
            print("=" * 80)
            print()

    except KeyboardInterrupt:
        print("\n\nStopping listener...")
    except Exception as e:
        print(f"\nError: {e}")
        return 1
    finally:
        sock.close()
        print("Socket closed")

    return 0

if __name__ == "__main__":
    sys.exit(main())
