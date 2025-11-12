# BBO UART Output Format

## Overview

The FPGA outputs BBO (Best Bid/Offer) data via UART (115200 baud, 8N1) in a human-readable ASCII format suitable for parsing by the C++ Order Gateway (Project 9).

## Output Format

### Valid BBO Data

```
[BBO:AAPL    ] Bid:0x12345678 (0x00000064) | Ask:0x12346789 (0x000000C8) | Spr:0x00001111\r\n
```

**Field Breakdown:**
- `[BBO:AAPL    ]` - Header with 8-character symbol (space-padded)
- `Bid:0xXXXXXXXX` - Bid price (32-bit hex, big-endian)
- `(0xXXXXXXXX)` - Bid shares (32-bit hex, big-endian)
- `Ask:0xXXXXXXXX` - Ask price (32-bit hex, big-endian)
- `(0xXXXXXXXX)` - Ask shares (32-bit hex, big-endian)
- `Spr:0xXXXXXXXX` - Spread (ask - bid, 32-bit hex)
- `\r\n` - Line terminator

### No Valid BBO Data

```
[BBO:NODATA  ]\r\n
```

**Parsing Note:** Symbol field contains `NODATA  ` (space-padded to 8 characters) when no valid BBO exists. C++ parser can check if symbol == "NODATA" to immediately skip processing.

## Price Format

Prices are 32-bit unsigned integers representing fixed-point values with 4 decimal places:
- Example: `0x00098968` = 625,000 = $62.5000
- Division: `price_value / 10000 = dollar_amount`

## Update Frequency

- **Event-driven**: BBO output triggered on any price/quantity change
- **Heartbeat**: If no updates for 5 seconds, send current BBO (or NODATA if invalid)

## BBO Validation

**CRITICAL:** BBO is marked invalid (`[BBO:NODATA]`) when:
- Order book is cleared/reset
- No bid levels exist (bid_level_count = 0)
- No ask levels exist (ask_level_count = 0)
- Either bid or ask side is empty

This prevents **stale price propagation** - a serious issue in production trading systems where outdated prices could trigger incorrect trading decisions.

## Current Symbol Support

**Phase 1:** Single symbol only - `AAPL` (hardcoded in order_book_pkg.vhd)

**Future:** Phase 2 will support multiple symbols (up to 8) with dynamic symbol field

## Integration Notes for Project 9

### Parser Requirements

1. **Line-based parsing**: Read until `\r\n`
2. **Symbol extraction**: Parse 8 characters after `[BBO:`
3. **Symbol validation**: Check if symbol is "NODATA" - if yes, skip processing
4. **Hex parsing**: All numeric values are prefixed with `0x`

### Example C++ Parsing Pseudocode

```cpp
// Read line from UART
std::string line = uart.readLine();

// Extract symbol (bytes 5-12, immediately after "[BBO:")
std::string symbol = line.substr(5, 8);
trim(symbol);  // Remove trailing spaces

// Check for no-data condition
if (symbol == "NODATA") {
    // No valid BBO - wait for next update
    return;
}

// Valid BBO - parse fields
uint32_t bid_price = parseHex(extractField(line, "Bid:0x"));
uint32_t bid_shares = parseHex(extractField(line, "(0x", 1));
uint32_t ask_price = parseHex(extractField(line, "Ask:0x"));
uint32_t ask_shares = parseHex(extractField(line, "(0x", 2));
uint32_t spread = parseHex(extractField(line, "Spr:0x"));

// Convert price to dollars
double bid_price_usd = bid_price / 10000.0;
double ask_price_usd = ask_price / 10000.0;

// Process BBO for this symbol
processBBO(symbol, bid_price_usd, bid_shares, ask_price_usd, ask_shares);
```

## Hardware Implementation

- **Module**: `uart_bbo_formatter.vhd`
- **Input**: `bbo_t` record from `bbo_tracker.vhd`
- **Clock Domain**: 100 MHz (synchronized from 25 MHz MII domain)
- **Latency**: ~1-2 microseconds from BBO update to UART transmission start

## Testing

Connect to UART at 115200 baud using:
- **Windows**: PuTTY, TeraTerm, or COM port reader
- **Linux**: `screen /dev/ttyUSB0 115200` or `minicom`

Send ITCH 5.0 Add Order messages via Ethernet to see BBO updates.

## References

- [order_book_pkg.vhd](src/order_book_pkg.vhd#L20) - TARGET_SYMBOL definition
- [uart_bbo_formatter.vhd](src/uart_bbo_formatter.vhd) - UART formatter implementation
- [bbo_tracker.vhd](src/bbo_tracker.vhd) - BBO calculation logic
- [Project 9 README](../09-order-book-client/README.md) - C++ Order Gateway documentation
