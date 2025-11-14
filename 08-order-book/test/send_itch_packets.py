#!/usr/bin/env python3
"""
ITCH Message Generator and Sender (v5)
Generates ITCH 5.0 protocol messages and sends via UDP to FPGA
Automatically detects USB Ethernet interface by MAC address

Supports 9 message types:
    S - System Event
    R - Stock Directory
    A - Add Order
    E - Order Executed
    X - Order Cancel
    D - Order Delete
    U - Order Replace
    P - Trade (Non-Cross)
    Q - Cross Trade

v5 NEW Feature:
    - Symbol filtering test (--test filter_v5)
    - Tests filtered vs non-filtered symbols
    - Filter list: AAPL, TSLA, SPY, QQQ, GOOGL, MSFT, AMZN, NVDA

Requirements:
    pip install scapy

Usage Examples:
    python send_itch_packets.py --help
    python send_itch_packets.py --target 192.168.0.212 --port 12345
    python send_itch_packets.py --test add_order
    python send_itch_packets.py --test order_replace
    python send_itch_packets.py --test trade
    python send_itch_packets.py --test cross_trade
    python send_itch_packets.py --test lifecycle_v4
    python send_itch_packets.py --test all_types
    python send_itch_packets.py --test filter_v5     # NEW: Test v5 symbol filtering!
    python send_itch_packets.py --sequence 100 --delay 0.01
"""

import argparse
import struct
import random
import time
import sys
import os

# Check for Scapy
try:
    from scapy.all import Ether, IP, UDP, Raw, sendp, get_if_list
except ImportError:
    print("\n❌ ERROR: Scapy not installed")
    print("\nInstall with:")
    print("  pip3 install scapy")
    print("  or")
    print("  pip install scapy")
    sys.exit(1)

# Check for root privileges
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
PC_INTERFACE_MAC = "E8-9C-25-7A-5E-0A" # "80:3f:5d:fb:17:63"   # Your USB Ethernet MAC (to find interface)
FPGA_MAC = "00:18:3E:04:5D:E7"           # FPGA MAC address

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

    #print("\n📡 Available network interfaces:")
    for i, iface in enumerate(interfaces):
        mac = get_if_hwaddr_safe(iface)
     #  mac_str = f" (MAC: {mac})" if mac else ""
     #  marker = "  ← Your USB" if mac and mac.lower() == PC_INTERFACE_MAC.lower().replace('-', ':') else ""
     #   print(f"  {i+1}. {iface}{mac_str}{marker}")
        interface_map[i] = (iface, mac)

    # Try to auto-detect USB Ethernet by MAC
    # for i, (iface, mac) in interface_map.items():
    #     if mac and mac.lower() == PC_INTERFACE_MAC.lower().replace('-', ':'):
    #         print(f"\n✓ Auto-detected USB Ethernet: {iface} (MAC: {mac})")
    #         confirm = input("Use this interface? (y/n): ").strip().lower()
    #         if confirm == 'y':
    #             return iface, mac

    # # Manual selection if auto-detect fails
    # print("\n⚠ Could not auto-detect USB Ethernet interface")
    # print(f"   Looking for MAC: {PC_INTERFACE_MAC}")
    #print("\nPlease select interface manually:")

    while True:
        try:
            choice = 8 #input(f"Enter number (1-{len(interfaces)}): ").strip()
            idx = int(choice) - 1
            if 0 <= idx < len(interfaces):
                iface, mac = interface_map[idx]
     #           print(f"Selected: {iface} (MAC: {mac})")
                return iface, mac
            else:
                print(f"Invalid choice. Enter 1-{len(interfaces)}")
        except ValueError:
            print("Invalid input. Enter a number.")
        except KeyboardInterrupt:
            print("\n\nCancelled by user")
            sys.exit(0)

