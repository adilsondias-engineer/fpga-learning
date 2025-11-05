#!/usr/bin/env python3
"""
IP Header Test Vector Generator
Generates test vectors with known-good checksums for validation
"""

import struct
from scapy.all import IP, UDP, TCP, ICMP, Ether, Raw

def calculate_ip_checksum(header_bytes):
    """Calculate IP header checksum (16-bit one's complement)"""
    # Zero out checksum field
    header = bytearray(header_bytes)
    header[10] = 0
    header[11] = 0
    
    # Calculate checksum
    if len(header) % 2 == 1:
        header += b'\x00'
    
    total = 0
    for i in range(0, len(header), 2):
        word = (header[i] << 8) + header[i+1]
        total += word
        # Fold carry
        total = (total & 0xFFFF) + (total >> 16)
    
    checksum = ~total & 0xFFFF
    return checksum

def bytes_to_hex_string(data):
    """Convert bytes to hex string for display"""
    return ' '.join(f"{b:02X}" for b in data)

def save_test_vector(filename, frame_bytes, description):
    """Save test vector to file with metadata"""
    with open(f"test_vectors/{filename}", 'w') as f:
        f.write(f"# {description}\n")
        f.write(f"# Total bytes: {len(frame_bytes)}\n")
        f.write(f"# Hex dump:\n")
        f.write(f"# {bytes_to_hex_string(frame_bytes)}\n")
        f.write("#\n")
        
        # Write byte-by-byte
        for i, byte in enumerate(frame_bytes):
            f.write(f"{byte:02X}  # Byte {i}\n")
    
    print(f"Generated: {filename}")
    print(f"  Description: {description}")
    print(f"  Length: {len(frame_bytes)} bytes")
    print(f"  Hex: {bytes_to_hex_string(frame_bytes[:34])}")  # Show first 34 bytes
    print()

def generate_valid_udp():
    """Generate valid UDP packet"""
    pkt = Ether(dst="00:0a:35:02:af:9a", src="aa:bb:cc:dd:ee:ff") / \
          IP(src="192.168.1.10", dst="192.168.1.100", proto=17, ttl=64) / \
          UDP(sport=12345, dport=80)
    
    frame_bytes = bytes(pkt)[:34]  # MAC(14) + IP(20)
    save_test_vector("valid_udp.txt", frame_bytes, 
                    "Valid UDP: 192.168.1.10 -> 192.168.1.100")
    
    # Print parsed info
    ip_header = frame_bytes[14:34]
    print(f"  IP Version: {(ip_header[0] >> 4) & 0xF}")
    print(f"  IP IHL: {ip_header[0] & 0xF}")
    print(f"  Protocol: {ip_header[9]} (UDP)")
    print(f"  Checksum: 0x{ip_header[10]:02X}{ip_header[11]:02X}")
    print(f"  Source IP: {'.'.join(str(b) for b in ip_header[12:16])}")
    print(f"  Dest IP: {'.'.join(str(b) for b in ip_header[16:20])}")
    print()

def generate_valid_tcp():
    """Generate valid TCP packet"""
    pkt = Ether(dst="00:0a:35:02:af:9a", src="aa:bb:cc:dd:ee:ff") / \
          IP(src="10.0.0.1", dst="10.0.0.2", proto=6, ttl=64) / \
          TCP(sport=443, dport=80)
    
    frame_bytes = bytes(pkt)[:34]
    save_test_vector("valid_tcp.txt", frame_bytes,
                    "Valid TCP: 10.0.0.1 -> 10.0.0.2")

def generate_valid_icmp():
    """Generate valid ICMP packet"""
    pkt = Ether(dst="00:0a:35:02:af:9a", src="aa:bb:cc:dd:ee:ff") / \
          IP(src="8.8.8.8", dst="192.168.1.1", proto=1, ttl=64) / \
          ICMP()
    
    frame_bytes = bytes(pkt)[:34]
    save_test_vector("valid_icmp.txt", frame_bytes,
                    "Valid ICMP: 8.8.8.8 -> 192.168.1.1")

def generate_invalid_checksum():
    """Generate packet with corrupted checksum"""
    pkt = Ether(dst="00:0a:35:02:af:9a", src="aa:bb:cc:dd:ee:ff") / \
          IP(src="192.168.1.10", dst="192.168.1.100", proto=17, ttl=64) / \
          UDP()
    
    frame_bytes = bytearray(bytes(pkt)[:34])
    
    # Corrupt checksum
    frame_bytes[24] ^= 0xFF  # Flip bits in checksum field
    frame_bytes[25] ^= 0xFF
    
    save_test_vector("invalid_checksum.txt", bytes(frame_bytes),
                    "Invalid checksum (corrupted)")

def generate_invalid_version():
    """Generate packet with wrong IP version"""
    pkt = Ether(dst="00:0a:35:02:af:9a", src="aa:bb:cc:dd:ee:ff") / \
          IP(src="192.168.1.10", dst="192.168.1.100", proto=17, ttl=64) / \
          UDP()
    
    frame_bytes = bytearray(bytes(pkt)[:34])
    
    # Change version from 4 to 6
    frame_bytes[14] = (6 << 4) | (frame_bytes[14] & 0x0F)
    
    # Recalculate checksum for modified header
    ip_header = frame_bytes[14:34]
    checksum = calculate_ip_checksum(ip_header)
    frame_bytes[24] = (checksum >> 8) & 0xFF
    frame_bytes[25] = checksum & 0xFF
    
    save_test_vector("invalid_version.txt", bytes(frame_bytes),
                    "Invalid version (version=6, should be 4)")

def generate_with_options():
    """Generate packet with IP options (IHL=6)"""
    pkt = Ether(dst="00:0a:35:02:af:9a", src="aa:bb:cc:dd:ee:ff") / \
          IP(src="192.168.1.10", dst="192.168.1.100", proto=17, ttl=64, 
             options=[]) / UDP()
    
    frame_bytes = bytearray(bytes(pkt)[:34])
    
    # Change IHL from 5 to 6 (indicating 24-byte header with 4 bytes options)
    frame_bytes[14] = (frame_bytes[14] & 0xF0) | 6
    
    # Update total length (add 4 bytes for options)
    total_len = (frame_bytes[16] << 8) | frame_bytes[17]
    total_len += 4
    frame_bytes[16] = (total_len >> 8) & 0xFF
    frame_bytes[17] = total_len & 0xFF
    
    # Recalculate checksum
    ip_header = frame_bytes[14:34]
    checksum = calculate_ip_checksum(ip_header)
    frame_bytes[24] = (checksum >> 8) & 0xFF
    frame_bytes[25] = checksum & 0xFF
    
    save_test_vector("with_options.txt", bytes(frame_bytes),
                    "IP with options (IHL=6, should reject)")

def main():
    import os
    
    # Create test_vectors directory
    os.makedirs("test_vectors", exist_ok=True)
    
    print("=" * 60)
    print("IP Header Test Vector Generator")
    print("=" * 60)
    print()
    
    generate_valid_udp()
    generate_valid_tcp()
    generate_valid_icmp()
    generate_invalid_checksum()
    generate_invalid_version()
    generate_with_options()
    
    print("=" * 60)
    print("All test vectors generated successfully!")
    print("=" * 60)

if __name__ == "__main__":
    main()