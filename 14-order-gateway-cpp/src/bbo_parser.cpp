#include "bbo_parser.h"
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <chrono>
#include <ctime>
#include <stdexcept>
#include <arpa/inet.h>
#include <cstring>

namespace gateway
{
/*
    *UDP Packet Format:**

| Offset | Size | Field | Description | Example Value |
|--------|------|-------|-------------|---------------|
| **Ethernet Header (14 bytes)** |
| 0x00 | 6 | Destination MAC | Broadcast address | `FF:FF:FF:FF:FF:FF` |
| 0x06 | 6 | Source MAC | FPGA MAC address | `00:18:3E:04:5D:E7` |
| 0x0C | 2 | EtherType | IPv4 | `0x0800` |
| **IP Header (20 bytes)** |
| 0x0E | 1 | Version/IHL | IPv4, 20-byte header | `0x45` |
| 0x10 | 2 | Total Length | IP + UDP + Payload | `0x011C` (284 bytes) |
| 0x17 | 1 | Protocol | UDP | `0x11` (17) |
| 0x1A | 4 | Source IP | FPGA IP address | `192.168.0.212` |
| 0x1E | 4 | Destination IP | Target IP | `192.168.0.93` |
| **UDP Header (8 bytes)** |
| 0x22 | 2 | Source Port | FPGA UDP port | `0x1388` (5000) |
| 0x24 | 2 | Destination Port | Target UDP port | `0x1388` (5000) |
| 0x26 | 2 | Length | UDP header + payload | `0x0108` (264 bytes) |
| 0x28 | 2 | Checksum | Not computed | `0x0000` |
| **UDP Payload (256 bytes)** |
| 0x2A - 0xFD | 228 | Padding | Zero padding | `0x00...` |
| **BBO Data (28 bytes, at end of payload due to nibble reversal)** |
| 0xFE - 0x101 | 4 | Spread | Ask - Bid (big-endian) | `0x000061A8` = 25,000 |
| 0x102 - 0x105 | 4 | ASK Shares | Total ask shares (big-endian) | `0x0000012C` = 300 |
| 0x106 - 0x109 | 4 | ASK Price | Best ask price (big-endian) | `0x00173180` = 1,520,000 |
| 0x10A - 0x10D | 4 | BID Shares | Total bid shares (big-endian) | `0x0000012C` = 300 |
| 0x10E - 0x111 | 4 | BID Price | Best bid price (big-endian) | `0x0016CFD8` = 1,495,000 |
| 0x112 - 0x119 | 8 | Symbol | Stock ticker (ASCII) | `"AAPL    "` |

**Important Notes:**
1. **Byte Order:** Multi-byte integers are in **big-endian** format (network byte order)
2. **Price Format:** Prices are in fixed-point format (4 decimal places): `1,495,000 = $149.50`
3. **BBO Location:** Due to nibble-write order reversal, BBO data appears at **bytes 228-255** instead of bytes 0-27
4. **Symbol Padding:** Symbol names are 8 bytes, space-padded (e.g., `"AAPL    "`)

**Example Packet (AAPL):**
```
Hex dump (offsets 0x110-0x119, bytes 228-255 of payload):
0110: 00 00 61 a8 00 00 01 2c 00 17 31 80 00 00 01 2c
0120: 00 16 cf d8 41 41 50 4c 20 20 20 20

Decoded:
- Symbol: "AAPL    "
- BID: $149.50 (1,495,000), 300 shares
- ASK: $152.00 (1,520,000), 300 shares
- Spread: $2.50 (25,000)
*/
    BBOData BBOParser::parseBBOData(const uint8_t* data, size_t len) {
        BBOData bbo = {};
    
        try
        {
            // Expect UDP payload only. BBO occupies the last 28 bytes of the payload.
            const std::size_t BBO_SIZE = 28;
            if (len < BBO_SIZE) {
                bbo.valid = false;
                return bbo;
            }
            const uint8_t* bbo_data = data + (len - BBO_SIZE);

            // Parse big-endian integers
            uint32_t spread_be = 0, ask_shares_be = 0, ask_price_be = 0, bid_shares_be = 0, bid_price_be = 0;
            std::memcpy(&spread_be,     bbo_data + 0,  4);
            std::memcpy(&ask_shares_be, bbo_data + 4,  4);
            std::memcpy(&ask_price_be,  bbo_data + 8,  4);
            std::memcpy(&bid_shares_be, bbo_data + 12, 4);
            std::memcpy(&bid_price_be,  bbo_data + 16, 4);

            const uint32_t spread = ntohl(spread_be);
            const uint32_t ask_shares = ntohl(ask_shares_be);
            const uint32_t ask_price_fp = ntohl(ask_price_be);
            const uint32_t bid_shares = ntohl(bid_shares_be);
            const uint32_t bid_price_fp = ntohl(bid_price_be);

            // Assign with fixed-point scaling (4 decimals for prices)
            bbo.bid_price = static_cast<double>(bid_price_fp) / 10000.0;
            bbo.ask_price = static_cast<double>(ask_price_fp) / 10000.0;
            bbo.spread    = static_cast<double>(spread) / 10000.0;
            bbo.bid_shares = bid_shares;
            bbo.ask_shares = ask_shares;

            // Heuristics: if ask is missing or invalid, normalize to 0
            if (bbo.ask_shares == 0 || ask_price_fp == 0 || bbo.ask_price > 10000.0)
            {
                bbo.ask_price = 0.0;
            }
            // Derive spread if zero but both prices available
            if (bbo.spread == 0.0 && bbo.bid_price > 0.0 && bbo.ask_price > 0.0)
            {
                bbo.spread = bbo.ask_price - bbo.bid_price;
            }

            // Copy symbol (8 bytes) and trim trailing spaces
            char symbol[9];
            std::memcpy(symbol, bbo_data + 20, 8);
            symbol[8] = '\0';

            // Trim trailing spaces efficiently
            int last = 7;
            while (last >= 0 && symbol[last] == ' ') {
                last--;
            }
            symbol[last + 1] = '\0';

            bbo.set_symbol(std::string(symbol));
            bbo.timestamp_ns = get_timestamp_ns();
            bbo.valid = true;
        }
        catch (const std::exception &)
        {
            // Parsing error, return invalid BBO
            bbo.valid = false;
        }

        return bbo;
    }

    
    double BBOParser::hex_to_price(const std::string &hex_str)
    {
        try
        {
            // hex string to uint32_t using std::stoul(hex_str, nullptr, 16)
            // divide by 10000.0 to get price (FPGA uses 4 decimal places)
            // example: "0x0016E360" → 1500000 → 150.00
            return std::stoul(hex_str, nullptr, 16) / 10000.0;
        }
        catch (const std::exception &)
        {
            return 0.0;
        }
    }