class ITCHMessageGenerator:
    """Generates ITCH 5.0 binary messages"""
    
    def __init__(self):
        self.timestamp = 0
        self.order_ref = random.randrange(1000000,9000000)
        
    def _get_timestamp(self):
        """Get 6-byte nanosecond timestamp"""
        self.timestamp += 1000000  # Increment by 1ms
        return self.timestamp
    
    def _get_order_ref(self):
        """Get unique order reference number"""
        self.order_ref += 1
        return self.order_ref
    
    def system_event(self, event_code='O'):
        """
        System Event Message (Type 'S')
        
        Args:
            event_code: Event type character
                'O' = Start of Messages
                'S' = Start of System Hours
                'Q' = Start of Market Hours
                'M' = End of Market Hours
                'E' = End of System Hours
                'C' = End of Messages
        
        Returns:
            12-byte message
        """
        msg = bytearray()
        msg.append(ord('S'))                        # Message type
        msg.extend(struct.pack('>H', 1))            # Stock locate
        msg.extend(struct.pack('>H', 0))            # Tracking number
        msg.extend(struct.pack('>Q', self._get_timestamp())[2:])  # Timestamp (48-bit)
        msg.append(ord(event_code))                 # Event code
        
        assert len(msg) == 12, f"System Event message wrong size: {len(msg)}"
        return bytes(msg)
    
    def stock_directory(self, symbol='AAPL    ', market_category='Q', 
                       round_lot_size=100):
        """
        Stock Directory Message (Type 'R')
        
        Args:
            symbol: 8-character symbol (space-padded)
            market_category: Market category character
                'Q' = Nasdaq Global Select Market
                'G' = Nasdaq Global Market
                'S' = Nasdaq Capital Market
                'N' = NYSE
                'A' = NYSE MKT
                'P' = NYSE Arca
                'Z' = BATS
                'V' = Investors Exchange
            round_lot_size: Shares per round lot (typically 100)
        
        Returns:
            39-byte message
        """
        # Ensure symbol is exactly 8 characters
        if len(symbol) < 8:
            symbol = symbol.ljust(8)
        elif len(symbol) > 8:
            symbol = symbol[:8]
        
        msg = bytearray()
        msg.append(ord('R'))                        # Message type
        msg.extend(struct.pack('>H', 1))            # Stock locate
        msg.extend(struct.pack('>H', 0))            # Tracking number
        msg.extend(struct.pack('>Q', self._get_timestamp())[2:])  # Timestamp (48-bit)
        msg.extend(symbol.encode('ascii'))          # Stock symbol (8 bytes)
        msg.append(ord(market_category))            # Market category
        msg.append(ord('N'))                        # Financial status (N = Normal)
        msg.extend(struct.pack('>I', round_lot_size))  # Round lot size
        msg.append(ord('N'))                        # Round lots only (N = No)
        msg.append(ord('C'))                        # Issue classification (C = Common Stock)
        msg.extend(b'  ')                           # Issue sub-type (2 spaces)
        msg.append(ord('P'))                        # Authenticity (P = Production/Live)
        msg.append(ord('N'))                        # Short sale threshold (N = No)
        msg.append(ord('N'))                        # IPO flag (N = No)
        msg.append(ord('1'))                        # LULD ref price tier (1 = Tier 1)
        msg.append(ord('N'))                        # ETP flag (N = Not an ETP)
        msg.extend(struct.pack('>I', 0))            # ETP leverage factor (0 = N/A)
        msg.append(ord('N'))                        # Inverse indicator (N = Not inverse)
        
        assert len(msg) == 39, f"Stock Directory message wrong size: {len(msg)}"
        return bytes(msg)
    
    
    def add_order(self, symbol='AAPL    ', buy_sell='B', shares=100, price_dollars=150.25):
        """
        Add Order Message (Type 'A')
        
        Args:
            symbol: 8-character symbol (space-padded)
            buy_sell: 'B' for Buy, 'S' for Sell
            shares: Number of shares (integer)
            price_dollars: Price in dollars (float)
        
        Returns:
            36-byte message
        """
        if len(symbol) < 8:
            symbol = symbol.ljust(8)
        
        # Convert price to 1/10000 dollars
        price_int = int(price_dollars * 10000)
        
        msg = bytearray()
        msg.append(ord('A'))                        # Message type
        msg.extend(struct.pack('>H', 1))            # Stock locate
        msg.extend(struct.pack('>H', 0))            # Tracking number
        msg.extend(struct.pack('>Q', self._get_timestamp())[2:])  # Timestamp
        msg.extend(struct.pack('>Q', self._get_order_ref()))      # Order reference
        msg.append(ord(buy_sell))                   # Buy/Sell indicator
        msg.extend(struct.pack('>I', shares))       # Shares
        msg.extend(symbol[:8].encode('ascii'))      # Stock symbol
        msg.extend(struct.pack('>I', price_int))    # Price
        
        assert len(msg) == 36, f"Add Order message wrong size: {len(msg)}"
        return bytes(msg)
    
    def display_add_order_message(self, msg_bytes):
        """
        Display Add Order message in human-readable format for debugging
        
        Args:
            msg_bytes: 36-byte Add Order message
        """
        if len(msg_bytes) != 36:
            print(f"ERROR: Message length is {len(msg_bytes)}, expected 36")
            return
        
        print("\n" + "="*80)
        print("ADD ORDER MESSAGE FORMAT (36 bytes)")
        print("="*80)
        print(f"{'Byte':<6} {'Hex':<6} {'Dec':<6} {'ASCII':<8} {'Field':<20} {'Value'}")
        print("-"*80)
        
        # Byte 0: Message type
        b = msg_bytes[0]
        print(f"{'0':<6} {b:02X}     {b:<6} {chr(b) if 32 <= b < 127 else '.':<8} {'Type':<20} {chr(b)}")
        
        # Bytes 1-2: Stock locate
        stock_locate = struct.unpack('>H', msg_bytes[1:3])[0]
        print(f"{'1-2':<6} {msg_bytes[1]:02X} {msg_bytes[2]:02X}   {'--':<6} {'--':<8} {'Stock Locate':<20} {stock_locate}")
        
        # Bytes 3-4: Tracking number
        tracking = struct.unpack('>H', msg_bytes[3:5])[0]
        print(f"{'3-4':<6} {msg_bytes[3]:02X} {msg_bytes[4]:02X}   {'--':<6} {'--':<8} {'Tracking Number':<20} {tracking}")
        
        # Bytes 5-10: Timestamp (6 bytes from 8-byte timestamp, skipping first 2)
        timestamp_bytes = b'\x00\x00' + msg_bytes[5:11]
        timestamp = struct.unpack('>Q', timestamp_bytes)[0]
        print(f"{'5-10':<6} {' '.join(f'{b:02X}' for b in msg_bytes[5:11]):<20} {'Timestamp':<20} {timestamp}")
        
        # Bytes 11-18: Order reference
        order_ref = struct.unpack('>Q', msg_bytes[11:19])[0]
        hex_str = ' '.join(f'{b:02X}' for b in msg_bytes[11:19])
        print(f"{'11-18':<6} {hex_str:<20} {'Order Reference':<20} {order_ref} (0x{order_ref:016X})")
        
        # Byte 19: Buy/Sell indicator
        b = msg_bytes[19]
        print(f"{'19':<6} {b:02X}     {b:<6} {chr(b) if 32 <= b < 127 else '.':<8} {'Buy/Sell':<20} {chr(b)}")
        
        # Bytes 20-23: Shares
        shares = struct.unpack('>I', msg_bytes[20:24])[0]
        hex_str = ' '.join(f'{b:02X}' for b in msg_bytes[20:24])
        print(f"{'20-23':<6} {hex_str:<20} {'Shares':<20} {shares}")
        
        # Bytes 24-31: Symbol (8 bytes, ASCII)
        symbol_bytes = msg_bytes[24:32]
        symbol_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in symbol_bytes)
        hex_str = ' '.join(f'{b:02X}' for b in symbol_bytes)
        ascii_str = ' '.join(chr(b) if 32 <= b < 127 else '.' for b in symbol_bytes)
        print(f"{'24-31':<6} {hex_str:<20} {'Symbol':<20} '{symbol_str}' ({ascii_str})")
        
        # Bytes 32-35: Price (4 bytes, big-endian, 1/10000 dollars)
        price_int = struct.unpack('>I', msg_bytes[32:36])[0]
        price_dollars = price_int / 10000.0
        hex_str = ' '.join(f'{b:02X}' for b in msg_bytes[32:36])
        print(f"{'32-35':<6} {hex_str:<20} {'Price':<20} {price_dollars:.4f} (${price_dollars:.2f}) = {price_int}/10000")
        
        print("="*80)
        print(f"Full message (hex): {' '.join(f'{b:02X}' for b in msg_bytes)}")
        print("="*80 + "\n")
    
    def order_executed(self, order_ref, exec_shares):
        """
        Order Executed Message (Type 'E')
        
        Args:
            order_ref: Order reference number
            exec_shares: Number of shares executed
        
        Returns:
            31-byte message
        """
        msg = bytearray()
        msg.append(ord('E'))                        # Message type
        msg.extend(struct.pack('>H', 1))            # Stock locate
        msg.extend(struct.pack('>H', 0))            # Tracking number
        msg.extend(struct.pack('>Q', self._get_timestamp())[2:])  # Timestamp
        msg.extend(struct.pack('>Q', order_ref))    # Order reference
        msg.extend(struct.pack('>I', exec_shares))  # Executed shares
        msg.extend(struct.pack('>Q', 9876543210))   # Match number
        
        assert len(msg) == 31, f"Order Executed message wrong size: {len(msg)}"
        return bytes(msg)
    
    def order_cancel(self, order_ref, cancel_shares):
        """
        Order Cancel Message (Type 'X')
        
        Args:
            order_ref: Order reference number
            cancel_shares: Number of shares cancelled
        
        Returns:
            23-byte message
        """
        msg = bytearray()
        msg.append(ord('X'))                        # Message type
        msg.extend(struct.pack('>H', 1))            # Stock locate
        msg.extend(struct.pack('>H', 0))            # Tracking number
        msg.extend(struct.pack('>Q', self._get_timestamp())[2:])  # Timestamp
        msg.extend(struct.pack('>Q', order_ref))    # Order reference
        msg.extend(struct.pack('>I', cancel_shares))  # Cancelled shares
        
        assert len(msg) == 23, f"Order Cancel message wrong size: {len(msg)}"
        return bytes(msg)
    
    def order_delete(self, order_ref):
        """
        Order Delete Message (Type 'D')

        Args:
            order_ref: Order reference number

        Returns:
            19-byte message
        """
        msg = bytearray()
        msg.append(ord('D'))                        # Message type
        msg.extend(struct.pack('>H', 1))            # Stock locate
        msg.extend(struct.pack('>H', 0))            # Tracking number
        msg.extend(struct.pack('>Q', self._get_timestamp())[2:])  # Timestamp
        msg.extend(struct.pack('>Q', order_ref))    # Order reference

        assert len(msg) == 19, f"Order Delete message wrong size: {len(msg)}"
        return bytes(msg)

    def order_replace(self, original_order_ref, new_shares, new_price_dollars):
        """
        Order Replace Message (Type 'U')

        Args:
            original_order_ref: Original order reference number
            new_shares: New number of shares
            new_price_dollars: New price in dollars (float)

        Returns:
            35-byte message
        """
        # Convert price to 1/10000 dollars
        new_price_int = int(new_price_dollars * 10000)
        new_order_ref = self._get_order_ref()

        msg = bytearray()
        msg.append(ord('U'))                        # Message type
        msg.extend(struct.pack('>H', 1))            # Stock locate
        msg.extend(struct.pack('>H', 0))            # Tracking number
        msg.extend(struct.pack('>Q', self._get_timestamp())[2:])  # Timestamp
        msg.extend(struct.pack('>Q', original_order_ref))  # Original order reference
        msg.extend(struct.pack('>Q', new_order_ref))       # New order reference
        msg.extend(struct.pack('>I', new_shares))          # New shares
        msg.extend(struct.pack('>I', new_price_int))       # New price

        assert len(msg) == 35, f"Order Replace message wrong size: {len(msg)}"
        return bytes(msg)

    def trade_non_cross(self, symbol='AAPL    ', buy_sell='B', shares=100,
                        price_dollars=150.25, match_number=None):
        """
        Trade (Non-Cross) Message (Type 'P')

        Args:
            symbol: 8-character symbol (space-padded)
            buy_sell: 'B' for Buy, 'S' for Sell
            shares: Number of shares executed
            price_dollars: Execution price in dollars (float)
            match_number: Match number (auto-generated if None)

        Returns:
            44-byte message
        """
        if len(symbol) < 8:
            symbol = symbol.ljust(8)

        # Convert price to 1/10000 dollars
        price_int = int(price_dollars * 10000)

        if match_number is None:
            match_number = random.randrange(1000000000, 9000000000)

        order_ref = self._get_order_ref()

        msg = bytearray()
        msg.append(ord('P'))                        # Message type
        msg.extend(struct.pack('>H', 1))            # Stock locate
        msg.extend(struct.pack('>H', 0))            # Tracking number
        msg.extend(struct.pack('>Q', self._get_timestamp())[2:])  # Timestamp
        msg.extend(struct.pack('>Q', order_ref))    # Order reference
        msg.append(ord(buy_sell))                   # Buy/Sell indicator
        msg.extend(struct.pack('>I', shares))       # Shares
        msg.extend(symbol[:8].encode('ascii'))      # Stock symbol
        msg.extend(struct.pack('>I', price_int))    # Price
        msg.extend(struct.pack('>Q', match_number)) # Match number

        assert len(msg) == 44, f"Trade (Non-Cross) message wrong size: {len(msg)}"
        return bytes(msg)

    def cross_trade(self, symbol='AAPL    ', shares=1000, price_dollars=150.25,
                    cross_type='O', match_number=None):
        """
        Cross Trade Message (Type 'Q')

        Args:
            symbol: 8-character symbol (space-padded)
            shares: Number of shares crossed
            price_dollars: Cross price in dollars (float)
            cross_type: Cross type character
                'O' = Opening Cross
                'C' = Closing Cross
                'H' = Cross Halted/Paused
                'I' = Intraday Cross
            match_number: Match number (auto-generated if None)

        Returns:
            40-byte message
        """
        if len(symbol) < 8:
            symbol = symbol.ljust(8)

        # Convert price to 1/10000 dollars
        price_int = int(price_dollars * 10000)

        if match_number is None:
            match_number = random.randrange(1000000000, 9000000000)

        msg = bytearray()
        msg.append(ord('Q'))                        # Message type
        msg.extend(struct.pack('>H', 1))            # Stock locate
        msg.extend(struct.pack('>H', 0))            # Tracking number
        msg.extend(struct.pack('>Q', self._get_timestamp())[2:])  # Timestamp
        msg.extend(struct.pack('>Q', shares))       # Shares (64-bit for cross trades)
        msg.extend(symbol[:8].encode('ascii'))      # Stock symbol
        msg.extend(struct.pack('>I', price_int))    # Cross price
        msg.extend(struct.pack('>Q', match_number)) # Match number
        msg.append(ord(cross_type))                 # Cross type

        assert len(msg) == 40, f"Cross Trade message wrong size: {len(msg)}"
        return bytes(msg)


