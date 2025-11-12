#!/usr/bin/env python3
"""
itch_replay.py - Replay ITCH messages from database to FPGA via UDP
Updated to support FPGA-implemented message types: A, E, X, S, R, D, U, P, Q

Usage: python itch_replay.py database.db --fpga-ip 192.168.0.201 --symbol AAPL
"""

import sqlite3
import time
import argparse
import sys
from datetime import datetime

# Import Scapy for raw Ethernet packet sending (required for FPGA)
try:
    from scapy.all import Ether, IP, UDP, Raw, sendp
    from scapy.arch import get_if_hwaddr
except ImportError:
    print("\n❌ ERROR: Scapy not installed")
    print("\nInstall with: pip install scapy")
    sys.exit(1)

# Configuration - match working send_itch_packets.py
PC_INTERFACE_MAC = "E8-9C-25-7A-5E-0A"  # Your USB Ethernet MAC
FPGA_MAC = "ff:ff:ff:ff:ff:ff"          # Broadcast (same as working scripts)
# FPGA_MAC = "00:18:3E:04:5D:E7"        # FPGA unicast MAC (doesn't work for some reason)

def find_interface_by_mac(target_mac):
    """Find network interface by MAC address"""
    from scapy.all import get_if_list
    target_mac_normalized = target_mac.lower().replace('-', ':')

    for iface in get_if_list():
        try:
            mac = get_if_hwaddr(iface)
            if mac and mac.lower() == target_mac_normalized:
                return iface
        except:
            continue
    return None

