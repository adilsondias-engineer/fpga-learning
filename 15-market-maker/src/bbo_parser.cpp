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