def send_udp_packet(iface, target_ip, target_port, payload, src_ip=None):
    """Send UDP packet with ITCH payload"""
    # Auto-detect source IP from interface if not specified
    if src_ip is None:
        from scapy.arch import get_if_addr
        src_ip = get_if_addr(iface)
        # Fallback if interface has no IP assigned
        if src_ip == '0.0.0.0' or not src_ip:
            src_ip = '192.168.0.93'
            print(f"⚠ Interface has no IP, using default: {src_ip}")

    # Try broadcast MAC first to ensure packet reaches Arty (MAC filtering is disabled)
    # If that doesn't work, fall back to unicast
    packet = (
        Ether(dst="ff:ff:ff:ff:ff:ff") /  # Broadcast MAC - should work since MAC filtering is disabled
        IP(src=src_ip, dst=target_ip) /
        UDP(sport=54321, dport=target_port) /
        Raw(load=payload)
    )
    sendp(packet, iface=iface, verbose=False)

def test_system_event(iface,target_ip, target_port, event_code='O'):
    """Test System Event message"""
    gen = ITCHMessageGenerator()
    
    print("Testing System Event messages...")
    
    events = [
        ('O', 'Start of Messages'),
        ('S', 'Start of System Hours'),
        ('Q', 'Start of Market Hours'),
        ('M', 'End of Market Hours'),
        ('E', 'End of System Hours'),
        ('C', 'End of Messages')
    ]
    
    for event_code, description in events:
        print(f"  Sending: {description} ('{event_code}')")
        msg = gen.system_event(event_code)
        print(f"Payload: {msg.hex()}")
        send_udp_packet(iface,target_ip, target_port, msg)
        time.sleep(0.5)
    
    print("System Event test complete")