class ITCHReplayer:
    # FPGA-implemented message types
    FPGA_MESSAGE_TYPES = ['A', 'E', 'X', 'S', 'R', 'D', 'U', 'P', 'Q']

    def __init__(self, db_path, fpga_ip, fpga_port=12345, interface=None):
        self.db = sqlite3.connect(db_path)
        self.db.row_factory = sqlite3.Row
        self.fpga_ip = fpga_ip
        self.fpga_port = fpga_port

        # Find network interface
        if interface is None:
            self.iface = find_interface_by_mac(PC_INTERFACE_MAC)
            if not self.iface:
                print(f"\n❌ ERROR: Could not find interface with MAC {PC_INTERFACE_MAC}")
                print("\nAvailable interfaces:")
                from scapy.all import get_if_list
                for iface in get_if_list():
                    try:
                        mac = get_if_hwaddr(iface)
                        print(f"  {iface}: {mac}")
                    except:
                        pass
                sys.exit(1)
        else:
            self.iface = interface

        print(f"Using interface: {self.iface}")
        
    def replay_symbol(self, symbol, speed_multiplier=1.0, message_types=None, 
                     max_messages=None):
        """
        Replay messages for specific symbol
        
        Args:
            symbol: Stock symbol (e.g., 'AAPL')
            speed_multiplier: 1.0 = real-time, 10.0 = 10x speed, 0.0 = max speed
            message_types: List of message types to replay (None = all FPGA types)
            max_messages: Maximum number of messages to send (None = unlimited)
        """
        # Default to FPGA-implemented types only
        if message_types is None:
            message_types = self.FPGA_MESSAGE_TYPES
        else:
            # Validate message types
            invalid = [t for t in message_types if t not in self.FPGA_MESSAGE_TYPES]
            if invalid:
                print(f"Warning: Message types {invalid} not implemented in FPGA")
                message_types = [t for t in message_types if t in self.FPGA_MESSAGE_TYPES]
        
        # Build query
        placeholders = ','.join('?' * len(message_types))
        query = f"""
            SELECT * FROM itch_messages 
            WHERE stock_symbol = ? 
            AND message_type IN ({placeholders})
            ORDER BY timestamp_ns
        """
        
        if max_messages:
            query += f" LIMIT {max_messages}"

        # Ensure symbol is uppercase (ITCH standard)
        symbol_upper = symbol.upper()
        params = [symbol_upper] + list(message_types)

        cursor = self.db.cursor()
        cursor.execute(query, params)

        print(f"Replaying {symbol_upper} to {self.fpga_ip}:{self.fpga_port}")
        print(f"Message types: {', '.join(message_types)}")
        print(f"Speed: {speed_multiplier}x" if speed_multiplier > 0 else "Speed: MAXIMUM")
        
        count = 0
        type_counts = {t: 0 for t in message_types}
        last_timestamp = None
        start_time = time.time()
        last_display = start_time
        
        for row in cursor:
            # Rate limiting based on timestamps
            if speed_multiplier > 0 and last_timestamp:
                time_delta_ns = row['timestamp_ns'] - last_timestamp
                sleep_sec = (time_delta_ns / 1e9) / speed_multiplier
                # Cap sleep to max 0.1 second to handle large gaps in market data
                sleep_sec = min(sleep_sec, 0.1)
                if sleep_sec > 0:
                    time.sleep(sleep_sec)

            # Send raw message via UDP using Scapy (same as send_itch_packets.py)
            payload = bytearray(row['raw_message'])

            # Convert symbol bytes to uppercase (bytes 24-31 for most message types)
            # Symbol is 8 bytes starting at offset 24 for Add Order, Execute, Cancel, etc.
            msg_type = payload[0]
            if msg_type in [ord('A'), ord('E'), ord('X'), ord('D'), ord('U'), ord('P'), ord('Q')]:
                # Symbol at offset 24-31 (8 bytes)
                for i in range(24, min(32, len(payload))):
                    if ord('a') <= payload[i] <= ord('z'):
                        payload[i] = payload[i] - 32  # Convert to uppercase

            payload = bytes(payload.upper())  # Convert back to immutable bytes

            # Debug: Print payload hex
            print(f"\n[MSG {count+1}] Type: {row['message_type']}, Length: {len(payload)} bytes")
            print(f"Payload: {payload.hex()}")

            packet = (
                Ether(dst=FPGA_MAC) /
                IP(dst=self.fpga_ip) /
                UDP(sport=54321, dport=self.fpga_port) /
                Raw(load=payload.upper())
            )
            sendp(packet, iface=self.iface, verbose=False)

            count += 1
            type_counts[row['message_type']] += 1
            last_timestamp = row['timestamp_ns']

            # Progress display (every second)
            now = time.time()
            if now - last_display >= 1.0:
                elapsed = now - start_time
                rate = count / elapsed if elapsed > 0 else 0
                print(f"  Sent {count:,} messages ({rate:.0f} msg/sec)", end='\r')
                last_display = now
                
        elapsed = time.time() - start_time
        print(f"\n\nCompleted: {count:,} messages in {elapsed:.1f} seconds")
        print(f"Average rate: {count/elapsed:.0f} messages/second")
        print("\nBreakdown by type:")
        for msg_type, cnt in sorted(type_counts.items()):
            if cnt > 0:
                print(f"  {msg_type}: {cnt:,}")
        
    def replay_all_types(self, symbol, speed_multiplier=1.0, max_messages=None):
        """Replay all FPGA-supported message types for a symbol"""
        return self.replay_symbol(symbol, speed_multiplier, 
                                 self.FPGA_MESSAGE_TYPES, max_messages)
    
    def replay_time_range(self, start_ns, end_ns, symbols=None, message_types=None):
        """
        Replay messages in timestamp range
        
        Args:
            start_ns: Start timestamp (nanoseconds)
            end_ns: End timestamp (nanoseconds)
            symbols: List of symbols (None = all)
            message_types: List of types (None = all FPGA types)
        """
        if message_types is None:
            message_types = self.FPGA_MESSAGE_TYPES
            
        placeholders_types = ','.join('?' * len(message_types))
        
        if symbols:
            placeholders_symbols = ','.join('?' * len(symbols))
            query = f"""
                SELECT * FROM itch_messages 
                WHERE timestamp_ns BETWEEN ? AND ? 
                AND stock_symbol IN ({placeholders_symbols})
                AND message_type IN ({placeholders_types})
                ORDER BY timestamp_ns
            """
            params = [start_ns, end_ns] + list(symbols) + list(message_types)
        else:
            query = f"""
                SELECT * FROM itch_messages 
                WHERE timestamp_ns BETWEEN ? AND ?
                AND message_type IN ({placeholders_types})
                ORDER BY timestamp_ns
            """
            params = [start_ns, end_ns] + list(message_types)
        
        cursor = self.db.cursor()
        cursor.execute(query, params)
        
        count = 0
        for row in cursor:
            self.sock.sendto(row['raw_message'], self.fpga_addr)
            count += 1
            
        print(f"Sent {count:,} messages from time range")
        
    def get_symbols(self, min_messages=100, message_types=None):
        """
        Get list of symbols with at least min_messages
        
        Args:
            min_messages: Minimum message count
            message_types: Filter by message types (None = all FPGA types)
        """
        if message_types is None:
            message_types = self.FPGA_MESSAGE_TYPES
            
        placeholders = ','.join('?' * len(message_types))
        
        cursor = self.db.cursor()
        cursor.execute(f'''
            SELECT stock_symbol, message_type, COUNT(*) as count
            FROM itch_messages
            WHERE stock_symbol IS NOT NULL
            AND message_type IN ({placeholders})
            GROUP BY stock_symbol, message_type
            ORDER BY stock_symbol, message_type
        ''', message_types)
        
        # Aggregate by symbol
        symbol_stats = {}
        for row in cursor.fetchall():
            symbol = row[0]
            msg_type = row[1]
            count = row[2]
            
            if symbol not in symbol_stats:
                symbol_stats[symbol] = {'total': 0, 'types': {}}
            
            symbol_stats[symbol]['total'] += count
            symbol_stats[symbol]['types'][msg_type] = count
        
        # Filter by minimum and sort
        result = [(sym, stats['total'], stats['types']) 
                  for sym, stats in symbol_stats.items() 
                  if stats['total'] >= min_messages]
        result.sort(key=lambda x: x[1], reverse=True)
        
        return result
    
    def get_time_range(self):
        """Get first and last timestamps in database"""
        cursor = self.db.cursor()
        cursor.execute('''
            SELECT MIN(timestamp_ns) as first_ts, 
                   MAX(timestamp_ns) as last_ts,
                   (MAX(timestamp_ns) - MIN(timestamp_ns)) / 1e9 / 3600 as hours
            FROM itch_messages
        ''')
        row = cursor.fetchone()
        return row[0], row[1], row[2]
    
    def get_message_stats(self):
        """Get overall message statistics"""
        cursor = self.db.cursor()
        cursor.execute('''
            SELECT message_type, COUNT(*) as count
            FROM itch_messages
            GROUP BY message_type
            ORDER BY count DESC
        ''')
        return cursor.fetchall()
        
    def close(self):
        self.db.close()
        # No need to close Scapy socket - it's stateless

