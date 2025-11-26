-- itchdb_schema.sql
-- Bootstrap script for the MySQL schema used by scripts/itch_mysql_importer.py
--
-- Usage:
--   mysql -u root -p < 14-order-gateway-cpp/db/itchdb_schema.sql
--
-- Optional: create an application user (replace password as needed)
--   CREATE USER IF NOT EXISTS 'itch_user'@'%' IDENTIFIED BY 'change_me';
--   GRANT ALL PRIVILEGES ON itch_data.* TO 'itch_user'@'%';
--   FLUSH PRIVILEGES;

-- Database -------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS itch_data
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE itch_data;

-- Main ITCH message store ----------------------------------------------------
CREATE TABLE IF NOT EXISTS itch_messages (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    timestamp_ns BIGINT UNSIGNED NOT NULL,
    message_type CHAR(1) NOT NULL,
    stock_symbol VARCHAR(8),
    raw_message BLOB NOT NULL,

    INDEX idx_timestamp (timestamp_ns),
    INDEX idx_symbol_time (stock_symbol, timestamp_ns),
    INDEX idx_type (message_type),
    INDEX idx_symbol_type (stock_symbol, message_type)
) ENGINE=InnoDB
  ROW_FORMAT=COMPRESSED
  KEY_BLOCK_SIZE=8
  COMMENT='ITCH 5.0 messages - optimized for time-series replay';

-- Symbol catalog & stats -----------------------------------------------------
CREATE TABLE IF NOT EXISTS symbols (
    symbol VARCHAR(8) PRIMARY KEY,
    message_count INT UNSIGNED DEFAULT 0,
    first_seen BIGINT UNSIGNED,
    last_seen BIGINT UNSIGNED,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
               ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_count (message_count DESC),
    INDEX idx_first_seen (first_seen)
) ENGINE=InnoDB
  COMMENT='Symbol statistics and catalog';

-- Import tracking ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS import_stats (
    id INT AUTO_INCREMENT PRIMARY KEY,
    filename VARCHAR(255),
    imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_messages BIGINT UNSIGNED,
    duration_seconds FLOAT,
    messages_per_second INT UNSIGNED
) ENGINE=InnoDB
  COMMENT='Tracks each ITCH import run';

-- Optional seed data ---------------------------------------------------------
INSERT INTO import_stats (filename, total_messages, duration_seconds, messages_per_second)
VALUES ('bootstrap', 0, 0, 0)
ON DUPLICATE KEY UPDATE imported_at = CURRENT_TIMESTAMP;