def test_stock_directory(iface, target_ip, target_port):
    """Test Stock Directory message"""
    gen = ITCHMessageGenerator()
    
    print("Testing Stock Directory messages...")
    
    stocks = [
        ('AAPL    ', 'Q', 100),
        ('GOOGL   ', 'Q', 100),
        ('MSFT    ', 'Q', 100),
        ('TSLA    ', 'Q', 100),
        ('SPY     ', 'P', 100),
        ('QQQ     ', 'Q', 100)
    ]
    
    for symbol, category, lot_size in stocks:
        print(f"  Sending: {symbol.strip()} (Market={category}, Lot={lot_size})")
        msg = gen.stock_directory(symbol, category, lot_size)
        print(f"Payload: {msg.hex()}")
        send_udp_packet(iface,target_ip, target_port, msg)
        time.sleep(0.3)
    
    print("Stock Directory test complete")


def test_market_session(iface, target_ip, target_port):
    """Test complete market session sequence"""
    gen = ITCHMessageGenerator()
    
    print("Testing complete market session...")
    
    # 1. Start of Messages
    print("1. Start of Messages")
    msg = gen.system_event('O')
    send_udp_packet(target_ip, target_port, msg)
    time.sleep(0.5)
    
    # 2. Stock Directory entries
    print("2. Stock Directory entries")
    for symbol in ['AAPL    ', 'GOOGL   ', 'MSFT    ']:
        msg = gen.stock_directory(symbol, 'Q', 100)
        send_udp_packet(target_ip, target_port, msg)
        time.sleep(0.2)
    
    # 3. Start of System Hours
    print("3. Start of System Hours")
    msg = gen.system_event('S')
    send_udp_packet(target_ip, target_port, msg)
    time.sleep(0.5)
    
    # 4. Start of Market Hours
    print("4. Start of Market Hours")
    msg = gen.system_event('Q')
    send_udp_packet(target_ip, target_port, msg)
    time.sleep(0.5)
    
    # 5. Trading activity
    print("5. Trading activity (Add Orders)")
    for i in range(5):
        msg = gen.add_order('AAPL    ', 'B', 100, 150.00 + i*0.25)
        send_udp_packet(target_ip, target_port, msg)
        time.sleep(0.1)
    
    # 6. End of Market Hours
    print("6. End of Market Hours")
    msg = gen.system_event('M')
    send_udp_packet(target_ip, target_port, msg)
    time.sleep(0.5)
    
    # 7. End of System Hours
    print("7. End of System Hours")
    msg = gen.system_event('E')
    send_udp_packet(target_ip, target_port, msg)
    time.sleep(0.5)
    
    # 8. End of Messages
    print("8. End of Messages")
    msg = gen.system_event('C')
    send_udp_packet(target_ip, target_port, msg)
    
    print("Market session test complete")


