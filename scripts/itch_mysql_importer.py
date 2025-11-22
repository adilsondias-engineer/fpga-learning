#!/usr/bin/env python3
"""
itch_mysql_importer.py - Import ITCH PCAP files to MySQL/MariaDB

Handles 20+ million records efficiently with proper indexing and batching.
Replaces SQLite for better scalability and concurrent access.

Requirements:
    pip install scapy pymysql

MySQL Setup:
    CREATE DATABASE itch_data CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER 'itch_user'@'localhost' IDENTIFIED BY 'password';
    GRANT ALL PRIVILEGES ON itch_data.* TO 'itch_user'@'localhost';
    FLUSH PRIVILEGES;

Usage:
    python itch_mysql_importer.py nasdaq_itch50.pcap --host localhost --user itch_user --password your_password
"""

import sys
import argparse
import struct
from datetime import datetime
from collections import defaultdict
import time

try:
    from scapy.all import rdpcap, Raw
except ImportError:
    print("\nERROR: Scapy not installed")
    print("Install with: pip install scapy")
    sys.exit(1)

try:
    import pymysql
    import pymysql.cursors
except ImportError:
    print("\nERROR: PyMySQL not installed")
    print("Install with: pip install pymysql")
    sys.exit(1)


class MySQLITCHImporter:
    """Import ITCH messages from PCAP to MySQL with optimized batching"""

    # ITCH 5.0 message types (all 9 types supported by FPGA)
    MESSAGE_TYPES = {
        'S': 'System Event',
        'R': 'Stock Directory',
        'A': 'Add Order',
        'E': 'Order Executed',
        'X': 'Order Cancel',
        'D': 'Order Delete',
        'U': 'Order Replace',
        'P': 'Trade',
        'Q': 'Cross Trade'
    }

    def __init__(self, host, user, password, database='itch_data', port=3306):
        """Initialize MySQL connection with optimized settings"""
        print(f"Connecting to MySQL: {user}@{host}:{port}/{database}")

        self.conn = pymysql.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            database=database,
            charset='utf8mb4',
            #auth_plugin_map='caching_sha2_password',  # MySQL 8.0+ default authentication
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=False  # Manual commit for batch optimization
        )
        self.cursor = self.conn.cursor()

        # Performance settings
        self.cursor.execute("SET SESSION sql_mode = 'NO_AUTO_VALUE_ON_ZERO'")
        self.cursor.execute("SET SESSION autocommit = 0")
        self.cursor.execute("SET SESSION unique_checks = 0")
        self.cursor.execute("SET SESSION foreign_key_checks = 0")

        print("Connected to MySQL successfully")

    def create_tables(self, drop_existing=False):
        """Create optimized tables with proper indexing"""

        if drop_existing:
            print("Dropping existing tables...")
            self.cursor.execute("DROP TABLE IF EXISTS itch_messages")
            self.cursor.execute("DROP TABLE IF EXISTS symbols")
            self.cursor.execute("DROP TABLE IF EXISTS import_stats")

        print("Creating tables...")

        # Main messages table - optimized for time-series queries
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS itch_messages (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                timestamp_ns BIGINT UNSIGNED NOT NULL,
                message_type CHAR(1) NOT NULL,
                stock_symbol VARCHAR(8),
                raw_message BLOB NOT NULL,

                -- Indexes for common queries
                INDEX idx_timestamp (timestamp_ns),
                INDEX idx_symbol_time (stock_symbol, timestamp_ns),
                INDEX idx_type (message_type),
                INDEX idx_symbol_type (stock_symbol, message_type)
            ) ENGINE=InnoDB
            ROW_FORMAT=COMPRESSED
            KEY_BLOCK_SIZE=8
            COMMENT='ITCH 5.0 messages - optimized for time-series replay'
        """)

        # Symbols catalog with statistics
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS symbols (
                symbol VARCHAR(8) PRIMARY KEY,
                message_count INT UNSIGNED DEFAULT 0,
                first_seen BIGINT UNSIGNED,
                last_seen BIGINT UNSIGNED,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

                INDEX idx_count (message_count DESC),
                INDEX idx_first_seen (first_seen)
            ) ENGINE=InnoDB
            COMMENT='Symbol statistics and catalog'
        """)

        # Import tracking
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS import_stats (
                id INT AUTO_INCREMENT PRIMARY KEY,
                filename VARCHAR(255),
                imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                total_messages BIGINT UNSIGNED,
                duration_seconds FLOAT,
                messages_per_second INT UNSIGNED
            ) ENGINE=InnoDB
        """)

        self.conn.commit()
        print("Tables created successfully")

    def parse_itch_message(self, payload):
        """Parse ITCH message to extract type, symbol, and timestamp"""
        if len(payload) < 2:
            return None

        msg_type = chr(payload[0])

        # Extract symbol if present (offset varies by message type)
        symbol = None
        if msg_type in ['R', 'A', 'E', 'X', 'D', 'U', 'P', 'Q']:
            # Symbol is 8 bytes at offset 24 for most order-related messages
            if len(payload) >= 32:
                symbol_bytes = payload[24:32]
                symbol = symbol_bytes.decode('ascii', errors='ignore').strip()

        return {
            'type': msg_type,
            'symbol': symbol if symbol else None,
            'raw': bytes(payload)
        }

    def _read_binary_itch(self, filename):
        """
        Read binary ITCH 5.0 file and yield messages

        ITCH 5.0 format:
        - Big-endian
        - Variable length messages
        - 2-byte length prefix + message data

        Yields:
            Tuples of (timestamp_ns, message_dict)
        """
        print(f"Reading binary ITCH 5.0 file: {filename}")

        messages = []
        message_count = 0
        current_timestamp = int(time.time() * 1e9)  # Base timestamp

        with open(filename, 'rb') as f:
            while True:
                # Read 2-byte length (big-endian)
                length_bytes = f.read(2)
                if not length_bytes or len(length_bytes) < 2:
                    break  # End of file

                msg_length = struct.unpack('>H', length_bytes)[0]

                # Read message payload
                payload = f.read(msg_length)
                if len(payload) < msg_length:
                    print(f"⚠ Warning: Truncated message at offset {f.tell()}")
                    break

                # Parse message
                msg = self.parse_itch_message(payload)
                if msg:
                    # Use sequential timestamps (increment by 1µs per message)
                    timestamp_ns = current_timestamp + (message_count * 1000)
                    messages.append((timestamp_ns, msg))
                    message_count += 1

                    # Progress display for large files
                    if message_count % 1000000 == 0:
                        print(f"  Read {message_count:,} messages...")
                    if message_count > 100000000:
                        print("100000000 messages reached, stopping import")
                        break
        print(f"Read {message_count:,} messages from binary ITCH file")
        return messages

    def _read_pcap(self, filename):
        """
        Read PCAP file and extract ITCH messages

        Yields:
            Tuples of (timestamp_ns, message_dict)
        """
        print(f"Reading PCAP file: {filename}")

        packets = rdpcap(filename)
        messages = []

        for i, pkt in enumerate(packets):
            if Raw in pkt:
                payload = bytes(pkt[Raw].load)
                msg = self.parse_itch_message(payload)

                if msg:
                    # Use packet timestamp or synthetic
                    timestamp_ns = int(time.time() * 1e9) + i
                    messages.append((timestamp_ns, msg))

        print(f"Read {len(messages):,} messages from PCAP")
        return messages

    def import_file(self, input_file, batch_size=10000, progress_interval=50000):
        """
        Import ITCH file (PCAP or binary) with optimized batching

        Args:
            input_file: Path to ITCH file (PCAP or binary)
            batch_size: Number of records per batch insert (default 10,000)
            progress_interval: Show progress every N messages
        """
        print(f"\nImporting: {input_file}")
        print(f"Batch size: {batch_size:,} messages")

        start_time = time.time()

        # Detect file type and read
        print("Reading file...")
        try:
            if input_file.endswith('.pcap') or input_file.endswith('.pcapng'):
                messages = self._read_pcap(input_file)
            else:
                # Assume binary ITCH 5.0 file
                messages = self._read_binary_itch(input_file)
        except Exception as e:
            print(f"ERROR reading file: {e}")
            import traceback
            traceback.print_exc()
            return

        print(f"File loaded, processing messages...")

        # Prepare batch insert
        batch = []
        total_count = 0
        type_counts = defaultdict(int)
        symbol_stats = defaultdict(lambda: {'count': 0, 'first': None, 'last': None})

        last_progress_time = time.time()

        for i, (timestamp_ns, msg) in enumerate(messages):
            if not msg:
                continue

            # Add to batch
            batch.append((
                timestamp_ns,
                msg['type'],
                msg['symbol'],
                msg['raw']
            ))

            # Update statistics
            type_counts[msg['type']] += 1
            if msg['symbol']:
                stats = symbol_stats[msg['symbol']]
                stats['count'] += 1
                if stats['first'] is None:
                    stats['first'] = timestamp_ns
                stats['last'] = timestamp_ns

            total_count += 1

            # Batch insert
            if len(batch) >= batch_size:
                self._insert_batch(batch)
                batch = []
                self.conn.commit()  # Commit every batch

            # Progress display
            if total_count % progress_interval == 0:
                now = time.time()
                elapsed = now - start_time
                rate = total_count / elapsed

                print(f"  Progress: {total_count:,} messages "
                      f"({rate:.0f} msg/sec)")
            if total_count > 100000000:
                print("100000000 messages reached, stopping import")
                break

        # Insert remaining batch
        if batch:
            self._insert_batch(batch)
            self.conn.commit()

        # Update symbol statistics table
        print("\nUpdating symbol statistics...")
        self._update_symbol_stats(symbol_stats)

        # Record import stats
        duration = time.time() - start_time
        rate = total_count / duration if duration > 0 else 0

        self.cursor.execute("""
            INSERT INTO import_stats (filename, total_messages, duration_seconds, messages_per_second)
            VALUES (%s, %s, %s, %s)
        """, (input_file, total_count, duration, int(rate)))

        self.conn.commit()

        # Final report
        print(f"\n{'='*60}")
        print(f"Import Complete!")
        print(f"{'='*60}")
        print(f"Total messages: {total_count:,}")
        print(f"Duration: {duration:.1f} seconds")
        print(f"Average rate: {rate:.0f} messages/second")
        print(f"\nBreakdown by message type:")
        for msg_type in sorted(type_counts.keys()):
            count = type_counts[msg_type]
            pct = (count / total_count) * 100
            name = self.MESSAGE_TYPES.get(msg_type, 'Unknown')
            print(f"  {msg_type} ({name}): {count:,} ({pct:.1f}%)")

        print(f"\nUnique symbols: {len(symbol_stats):,}")

    def _insert_batch(self, batch):
        """Optimized batch insert"""
        if not batch:
            return

        sql = """
            INSERT INTO itch_messages (timestamp_ns, message_type, stock_symbol, raw_message)
            VALUES (%s, %s, %s, %s)
        """

        self.cursor.executemany(sql, batch)

    def _update_symbol_stats(self, symbol_stats):
        """Update symbol statistics table"""
        if not symbol_stats:
            return

        sql = """
            INSERT INTO symbols (symbol, message_count, first_seen, last_seen)
            VALUES (%s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE
                message_count = message_count + VALUES(message_count),
                first_seen = LEAST(first_seen, VALUES(first_seen)),
                last_seen = GREATEST(last_seen, VALUES(last_seen))
        """

        batch = [
            (symbol, stats['count'], stats['first'], stats['last'])
            for symbol, stats in symbol_stats.items()
        ]

        self.cursor.executemany(sql, batch)
        self.conn.commit()

    def get_table_stats(self):
        """Get current table statistics"""
        self.cursor.execute("""
            SELECT
                COUNT(*) as total_messages,
                MIN(timestamp_ns) as first_timestamp,
                MAX(timestamp_ns) as last_timestamp,
                COUNT(DISTINCT stock_symbol) as unique_symbols
            FROM itch_messages
        """)

        return self.cursor.fetchone()

    def close(self):
        """Close database connection"""
        self.cursor.close()
        self.conn.close()
        print("Database connection closed")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Import ITCH files (PCAP or binary) to MySQL/MariaDB',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Import binary ITCH 5.0 file
  python itch_mysql_importer.py 12302019.NASDAQ_ITCH50 --host localhost --user itch_user --password mypass

  # Import PCAP file
  python itch_mysql_importer.py nasdaq.pcap --host localhost --user itch_user --password mypass

  # Import with custom batch size (faster for large files)
  python itch_mysql_importer.py 12302019.NASDAQ_ITCH50 --host localhost --user root --password root --batch-size 50000

  # Drop and recreate tables
  python itch_mysql_importer.py data.pcap --host localhost --user root --password root --drop-tables
        """
    )

    parser.add_argument('itch_file', help='ITCH file (binary or PCAP) containing ITCH messages')
    parser.add_argument('--host', default='localhost', help='MySQL host (default: localhost)')
    parser.add_argument('--port', type=int, default=3306, help='MySQL port (default: 3306)')
    parser.add_argument('--user', required=True, help='MySQL username')
    parser.add_argument('--password', required=True, help='MySQL password')
    parser.add_argument('--database', default='itch_data', help='Database name (default: itch_data)')
    parser.add_argument('--batch-size', type=int, default=10000,
                       help='Batch insert size (default: 10,000)')
    parser.add_argument('--drop-tables', action='store_true',
                       help='Drop existing tables before import')
    parser.add_argument('--stats-only', action='store_true',
                       help='Show database statistics without importing')

    args = parser.parse_args()

    # Connect to MySQL
    importer = MySQLITCHImporter(
        host=args.host,
        port=args.port,
        user=args.user,
        password=args.password,
        database=args.database
    )

    try:
        if args.stats_only:
            # Show statistics
            stats = importer.get_table_stats()
            print("\nDatabase Statistics:")
            print("=" * 60)
            print(f"Total messages: {stats['total_messages']:,}")
            print(f"Unique symbols: {stats['unique_symbols']:,}")
            print(f"Time range: {stats['first_timestamp']} to {stats['last_timestamp']}")
        else:
            # Create tables
            importer.create_tables(drop_existing=args.drop_tables)

            # Import file
            importer.import_file(args.itch_file, batch_size=args.batch_size)

            # Show final stats
            print("\nFinal database statistics:")
            stats = importer.get_table_stats()
            print(f"  Total messages: {stats['total_messages']:,}")
            print(f"  Unique symbols: {stats['unique_symbols']:,}")

    finally:
        importer.close()
