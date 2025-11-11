#!/usr/bin/env python3
"""
itch_to_db.py - Parse NASDAQ ITCH 5.0 file into SQLite database
Updated to support all FPGA-implemented message types: A, E, X, S, R, D, U, P, Q

Usage: python itch_to_db.py NASDAQ_ITCH50_file.bin output.db [max_messages]
"""

import struct
import sqlite3
import sys
import time
from pathlib import Path

class ITCHParser:
    def __init__(self, db_path):
        self.db = sqlite3.connect(db_path)
        self.cursor = self.db.cursor()
        self.create_schema()
        self.batch = []
        self.batch_size = 10000  # Commit every 10K messages
        self.stats = {'total': 0, 'by_type': {}}
        
        # Performance optimizations
        self.cursor.execute("PRAGMA synchronous = OFF")
        self.cursor.execute("PRAGMA journal_mode = MEMORY")
        self.cursor.execute("PRAGMA cache_size = 100000")
        
    def create_schema(self):
        """Create database tables and indexes"""
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS itch_messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp_ns INTEGER NOT NULL,
                message_type CHAR(1) NOT NULL,
                stock_locate INTEGER,
                stock_symbol CHAR(8),
                
                -- Add Order (A) fields
                order_ref_num INTEGER,
                buy_sell CHAR(1),
                shares INTEGER,
                price INTEGER,
                
                -- Order Executed (E) fields
                executed_shares INTEGER,
                match_number INTEGER,
                
                -- Order Cancel (X) fields
                cancelled_shares INTEGER,
                
                -- Order Delete (D) - just order_ref_num
                
                -- Order Replace (U) fields
                original_order_ref INTEGER,
                new_order_ref INTEGER,
                new_shares INTEGER,
                new_price INTEGER,
                
                -- Trade (P) fields
                trade_id INTEGER,
                
                -- Cross Trade (Q) fields
                cross_shares INTEGER,
                cross_price INTEGER,
                cross_type CHAR(1),
                
                -- System Event (S) fields
                event_code CHAR(1),
                
                -- Stock Directory (R) fields
                market_category CHAR(1),
                financial_status CHAR(1),
                round_lot INTEGER,
                issue_classification CHAR(1),
                
                -- Raw message for debugging
                raw_message BLOB
            )
        ''')
        
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS parse_stats (
                total_messages INTEGER,
                parse_duration_sec REAL,
                file_size_bytes INTEGER,
                parse_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        self.db.commit()
        
    def parse_file(self, itch_file, max_messages=None):
        """Parse ITCH binary file into database"""
        file_size = Path(itch_file).stat().st_size
        print(f"Parsing {itch_file} ({file_size / 1e9:.2f} GB)...")
        print("Supported types: A, E, X, S, R, D, U, P, Q")
        
        start_time = time.time()
        
        with open(itch_file, 'rb') as f:
            count = 0
            last_print = 0
            
            # Begin transaction for batch performance
            self.cursor.execute("BEGIN TRANSACTION")
            
            while True:
                if max_messages and count >= max_messages:
                    break
                    
                # Read 2-byte length field (big-endian)
                length_bytes = f.read(2)
                if len(length_bytes) < 2:
                    break  # EOF
                    
                msg_length = struct.unpack('>H', length_bytes)[0]
                msg_data = f.read(msg_length)
                
                if len(msg_data) < msg_length:
                    break  # Incomplete message
                    
                # Parse message
                msg_type = chr(msg_data[0])
                self.stats['by_type'][msg_type] = self.stats['by_type'].get(msg_type, 0) + 1
                
                # Parse based on type
                record = self.parse_message(msg_type, msg_data)
                if record:
                    self.batch.append(record)
                    
                count += 1
                self.stats['total'] = count
                
                # Batch insert
                if len(self.batch) >= self.batch_size:
                    self.flush_batch()
                    
                # Progress indicator
                if count - last_print >= 100000:
                    elapsed = time.time() - start_time
                    rate = count / elapsed
                    print(f"  Parsed {count:,} messages ({rate:.0f} msg/sec)")
                    last_print = count
        
        # Final flush
        self.flush_batch()
        self.db.commit()
        
        # Create indexes after bulk insert (much faster)
        print("Creating indexes...")
        self.create_indexes()
        
        # Save statistics
        duration = time.time() - start_time
        self.save_stats(file_size, duration)
        
        print(f"\nCompleted in {duration:.1f} seconds")
        print(f"Average rate: {count/duration:.0f} messages/second")
        print("\nMessage type breakdown:")
        for msg_type, count in sorted(self.stats['by_type'].items()):
            type_name = self.get_type_name(msg_type)
            print(f"  {msg_type}: {count:,}  ({type_name})")
            
    def get_type_name(self, msg_type):
        """Get descriptive name for message type"""
        names = {
            'S': 'System Event',
            'R': 'Stock Directory',
            'H': 'Trading Action',
            'Y': 'Reg SHO Restriction',
            'L': 'Market Participant Position',
            'V': 'MWCB Decline Level',
            'W': 'MWCB Status',
            'K': 'IPO Quoting Period',
            'J': 'LULD Auction Collar',
            'h': 'Operational Halt',
            'A': 'Add Order (no MPID)',
            'F': 'Add Order (MPID)',
            'E': 'Order Executed',
            'C': 'Order Executed w/ Price',
            'X': 'Order Cancel',
            'D': 'Order Delete',
            'U': 'Order Replace',
            'P': 'Trade (non-cross)',
            'Q': 'Cross Trade',
            'B': 'Broken Trade',
            'I': 'NOII Message'
        }
        return names.get(msg_type, 'Unknown')
            
    def parse_message(self, msg_type, msg_data):
        """Parse individual ITCH message"""
        try:
            if msg_type == 'S':  # System Event
                return self.parse_system_event(msg_data)
            elif msg_type == 'R':  # Stock Directory
                return self.parse_stock_directory(msg_data)
            elif msg_type == 'A':  # Add Order
                return self.parse_add_order(msg_data)
            elif msg_type == 'E':  # Order Executed
                return self.parse_order_executed(msg_data)
            elif msg_type == 'X':  # Order Cancel
                return self.parse_order_cancel(msg_data)
            elif msg_type == 'D':  # Order Delete
                return self.parse_order_delete(msg_data)
            elif msg_type == 'U':  # Order Replace
                return self.parse_order_replace(msg_data)
            elif msg_type == 'P':  # Trade (non-cross)
                return self.parse_trade(msg_data)
            elif msg_type == 'Q':  # Cross Trade
                return self.parse_cross_trade(msg_data)
            else:
                # Store unknown types with just basics
                return {
                    'timestamp_ns': 0,
                    'message_type': msg_type,
                    'raw_message': msg_data
                }
        except Exception as e:
            print(f"Error parsing message type {msg_type}: {e}")
            return None
            
    def parse_system_event(self, msg_data):
        """Parse System Event (S) message - 12 bytes"""
        stock_locate = struct.unpack('>H', msg_data[1:3])[0]
        tracking_num = struct.unpack('>H', msg_data[3:5])[0]
        timestamp = struct.unpack('>Q', b'\x00\x00' + msg_data[5:11])[0]
        event_code = chr(msg_data[11])
        
        return {
            'timestamp_ns': timestamp,
            'message_type': 'S',
            'stock_locate': stock_locate,
            'event_code': event_code,
            'raw_message': msg_data
        }
        
    def parse_stock_directory(self, msg_data):
        """Parse Stock Directory (R) message - 39 bytes"""
        stock_locate = struct.unpack('>H', msg_data[1:3])[0]
        tracking_num = struct.unpack('>H', msg_data[3:5])[0]
        timestamp = struct.unpack('>Q', b'\x00\x00' + msg_data[5:11])[0]
        stock_symbol = msg_data[11:19].decode('ascii').strip()
        market_category = chr(msg_data[19])
        financial_status = chr(msg_data[20])
        round_lot = struct.unpack('>I', msg_data[21:25])[0]
        # Skip round lot only (1 byte) at offset 25
        issue_classification = chr(msg_data[26])
        # Remaining fields omitted for brevity
        
        return {
            'timestamp_ns': timestamp,
            'message_type': 'R',
            'stock_locate': stock_locate,
            'stock_symbol': stock_symbol,
            'market_category': market_category,
            'financial_status': financial_status,
            'round_lot': round_lot,
            'issue_classification': issue_classification,
            'raw_message': msg_data
        }
        
    def parse_add_order(self, msg_data):
        """Parse Add Order (A) message - 36 bytes"""
        stock_locate = struct.unpack('>H', msg_data[1:3])[0]
        tracking_num = struct.unpack('>H', msg_data[3:5])[0]
        timestamp = struct.unpack('>Q', b'\x00\x00' + msg_data[5:11])[0]
        order_ref = struct.unpack('>Q', msg_data[11:19])[0]
        buy_sell = chr(msg_data[19])
        shares = struct.unpack('>I', msg_data[20:24])[0]
        stock_symbol = msg_data[24:32].decode('ascii').strip()
        price = struct.unpack('>I', msg_data[32:36])[0]
        
        return {
            'timestamp_ns': timestamp,
            'message_type': 'A',
            'stock_locate': stock_locate,
            'stock_symbol': stock_symbol,
            'order_ref_num': order_ref,
            'buy_sell': buy_sell,
            'shares': shares,
            'price': price,
            'raw_message': msg_data
        }
        
    def parse_order_executed(self, msg_data):
        """Parse Order Executed (E) message - 31 bytes"""
        stock_locate = struct.unpack('>H', msg_data[1:3])[0]
        tracking_num = struct.unpack('>H', msg_data[3:5])[0]
        timestamp = struct.unpack('>Q', b'\x00\x00' + msg_data[5:11])[0]
        order_ref = struct.unpack('>Q', msg_data[11:19])[0]
        executed_shares = struct.unpack('>I', msg_data[19:23])[0]
        match_number = struct.unpack('>Q', msg_data[23:31])[0]
        
        return {
            'timestamp_ns': timestamp,
            'message_type': 'E',
            'stock_locate': stock_locate,
            'order_ref_num': order_ref,
            'executed_shares': executed_shares,
            'match_number': match_number,
            'raw_message': msg_data
        }
        
    def parse_order_cancel(self, msg_data):
        """Parse Order Cancel (X) message - 23 bytes"""
        stock_locate = struct.unpack('>H', msg_data[1:3])[0]
        tracking_num = struct.unpack('>H', msg_data[3:5])[0]
        timestamp = struct.unpack('>Q', b'\x00\x00' + msg_data[5:11])[0]
        order_ref = struct.unpack('>Q', msg_data[11:19])[0]
        cancelled_shares = struct.unpack('>I', msg_data[19:23])[0]
        
        return {
            'timestamp_ns': timestamp,
            'message_type': 'X',
            'stock_locate': stock_locate,
            'order_ref_num': order_ref,
            'cancelled_shares': cancelled_shares,
            'raw_message': msg_data
        }
        
    def parse_order_delete(self, msg_data):
        """Parse Order Delete (D) message - 19 bytes"""
        stock_locate = struct.unpack('>H', msg_data[1:3])[0]
        tracking_num = struct.unpack('>H', msg_data[3:5])[0]
        timestamp = struct.unpack('>Q', b'\x00\x00' + msg_data[5:11])[0]
        order_ref = struct.unpack('>Q', msg_data[11:19])[0]
        
        return {
            'timestamp_ns': timestamp,
            'message_type': 'D',
            'stock_locate': stock_locate,
            'order_ref_num': order_ref,
            'raw_message': msg_data
        }
        
    def parse_order_replace(self, msg_data):
        """Parse Order Replace (U) message - 35 bytes"""
        stock_locate = struct.unpack('>H', msg_data[1:3])[0]
        tracking_num = struct.unpack('>H', msg_data[3:5])[0]
        timestamp = struct.unpack('>Q', b'\x00\x00' + msg_data[5:11])[0]
        original_order_ref = struct.unpack('>Q', msg_data[11:19])[0]
        new_order_ref = struct.unpack('>Q', msg_data[19:27])[0]
        new_shares = struct.unpack('>I', msg_data[27:31])[0]
        new_price = struct.unpack('>I', msg_data[31:35])[0]
        
        return {
            'timestamp_ns': timestamp,
            'message_type': 'U',
            'stock_locate': stock_locate,
            'original_order_ref': original_order_ref,
            'new_order_ref': new_order_ref,
            'new_shares': new_shares,
            'new_price': new_price,
            'raw_message': msg_data
        }
        
    def parse_trade(self, msg_data):
        """Parse Trade (P) message - 44 bytes"""
        stock_locate = struct.unpack('>H', msg_data[1:3])[0]
        tracking_num = struct.unpack('>H', msg_data[3:5])[0]
        timestamp = struct.unpack('>Q', b'\x00\x00' + msg_data[5:11])[0]
        order_ref = struct.unpack('>Q', msg_data[11:19])[0]
        buy_sell = chr(msg_data[19])
        shares = struct.unpack('>I', msg_data[20:24])[0]
        stock_symbol = msg_data[24:32].decode('ascii').strip()
        price = struct.unpack('>I', msg_data[32:36])[0]
        match_number = struct.unpack('>Q', msg_data[36:44])[0]
        
        return {
            'timestamp_ns': timestamp,
            'message_type': 'P',
            'stock_locate': stock_locate,
            'stock_symbol': stock_symbol,
            'order_ref_num': order_ref,
            'buy_sell': buy_sell,
            'shares': shares,
            'price': price,
            'match_number': match_number,
            'raw_message': msg_data
        }
        
    def parse_cross_trade(self, msg_data):
        """Parse Cross Trade (Q) message - 40 bytes"""
        stock_locate = struct.unpack('>H', msg_data[1:3])[0]
        tracking_num = struct.unpack('>H', msg_data[3:5])[0]
        timestamp = struct.unpack('>Q', b'\x00\x00' + msg_data[5:11])[0]
        cross_shares = struct.unpack('>Q', msg_data[11:19])[0]
        stock_symbol = msg_data[19:27].decode('ascii').strip()
        cross_price = struct.unpack('>I', msg_data[27:31])[0]
        match_number = struct.unpack('>Q', msg_data[31:39])[0]
        cross_type = chr(msg_data[39])
        
        return {
            'timestamp_ns': timestamp,
            'message_type': 'Q',
            'stock_locate': stock_locate,
            'stock_symbol': stock_symbol,
            'cross_shares': cross_shares,
            'cross_price': cross_price,
            'match_number': match_number,
            'cross_type': cross_type,
            'raw_message': msg_data
        }
        
    def flush_batch(self):
        """Insert batch of records"""
        if not self.batch:
            return
            
        self.cursor.executemany('''
            INSERT INTO itch_messages VALUES (
                NULL, :timestamp_ns, :message_type, :stock_locate, :stock_symbol,
                :order_ref_num, :buy_sell, :shares, :price,
                :executed_shares, :match_number, :cancelled_shares,
                :original_order_ref, :new_order_ref, :new_shares, :new_price,
                :trade_id, :cross_shares, :cross_price, :cross_type,
                :event_code, :market_category, :financial_status, :round_lot,
                :issue_classification, :raw_message
            )
        ''', [self.dict_to_row(r) for r in self.batch])
        
        self.batch = []
        
    def dict_to_row(self, record):
        """Convert record dict to full row with all columns"""
        return {
            'timestamp_ns': record.get('timestamp_ns', 0),
            'message_type': record.get('message_type', ''),
            'stock_locate': record.get('stock_locate'),
            'stock_symbol': record.get('stock_symbol'),
            'order_ref_num': record.get('order_ref_num'),
            'buy_sell': record.get('buy_sell'),
            'shares': record.get('shares'),
            'price': record.get('price'),
            'executed_shares': record.get('executed_shares'),
            'match_number': record.get('match_number'),
            'cancelled_shares': record.get('cancelled_shares'),
            'original_order_ref': record.get('original_order_ref'),
            'new_order_ref': record.get('new_order_ref'),
            'new_shares': record.get('new_shares'),
            'new_price': record.get('new_price'),
            'trade_id': record.get('trade_id'),
            'cross_shares': record.get('cross_shares'),
            'cross_price': record.get('cross_price'),
            'cross_type': record.get('cross_type'),
            'event_code': record.get('event_code'),
            'market_category': record.get('market_category'),
            'financial_status': record.get('financial_status'),
            'round_lot': record.get('round_lot'),
            'issue_classification': record.get('issue_classification'),
            'raw_message': record.get('raw_message')
        }
        
    def create_indexes(self):
        """Create indexes after bulk insert"""
        indexes = [
            "CREATE INDEX IF NOT EXISTS idx_timestamp ON itch_messages(timestamp_ns)",
            "CREATE INDEX IF NOT EXISTS idx_symbol ON itch_messages(stock_symbol)",
            "CREATE INDEX IF NOT EXISTS idx_type ON itch_messages(message_type)",
            "CREATE INDEX IF NOT EXISTS idx_symbol_time ON itch_messages(stock_symbol, timestamp_ns)",
            "CREATE INDEX IF NOT EXISTS idx_order_ref ON itch_messages(order_ref_num)"
        ]
        for idx in indexes:
            self.cursor.execute(idx)
        self.db.commit()
        
    def save_stats(self, file_size, duration):
        """Save parse statistics"""
        self.cursor.execute('''
            INSERT INTO parse_stats (total_messages, parse_duration_sec, file_size_bytes)
            VALUES (?, ?, ?)
        ''', (self.stats['total'], duration, file_size))
        self.db.commit()
        
    def close(self):
        self.db.close()

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python itch_to_db.py <itch_file> <output_db> [max_messages]")
        sys.exit(1)
        
    itch_file = sys.argv[1]
    db_file = sys.argv[2]
    max_msgs = int(sys.argv[3]) if len(sys.argv) > 3 else None
    
    parser = ITCHParser(db_file)
    try:
        parser.parse_file(itch_file, max_msgs)
    finally:
        parser.close()
        
    print(f"\nDatabase created: {db_file}")
    print(f"\nUseful queries:")
    print(f"  sqlite3 {db_file} \"SELECT message_type, COUNT(*) FROM itch_messages GROUP BY message_type\"")
    print(f"  sqlite3 {db_file} \"SELECT stock_symbol, COUNT(*) FROM itch_messages WHERE message_type='A' GROUP BY stock_symbol ORDER BY COUNT(*) DESC LIMIT 10\"")