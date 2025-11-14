#include "bbo_parser.h"
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <chrono>
#include <ctime>
#include <stdexcept>

namespace gateway
{

    BBOData BBOParser::parse(const std::string &line)
    {
        BBOData bbo;
        bbo.valid = false;

        // Check for NODATA
        if (line.find("NODATA") != std::string::npos)
        {
            return bbo;
        }

        try
        {
            // Extract symbol from "[BBO:XXXX]"
            size_t bbo_pos = line.find("BBO:");
            size_t close_bracket = line.find("]", bbo_pos);
            if (bbo_pos == std::string::npos || close_bracket == std::string::npos)
            {
                return bbo; // Invalid format
            }
            bbo.symbol = trim(line.substr(bbo_pos + 4, close_bracket - bbo_pos - 4));

            // Extract bid price hex (after "Bid:0x", before " (")
            size_t bid_start = line.find("Bid:0x");
            size_t bid_space = line.find(" (", bid_start);
            if (bid_start == std::string::npos || bid_space == std::string::npos)
            {
                return bbo; // Invalid format
            }
            std::string bid_price_hex = line.substr(bid_start + 6, bid_space - bid_start - 6);
            bbo.bid_price = hex_to_price(bid_price_hex);

            // Extract bid shares hex (after "(0x", before ")")
            size_t bid_shares_start = line.find("(0x", bid_space);
            size_t bid_shares_end = line.find(")", bid_shares_start);
            if (bid_shares_start == std::string::npos || bid_shares_end == std::string::npos)
            {
                return bbo; // Invalid format
            }
            std::string bid_shares_hex = line.substr(bid_shares_start + 3, bid_shares_end - bid_shares_start - 3);
            bbo.bid_shares = hex_to_uint(bid_shares_hex);

            // Extract ask price hex (after "Ask:0x", before " (")
            size_t ask_start = line.find("Ask:0x");
            size_t ask_space = line.find(" (", ask_start);
            if (ask_start == std::string::npos || ask_space == std::string::npos)
            {
                return bbo; // Invalid format
            }
            std::string ask_price_hex = line.substr(ask_start + 6, ask_space - ask_start - 6);
            bbo.ask_price = hex_to_price(ask_price_hex);

            // Extract ask shares hex (after "(0x", before ")")
            size_t ask_shares_start = line.find("(0x", ask_space);
            size_t ask_shares_end = line.find(")", ask_shares_start);
            if (ask_shares_start == std::string::npos || ask_shares_end == std::string::npos)
            {
                return bbo; // Invalid format
            }
            std::string ask_shares_hex = line.substr(ask_shares_start + 3, ask_shares_end - ask_shares_start - 3);
            bbo.ask_shares = hex_to_uint(ask_shares_hex);

            // Extract spread hex (after "Spr:0x", before end or "|")
            size_t spr_start = line.find("Spr:0x");
            if (spr_start == std::string::npos)
            {
                return bbo; // Invalid format
            }
            size_t spr_end = line.find_first_of(" |\n\r", spr_start + 6);
            if (spr_end == std::string::npos)
            {
                spr_end = line.length();
            }
            std::string spread_hex = line.substr(spr_start + 6, spr_end - spr_start - 6);
            bbo.spread = hex_to_price(spread_hex);

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
        // get current time using std::chrono::system_clock::now()
        auto now = std::chrono::system_clock::now();
        
        // convert to nanoseconds since Unix epoch
        auto duration = now.time_since_epoch();
        auto nanoseconds = std::chrono::duration_cast<std::chrono::nanoseconds>(duration).count();
        
        return nanoseconds;
    }

    std::string bbo_to_json(const BBOData &bbo)
    {
        // Format JSON according to SYSTEM_ARCHITECTURE.md specification
        std::ostringstream oss;
        
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
