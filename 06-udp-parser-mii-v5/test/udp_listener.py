#!/usr/bin/env python3
"""
Simple UDP Listener for Testing FPGA TX
Listens for UDP packets from FPGA and prints received data

Usage:
    python3 udp_listener.py [--port PORT] [--timeout SECONDS]

Example:
    python3 udp_listener.py --port 80 --timeout 30
"""

import socket
import argparse
import sys
from datetime import datetime

def listen_udp(port=80, timeout=30):
    """Listen for UDP packets on specified port"""
    print(f"\n{'='*70}")
    print(f"UDP Listener - Waiting for packets from FPGA")
    print(f"{'='*70}")
    print(f"Port: {port}")
    print(f"Timeout: {timeout} seconds")
    print(f"{'='*70}\n")
    
    try:
        # Create UDP socket
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(('0.0.0.0', port))  # Listen on all interfaces
        sock.settimeout(timeout)
        
        print(f" Listening on port {port}...")
        print(f"  (Press Ctrl+C to stop)\n")
        
        packet_count = 0
        
        while True:
            try:
                data, addr = sock.recvfrom(1024)  # Buffer up to 1024 bytes
                packet_count += 1
                timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
                
                print(f"[{timestamp}] Packet #{packet_count} from {addr[0]}:{addr[1]}")
                print(f"  Length: {len(data)} bytes")
                print(f"  Data (hex): {data.hex()}")
                print(f"  Data (ASCII): {repr(data)}")
                
                # Try to decode as text
                try:
                    text = data.decode('utf-8', errors='replace')
                    if text.isprintable():
                        print(f"  Data (text): {text}")
                except:
                    pass
                
                print()
                
            except socket.timeout:
                print(f"\n⏱ Timeout after {timeout} seconds")
                print(f"   Received {packet_count} packet(s)")
                break
                
    except KeyboardInterrupt:
        print(f"\n\n Stopped by user")
        print(f"   Received {packet_count} packet(s)")
    except Exception as e:
        print(f"\nERROR: Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        sock.close()
        print(f"\n{'='*70}")
        print("Listener closed")
        print(f"{'='*70}\n")

def main():
    parser = argparse.ArgumentParser(description="UDP Listener for FPGA TX Testing")
    parser.add_argument('--port', type=int, default=80, 
                       help='UDP port to listen on (default: 80)')
    parser.add_argument('--timeout', type=int, default=30,
                       help='Timeout in seconds (default: 30, 0 = no timeout)')
    args = parser.parse_args()
    
    if args.timeout == 0:
        args.timeout = None
    
    listen_udp(args.port, args.timeout)

if __name__ == "__main__":
    main()