def test_single_message(iface, target_ip, target_port, msg_type='add_order'):
    """Send a single test message"""
    gen = ITCHMessageGenerator()

    if msg_type == 'system_event':
        msg = gen.system_event('O')
        print(f"Sending System Event message ({len(msg)} bytes)")
    elif msg_type == 'stock_directory':
        msg = gen.stock_directory('AAPL    ')
        print(f"Sending Stock Directory message ({len(msg)} bytes)")
    elif msg_type == 'add_order':
        msg = gen.add_order('AAPL    ', 'B', 100, 150.25)
        print(f"Sending Add Order message ({len(msg)} bytes)")
        gen.display_add_order_message(msg)
    elif msg_type == 'order_executed':
        msg = gen.order_executed(1000001, 50)
        print(f"Sending Order Executed message ({len(msg)} bytes)")
    elif msg_type == 'order_cancel':
        msg = gen.order_cancel(1000001, 25)
        print(f"Sending Order Cancel message ({len(msg)} bytes)")
    elif msg_type == 'order_delete':
        msg = gen.order_delete(1000001)
        print(f"Sending Order Delete message ({len(msg)} bytes)")
    elif msg_type == 'order_replace':
        msg = gen.order_replace(1000001, 200, 151.50)
        print(f"Sending Order Replace message ({len(msg)} bytes)")
    elif msg_type == 'trade':
        msg = gen.trade_non_cross('AAPL    ', 'B', 100, 150.25)
        print(f"Sending Trade (Non-Cross) message ({len(msg)} bytes)")
    elif msg_type == 'cross_trade':
        msg = gen.cross_trade('AAPL    ', 1000, 150.00, 'O')
        print(f"Sending Cross Trade message ({len(msg)} bytes)")
    else:
        print(f"Unknown message type: {msg_type}")
        return

    # Display message in hex
    print(f"Payload: {msg.hex()}")

    # Send packet
    send_udp_packet(iface, target_ip, target_port, msg)
    print("Packet sent successfully")