    uint32_t BBOParser::hex_to_uint(const std::string &hex_str)
    {
        try
        {
            // parse hex string to uint32_t using std::stoul(hex_str, nullptr, 16)
            // example: "0x00000064" → 100
            return static_cast<uint32_t>(std::stoul(hex_str, nullptr, 16));
        }
        catch (const std::exception &)
        {
            return 0;
        }
    }

    std::string BBOParser::trim(const std::string &str)
    {
        // find first non-space character from left
        auto left = std::find_if(str.begin(), str.end(), [](char c)
                                 { return !std::isspace(c); });
        if (left == str.end())
        {
            return ""; // String is all whitespace
        }

        // find first non-space character from right
        auto right = std::find_if(str.rbegin(), str.rend(), [](char c)
                                  { return !std::isspace(c); })
                         .base();
        return std::string(left, right);
    }

    int64_t BBOParser::get_timestamp_ns()
    {
        // Use high_resolution_clock for better performance (no syscall on modern systems)
        auto now = std::chrono::high_resolution_clock::now();
        auto nanoseconds = std::chrono::duration_cast<std::chrono::nanoseconds>(now.time_since_epoch()).count();
        return nanoseconds;
    }

    std::string bbo_to_json(const BBOData &bbo)
    {
        // Thread-local buffer to avoid repeated allocations
        static thread_local std::ostringstream oss;
        oss.str("");
        oss.clear();

        // Calculate mid price for spread percent calculation
        double mid_price = (bbo.bid_price + bbo.ask_price) / 2.0;
        double spread_percent = (mid_price > 0.0) ? (bbo.spread / mid_price) * 100.0 : 0.0;

        oss << "{";
        oss << "\"type\":\"bbo\",";
        oss << "\"symbol\":\"" << bbo.symbol << "\",";
        oss << "\"timestamp\":" << bbo.timestamp_ns << ",";
        oss << "\"bid\":{";
        oss << "\"price\":" << std::fixed << std::setprecision(4) << bbo.bid_price << ",";
        oss << "\"shares\":" << bbo.bid_shares;
        oss << "},";
        oss << "\"ask\":{";
        oss << "\"price\":" << std::fixed << std::setprecision(4) << bbo.ask_price << ",";
        oss << "\"shares\":" << bbo.ask_shares;
        oss << "},";
        oss << "\"spread\":{";
        oss << "\"price\":" << std::fixed << std::setprecision(4) << bbo.spread << ",";
        oss << "\"percent\":" << std::fixed << std::setprecision(3) << spread_percent;
        oss << "}";
        oss << "}";

        return oss.str();
    }

} // namespace gateway
