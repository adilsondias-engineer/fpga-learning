#!/usr/bin/env python3
"""
Simple ITCH packet sender using standard Python sockets (no Scapy needed)
Workaround for when Scapy/Npcap is broken after VS upgrades
"""
import socket
import struct
import time
import random

class SimpleITCHSender:
    def __init__(self, target_ip='192.168.0.201', target_port=12345):
        self.target_ip = target_ip
        self.target_port = target_port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.timestamp = 0

    def _get_timestamp(self):
        """Get incrementing timestamp"""
        self.timestamp += 1000
        return self.timestamp

    def add_order(self, symbol, side, shares, price_dollars, order_ref=None):
        """
        Create ITCH Add Order message (Type 'A')

        Args:
            symbol: Stock symbol (max 8 chars)
            side: 'B' for buy, 'S' for sell
            shares: Number of shares
            price_dollars: Price in dollars (will convert to 1/10000)
            order_ref: Order reference number (auto-generated if None)

        Returns:
            36-byte message
        """
        if len(symbol) < 8:
            symbol = symbol.ljust(8)

        # Convert price to 1/10000 dollars
        price_int = int(price_dollars * 10000)

        if order_ref is None:
            order_ref = random.randrange(1000000, 9999999)

        msg = bytearray()
        msg.append(ord('A'))                        # Message type
        msg.extend(struct.pack('>H', 1))            # Stock locate
        msg.extend(struct.pack('>H', 0))            # Tracking number
        msg.extend(struct.pack('>Q', self._get_timestamp())[2:])  # Timestamp (48-bit)
        msg.extend(struct.pack('>Q', order_ref))    # Order ref number
        msg.append(ord(side))                       # Buy/Sell indicator
        msg.extend(struct.pack('>I', shares))       # Shares
        msg.extend(symbol[:8].encode('ascii'))      # Stock symbol
        msg.extend(struct.pack('>I', price_int))    # Price

        assert len(msg) == 36, f"Add Order message wrong size: {len(msg)}"
        return bytes(msg)

    def send(self, payload):
        """Send UDP packet"""
        self.sock.sendto(payload, (self.target_ip, self.target_port))
        print(f"✓ Sent {len(payload)} bytes to {self.target_ip}:{self.target_port}")


def test_order_book():
    """Test order book with simple socket-based sender"""
    sender = SimpleITCHSender(target_ip='192.168.0.201', target_port=12345)

    print("=" * 70)
    print("SIMPLE ORDER BOOK TEST (No Scapy)")
    print("=" * 70)
    print(f"Target: {sender.target_ip}:{sender.target_port}")
    print()

    # Test 1: Build order book
    print("Sending BID orders...")
    bids = [(150.00, 100), (149.75, 200), (150.25, 150), (149.50, 300)]
    for i, (price, shares) in enumerate(bids, 1):
        print(f"  {i}. Bid ${price:.2f}, {shares} shares")
        msg = sender.add_order('AAPL    ', 'B', shares, price)
        sender.send(msg)
        time.sleep(0.5)

    print("\nSending ASK orders...")
    asks = [(151.00, 100), (151.50, 200), (150.75, 150), (152.00, 300)]
    for i, (price, shares) in enumerate(asks, 1):
        print(f"  {i}. Ask ${price:.2f}, {shares} shares")
        msg = sender.add_order('AAPL    ', 'S', shares, price)
        sender.send(msg)
        time.sleep(0.5)

    print("\n" + "=" * 70)
    print("EXPECTED BBO: Bid $150.25, Ask $150.75, Spread $0.50")
    print("Check FPGA UART output in debug mode 00 or 11")
    print("=" * 70)


if __name__ == '__main__':
    print("\nThis script uses standard Python sockets (no Scapy/Npcap needed)")
    print("It sends UDP packets directly - should work even if Scapy is broken\n")

    input("Press Enter to start test...")
    test_order_book()