def test_sequence(iface, target_ip, target_port, count=10, delay=0.1):
    """Send a sequence of ITCH messages"""
    gen = ITCHMessageGenerator()

    print(f"Sending sequence of {count} messages with {delay}s delay...")

    for i in range(count):
        # Vary message types
        if i % 10 == 0:
            msg = gen.system_event('O')
            msg_type = 'System Event'
        elif i % 10 == 1:
            msg = gen.stock_directory('AAPL    ')
            msg_type = 'Stock Directory'
        elif i % 3 == 0:
            msg = gen.add_order('AAPL    ', 'B', 100 + i, 150.00 + i*0.01)
            msg_type = 'Add Order'
            if i == 0:  # Display format for first message only
                gen.display_add_order_message(msg)
        elif i % 3 == 1:
            msg = gen.order_executed(1000001 + i, 50)
            msg_type = 'Order Executed'
        else:
            msg = gen.order_cancel(1000001 + i, 25)
            msg_type = 'Order Cancel'

        print(f"[{i+1}/{count}] Sending {msg_type}...")
        print(f"Payload: {msg.hex()}")
        send_udp_packet(iface, target_ip, target_port, msg)
        time.sleep(delay)

    print(f"Sequence complete: {count} messages sent")


def test_order_lifecycle(iface, target_ip, target_port):
    """Send complete order lifecycle: Add -> Execute -> Cancel -> Delete"""
    gen = ITCHMessageGenerator()

    print("Testing order lifecycle...")

    # Add order
    print("1. Adding order for 100 shares AAPL...")
    order_ref = gen.order_ref + 1
    msg = gen.add_order('AAPL    ', 'B', 100, 150.25)
    gen.display_add_order_message(msg)
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)

    # Partial execution
    print("2. Executing 50 shares...")
    msg = gen.order_executed(order_ref, 50)
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)

    # Partial cancel
    print("3. Cancelling 25 shares...")
    msg = gen.order_cancel(order_ref, 25)
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)

    # Delete remaining
    print("4. Deleting remaining order...")
    msg = gen.order_delete(order_ref)
    send_udp_packet(iface, target_ip, target_port, msg)

    print("Order lifecycle test complete")


def test_order_lifecycle_v4(iface, target_ip, target_port):
    """Send complete v4 order lifecycle: Add -> Replace -> Execute -> Delete + Trade + Cross"""
    gen = ITCHMessageGenerator()

    print("Testing v4 extended order lifecycle...")

    # Add order
    print("1. Adding order for 100 shares AAPL @ $150.25...")
    order_ref = gen.order_ref + 1
    msg = gen.add_order('AAPL    ', 'B', 100, 150.25)
    print(f"   Payload: {msg.hex()}")
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)

    # Replace order (U message)
    print("2. Replacing order: 200 shares @ $151.50...")
    msg = gen.order_replace(order_ref, 200, 151.50)
    print(f"   Payload: {msg.hex()}")
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)

    # Partial execution
    print("3. Executing 100 shares...")
    msg = gen.order_executed(gen.order_ref, 100)
    print(f"   Payload: {msg.hex()}")
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)

    # Trade message (P message)
    print("4. Trade execution: 50 shares TSLA @ $200.00...")
    msg = gen.trade_non_cross('TSLA    ', 'S', 50, 200.00)
    print(f"   Payload: {msg.hex()}")
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)

    # Cross trade (Q message)
    print("5. Opening cross: 1000 shares GOOGL @ $2500.00...")
    msg = gen.cross_trade('GOOGL   ', 1000, 2500.00, 'O')
    print(f"   Payload: {msg.hex()}")
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.5)

    # Delete remaining
    print("6. Deleting remaining order...")
    msg = gen.order_delete(gen.order_ref)
    print(f"   Payload: {msg.hex()}")
    send_udp_packet(iface, target_ip, target_port, msg)

    print("\nv4 order lifecycle test complete")
    print("✓ Tested: D (Delete), U (Replace), P (Trade), Q (Cross)")


def test_all_message_types(iface, target_ip, target_port):
    """Send one message of each type supported in v4"""
    gen = ITCHMessageGenerator()

    print("Testing all v4 message types...\n")

    message_types = [
        ('S', 'System Event', lambda: gen.system_event('O')),
        ('R', 'Stock Directory', lambda: gen.stock_directory('AAPL    ')),
        ('A', 'Add Order', lambda: gen.add_order('AAPL    ', 'B', 100, 150.25)),
        ('E', 'Order Executed', lambda: gen.order_executed(1000001, 50)),
        ('X', 'Order Cancel', lambda: gen.order_cancel(1000001, 25)),
        ('D', 'Order Delete', lambda: gen.order_delete(1000001)),
        ('U', 'Order Replace', lambda: gen.order_replace(1000001, 200, 151.50)),
        ('P', 'Trade (Non-Cross)', lambda: gen.trade_non_cross('AAPL    ', 'B', 100, 150.25)),
        ('Q', 'Cross Trade', lambda: gen.cross_trade('AAPL    ', 1000, 150.00, 'O'))
    ]

    for i, (type_code, type_name, msg_func) in enumerate(message_types, 1):
        print(f"{i}. Sending {type_name} ('{type_code}')...")
        msg = msg_func()
        print(f"   Size: {len(msg)} bytes")
        print(f"   Payload: {msg.hex()}")
        send_udp_packet(iface, target_ip, target_port, msg)
        time.sleep(0.3)

    print("\n✓ All message types test complete")
    print("  Tested 9 message types: S, R, A, E, X, D, U, P, Q")


