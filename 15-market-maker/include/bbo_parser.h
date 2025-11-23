#pragma once

#include <string>
#include <cstdint>

namespace gateway
{

    /**
     * BBO Data structure
     * Represents parsed Best Bid/Offer data from FPGA UART output
     */
    struct BBOData
    {
        std::string symbol;      // e.g., "AAPL"
        double bid_price;         // e.g., 150.00 (4 decimal places)
        uint32_t bid_shares;      // e.g., 100
        double ask_price;         // e.g., 149.95
        uint32_t ask_shares;      // e.g., 200
        double spread;            // e.g., 0.50
        int64_t timestamp_ns;     // Nanoseconds since Unix epoch
        bool valid;               // true if BBO data, false if NODATA
    };

    /**
     * BBO Parser
     * Parses ASCII BBO format from FPGA UART output
     *
     * Input format:
     *   Valid BBO: [BBO:AAPL    ]Bid:0x0016E360 (0x00000064) | Ask:0x0016D99C (0x000000C8) | Spr:0x00001388
     *   No BBO:    [BBO:NODATA  ]
     */
    class BBOParser
    {
    public:
        

    private:
        
    };

    /**
     * Convert BBOData to JSON string
     * @param bbo BBO data structure
     * @return JSON string
     */
    std::string bbo_to_json(const BBOData &bbo);

} // namespace gateway
