#!/usr/bin/env python3
"""
UDP Test Vector Generator
Generates various UDP packets for testing the UDP parser
"""

from scapy.all import Ether, IP, UDP, TCP, Raw

def save_test_vector(filename, packet_bytes, description):
    """Save packet bytes as hex text file"""
    with open(f"test_vectors/{filename}", 'w') as f:
        f.write(f"# {description}\n")
        f.write(f"# Total length: {len(packet_bytes)} bytes\n\n")
        
        # Write hex dump
        for i in range(0, len(packet_bytes), 16):
            hex_line = ' '.join(f'{b:02x}' for b in packet_bytes[i:i+16])
            f.write(f"{i:04x}: {hex_line}\n")
    
    print(f"Generated: {filename}")
    print(f"  Description: {description}")
    print(f"  Length: {len(packet_bytes)} bytes")
    print()

def generate_valid_udp_port80():
    """Test 1: Valid UDP to port 80"""
    pkt = Ether(dst="00:0a:35:02:af:9a") / \
          IP(src="192.168.1.10", dst="192.168.1.100") / \
          UDP(sport=12345, dport=80) / \
          Raw(b"GET / HTTP/1.1\r\n")
    
    frame_bytes = bytes(pkt)
    save_test_vector("valid_udp_port80.txt", frame_bytes,
                    "Valid UDP: port 12345 -> 80, 16-byte payload")
    
    # Print parsed info
    print(f"  IP Total Length: {pkt[IP].len}")
    print(f"  UDP Length: {pkt[UDP].len}")
    print(f"  UDP Checksum: 0x{pkt[UDP].chksum:04X}")
    print()

def generate_valid_udp_port53():
    """Test 2: Valid UDP to port 53 (DNS)"""
    pkt = Ether(dst="00:0a:35:02:af:9a") / \
          IP(src="192.168.1.10", dst="192.168.1.100") / \
          UDP(sport=49320, dport=53) / \
          Raw(b"DNSQUERY")
    
    frame_bytes = bytes(pkt)
    save_test_vector("valid_udp_port53.txt", frame_bytes,
                    "Valid UDP: port 49320 -> 53 (DNS), 8-byte payload")
    
    print(f"  IP Total Length: {pkt[IP].len}")
    print(f"  UDP Length: {pkt[UDP].len}")
    print(f"  UDP Checksum: 0x{pkt[UDP].chksum:04X}")
    print()

def generate_udp_checksum_disabled():
    """Test 3: UDP with checksum = 0x0000 (disabled)"""
    pkt = Ether(dst="00:0a:35:02:af:9a") / \
          IP(src="192.168.1.10", dst="192.168.1.100") / \
          UDP(sport=4660, dport=22136, chksum=0)  # Force checksum = 0
    
    frame_bytes = bytes(pkt)
    save_test_vector("udp_checksum_disabled.txt", frame_bytes,
                    "Valid UDP: checksum=0 (disabled), no payload")
    
    print(f"  IP Total Length: {pkt[IP].len}")
    print(f"  UDP Length: {pkt[UDP].len}")
    print(f"  UDP Checksum: 0x{pkt[UDP].chksum:04X} (disabled)")
    print()

def generate_tcp_packet():
    """Test 4: TCP packet (should be ignored by UDP parser)"""
    pkt = Ether(dst="00:0a:35:02:af:9a") / \
          IP(src="192.168.1.10", dst="192.168.1.100") / \
          TCP(sport=80, dport=4660)
    
    frame_bytes = bytes(pkt)
    save_test_vector("tcp_packet.txt", frame_bytes,
                    "TCP packet (protocol=6, not UDP)")
    
    print(f"  IP Protocol: {pkt[IP].proto} (TCP)")
    print(f"  IP Total Length: {pkt[IP].len}")
    print()

def generate_udp_length_mismatch():
    """Test 5: UDP with length mismatch"""
    pkt = Ether(dst="00:0a:35:02:af:9a") / \
          IP(src="192.168.1.10", dst="192.168.1.100") / \
          UDP(sport=43981, dport=61185)
    
    frame_bytes = bytearray(bytes(pkt))
    
    # Manually corrupt UDP length field (bytes 38-39 in frame)
    # Make it claim 256 bytes when actual is only 8
    frame_bytes[38] = 0x01  # Length MSB
    frame_bytes[39] = 0x00  # Length LSB = 0x0100 = 256 bytes
    
    save_test_vector("udp_length_mismatch.txt", bytes(frame_bytes),
                    "UDP with length mismatch (claims 256, actual 8)")
    
    print(f"  IP Total Length: {pkt[IP].len}")
    print(f"  Corrupted UDP Length: 256 (invalid)")
    print()

def generate_minimum_udp():
    """Test 6: Minimum UDP packet (header only, no payload)"""
    pkt = Ether(dst="00:0a:35:02:af:9a") / \
          IP(src="192.168.1.10", dst="192.168.1.100") / \
          UDP(sport=1, dport=2)
    
    frame_bytes = bytes(pkt)
    save_test_vector("minimum_udp.txt", frame_bytes,
                    "Minimum UDP: header only (8 bytes), no payload")
    
    print(f"  IP Total Length: {pkt[IP].len}")
    print(f"  UDP Length: {pkt[UDP].len} (minimum)")
    print()

def main():
    import os
    
    # Create test_vectors directory
    os.makedirs("test_vectors", exist_ok=True)
    
    print("=" * 60)
    print("UDP Test Vector Generator")
    print("=" * 60)
    print()
    
    generate_valid_udp_port80()
    generate_valid_udp_port53()
    generate_udp_checksum_disabled()
    generate_tcp_packet()
    generate_udp_length_mismatch()
    generate_minimum_udp()
    
    print("=" * 60)
    print("All test vectors generated successfully!")
    print("=" * 60)
    print("\nFiles created in test_vectors/:")
    print("  - valid_udp_port80.txt")
    print("  - valid_udp_port53.txt")
    print("  - udp_checksum_disabled.txt")
    print("  - tcp_packet.txt")
    print("  - udp_length_mismatch.txt")
    print("  - minimum_udp.txt")
    print()
    print("Use these vectors to verify UDP parser behavior in simulation.")

if __name__ == "__main__":
    main()