def test_multiple_symbols(iface, target_ip, target_port):
    """Send orders for multiple symbols"""
    gen = ITCHMessageGenerator()

    symbols = ['AAPL    ', 'GOOGL   ', 'MSFT    ', 'TSLA    ', 'AMZN    ']

    print(f"Testing multiple symbols: {symbols}")

    for i, symbol in enumerate(symbols):
        print(f"Sending order for {symbol.strip()}...")
        msg = gen.add_order(symbol, 'B', 100, 150.00)
        if i == 0:  # Display format for first symbol only
            gen.display_add_order_message(msg)
        send_udp_packet(iface, target_ip, target_port, msg)
        time.sleep(0.2)

    print("Multiple symbol test complete")


def test_symbol_filtering_v5(iface, target_ip, target_port):
    """
    Test v5 symbol filtering feature

    v5 Filter List (ENABLE_SYMBOL_FILTER = true):
        AAPL, TSLA, SPY, QQQ, GOOGL, MSFT, AMZN, NVDA

    This test sends:
    - Messages with FILTERED symbols (should appear in UART output)
    - Messages with NON-FILTERED symbols (should NOT appear in UART output)
    - Messages without symbols (should always appear)

    Expected Results:
    - Total messages counter increments for ALL messages
    - Filtered messages counter increments ONLY for matched symbols
    - UART output shows ONLY filtered symbols (or non-symbol messages)
    """
    gen = ITCHMessageGenerator()

    print("=" * 60)
    print("Testing v5 Symbol Filtering Feature")
    print("=" * 60)
    print("\nFilter List (8 symbols): AAPL, TSLA, SPY, QQQ, GOOGL, MSFT, AMZN, NVDA")
    print("\n" + "=" * 60)

    # Part 1: Send FILTERED symbols (should appear)
    filtered_symbols = ['AAPL    ', 'TSLA    ', 'SPY     ', 'QQQ     ',
                        'GOOGL   ', 'MSFT    ', 'AMZN    ', 'NVDA    ']

    print("\nPart 1: Sending FILTERED symbols (should appear in UART)")
    print("-" * 60)
    for i, symbol in enumerate(filtered_symbols, 1):
        print(f"{i}. Sending Add Order for {symbol.strip()}...")
        msg = gen.add_order(symbol, 'B', 100, 150.00 + i)
        send_udp_packet(iface, target_ip, target_port, msg)
        time.sleep(0.3)

    print(f"\n✓ Sent {len(filtered_symbols)} FILTERED symbol messages")
    print("  Expected: All 8 should appear in UART output")
    time.sleep(1)

    # Part 2: Send NON-FILTERED symbols (should NOT appear)
    non_filtered_symbols = ['IBM     ', 'INTC    ', 'AMD     ', 'NFLX    ', 'META    ']

    print("\nPart 2: Sending NON-FILTERED symbols (should NOT appear in UART)")
    print("-" * 60)
    for i, symbol in enumerate(non_filtered_symbols, 1):
        print(f"{i}. Sending Add Order for {symbol.strip()}...")
        msg = gen.add_order(symbol, 'B', 100, 200.00 + i)
        send_udp_packet(iface, target_ip, target_port, msg)
        time.sleep(0.3)

    print(f"\n✓ Sent {len(non_filtered_symbols)} NON-FILTERED symbol messages")
    print("  Expected: NONE should appear in UART output (filtered out)")
    time.sleep(1)

    # Part 3: Send messages WITHOUT symbols (should always appear)
    print("\nPart 3: Sending messages WITHOUT symbols (should always appear)")
    print("-" * 60)

    print("1. Sending System Event (no symbol)...")
    msg = gen.system_event('O')
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.3)

    print("2. Sending Order Executed (no symbol)...")
    msg = gen.order_executed(12345678, 50)
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.3)

    print("3. Sending Order Cancel (no symbol)...")
    msg = gen.order_cancel(12345678, 25)
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.3)

    print("4. Sending Order Delete (no symbol)...")
    msg = gen.order_delete(12345678)
    send_udp_packet(iface, target_ip, target_port, msg)
    time.sleep(0.3)

    print("\n✓ Sent 4 non-symbol messages")
    print("  Expected: All 4 should appear (no filtering for non-symbol messages)")

    # Summary
    total_sent = len(filtered_symbols) + len(non_filtered_symbols) + 4
    expected_output = len(filtered_symbols) + 4  # Filtered symbols + non-symbol messages
    expected_filtered_out = len(non_filtered_symbols)

    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)
    print(f"Total messages sent:           {total_sent}")
    print(f"  - Filtered symbols:          {len(filtered_symbols)} (AAPL, TSLA, SPY, QQQ, GOOGL, MSFT, AMZN, NVDA)")
    print(f"  - Non-filtered symbols:      {len(non_filtered_symbols)} (IBM, INTC, AMD, NFLX, META)")
    print(f"  - Non-symbol messages:       4 (S, E, X, D)")
    print()
    print(f"Expected UART output count:    {expected_output} messages")
    print(f"Expected filtered out:         {expected_filtered_out} messages")
    print()
    print("Check your UART output:")
    print("  - Should see: AAPL, TSLA, SPY, QQQ, GOOGL, MSFT, AMZN, NVDA + S, E, X, D")
    print("  - Should NOT see: IBM, INTC, AMD, NFLX, META")
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description='ITCH Message Generator and Sender',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument('--target', default='192.168.0.212',
                       help='Target FPGA IP address (default: 192.168.0.212)')
    parser.add_argument('--port', type=int, default=12345,
                       help='Target UDP port (default: 12345)')
    parser.add_argument('--test', choices=['add_order', 'order_executed', 'order_cancel',
                                          'order_delete', 'order_replace', 'trade', 'cross_trade',
                                          'system_event', 'stock_directory',
                                          'lifecycle', 'lifecycle_v4', 'symbols', 'all_types',
                                          'filter_v5'],
                       help='Send single test message')
    parser.add_argument('--sequence', type=int, metavar='COUNT',
                       help='Send sequence of COUNT messages')
    parser.add_argument('--delay', type=float, default=0.1,
                       help='Delay between sequence messages in seconds (default: 0.1)')

    args = parser.parse_args()

    # Find USB Ethernet interface
    iface, mac = find_interface()
    if not iface:
        print("\n❌ ERROR: No interface selected")
        sys.exit(1)

   # print(f"\n✓ Using interface: {iface}")
    print(f"  Target: {args.target}:{args.port}")
    print()

    if args.test:
        if args.test == 'system_event':
            test_system_event(iface, args.target, args.port)
        elif args.test == 'stock_directory':
            test_stock_directory(iface, args.target, args.port)
        elif args.test == 'market_session':
            test_market_session(iface, args.target, args.port)
        elif args.test == 'lifecycle':
            test_order_lifecycle(iface, args.target, args.port)
        elif args.test == 'lifecycle_v4':
            test_order_lifecycle_v4(iface, args.target, args.port)
        elif args.test == 'symbols':
            test_multiple_symbols(iface, args.target, args.port)
        elif args.test == 'all_types':
            test_all_message_types(iface, args.target, args.port)
        elif args.test == 'filter_v5':
            test_symbol_filtering_v5(iface, args.target, args.port)
        elif args.test == 'add_order':
            gen = ITCHMessageGenerator()
            msg = gen.add_order('AAPL    ', 'B', 100, 150.00)
            send_udp_packet(iface, args.target, args.port, msg)
            gen.display_add_order_message(msg)
            print("Sent Add Order message")
        elif args.test == 'order_executed':
            gen = ITCHMessageGenerator()
            msg = gen.order_executed(12345678, 50)
            send_udp_packet(iface, args.target, args.port, msg)
            print("Sent Order Executed message")
        elif args.test == 'order_cancel':
            gen = ITCHMessageGenerator()
            msg = gen.order_cancel(12345678, 25)
            send_udp_packet(iface, args.target, args.port, msg)
            print("Sent Order Cancel message")
        elif args.test == 'order_delete':
            gen = ITCHMessageGenerator()
            msg = gen.order_delete(12345678)
            send_udp_packet(iface, args.target, args.port, msg)
            print("Sent Order Delete message")
        elif args.test == 'order_replace':
            gen = ITCHMessageGenerator()
            msg = gen.order_replace(12345678, 200, 151.50)
            send_udp_packet(iface, args.target, args.port, msg)
            print(f"Sent Order Replace message ({len(msg)} bytes)")
            print(f"Payload: {msg.hex()}")
        elif args.test == 'trade':
            gen = ITCHMessageGenerator()
            msg = gen.trade_non_cross('AAPL    ', 'B', 100, 150.25)
            send_udp_packet(iface, args.target, args.port, msg)
            print(f"Sent Trade (Non-Cross) message ({len(msg)} bytes)")
            print(f"Payload: {msg.hex()}")
        elif args.test == 'cross_trade':
            gen = ITCHMessageGenerator()
            msg = gen.cross_trade('AAPL    ', 1000, 150.00, 'O')
            send_udp_packet(iface, args.target, args.port, msg)
            print(f"Sent Cross Trade message ({len(msg)} bytes)")
            print(f"Payload: {msg.hex()}")
    elif args.sequence:
        test_sequence(iface, args.target, args.port, args.sequence, args.delay)
    elif args.system_event:
        test_system_event (iface, args.target, args.port, args.system_event)
    elif args.stock_directory:
        test_stock_directory(iface, args.target, args.port, args.stock_directory)
    elif args.market_session:
        test_market_session(iface, args.target, args.port, args.market_session)
    elif args.add_order:
        gen = ITCHMessageGenerator()
        msg = gen.add_order('AAPL    ', 'B', 100, 150.00)
        send_udp_packet(iface, args.target, args.port, msg)
        print("Sent Add Order message")
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