def format_timestamp(ts_ns):
    """Convert nanosecond timestamp to human-readable format"""
    ts_sec = ts_ns / 1e9
    dt = datetime.fromtimestamp(ts_sec)
    return dt.strftime('%Y-%m-%d %H:%M:%S')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Replay ITCH messages from database to FPGA',
        epilog='Example: python itch_replay.py data.db --fpga-ip 192.168.1.10 --symbol AAPL --speed 10'
    )
    parser.add_argument('database', help='SQLite database file')
    parser.add_argument('--fpga-ip', required=True, help='FPGA IP address')
    parser.add_argument('--fpga-port', type=int, default=1234, 
                       help='FPGA UDP port (default: 1234)')
    parser.add_argument('--symbol', help='Stock symbol to replay (e.g., AAPL)')
    parser.add_argument('--speed', type=float, default=1.0, 
                       help='Speed multiplier (0=max, 1=realtime, 10=10x)')
    parser.add_argument('--types', 
                       help='Message types to replay (e.g., "A,E,X" or "all" for all FPGA types)')
    parser.add_argument('--max-messages', type=int,
                       help='Maximum number of messages to send')
    parser.add_argument('--list-symbols', action='store_true', 
                       help='List available symbols')
    parser.add_argument('--stats', action='store_true',
                       help='Show database statistics')
    parser.add_argument('--time-info', action='store_true',
                       help='Show time range in database')
    
    args = parser.parse_args()
    
    replayer = ITCHReplayer(args.database, args.fpga_ip, args.fpga_port)
    
    try:
        if args.stats:
            print("Database Statistics:")
            print("-" * 50)
            stats = replayer.get_message_stats()
            total = sum(s[1] for s in stats)
            print(f"Total messages: {total:,}\n")
            for msg_type, count in stats:
                pct = (count / total) * 100
                fpga = "✓" if msg_type in ITCHReplayer.FPGA_MESSAGE_TYPES else " "
                print(f"  [{fpga}] {msg_type}: {count:,} ({pct:.1f}%)")
            print("\n✓ = Implemented in FPGA")
            
        elif args.time_info:
            first, last, hours = replayer.get_time_range()
            print("Time Range in Database:")
            print("-" * 50)
            print(f"First message: {format_timestamp(first)}")
            print(f"Last message:  {format_timestamp(last)}")
            print(f"Duration: {hours:.2f} hours")
            
        elif args.list_symbols:
            types = None
            if args.types and args.types != 'all':
                types = args.types.split(',')
            
            print("Available Symbols (FPGA-supported messages only):")
            print("-" * 70)
            symbols = replayer.get_symbols(message_types=types)
            
            for symbol, total, type_counts in symbols[:30]:  # Top 30
                type_str = ' '.join([f"{t}:{c}" for t, c in sorted(type_counts.items())])
                print(f"  {symbol:8s} {total:8,} messages  [{type_str}]")
            
            if len(symbols) > 30:
                print(f"\n  ... and {len(symbols) - 30} more symbols")
                
        elif args.symbol:
            types = ITCHReplayer.FPGA_MESSAGE_TYPES
            if args.types and args.types != 'all':
                types = args.types.split(',')
            
            replayer.replay_symbol(args.symbol, args.speed, types, args.max_messages)
        else:
            print("Error: Specify --symbol, --list-symbols, --stats, or --time-info")
            parser.print_help()
    finally:
        replayer.close()