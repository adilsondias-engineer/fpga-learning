#pragma once

#include "bbo_data.h"  // BBOData from common
#include <string>
#include <cstdint>

namespace gateway
{

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
        
        /**
         * Parse BBO data from UDP packet
         * @param data Pointer to UDP packet data
         * @param len Length of UDP packet data
         * @return BBOData struct (valid=false if NODATA or parse error)
         */
        static BBOData parseBBOData(const uint8_t* data, size_t len);
        /**
         * Convert hex string to price (4 decimal places)
         * @param hex_str Hex string (e.g., "0x0016E360")
         * @return Price in dollars (e.g., 150.00)
         */
        static double hex_to_price(const std::string &hex_str);

        /**
         * Convert hex string to unsigned integer
         * @param hex_str Hex string (e.g., "0x00000064")
         * @return Integer value (e.g., 100)
         */
        static uint32_t hex_to_uint(const std::string &hex_str);

    private:
        /**
         * Trim leading and trailing whitespace
         * @param str String to trim
         * @return Trimmed string
         */
        static std::string trim(const std::string &str);

        /**
         * Get current timestamp in nanoseconds since Unix epoch
         * @return Timestamp in nanoseconds (e.g., 1699824000123456789)
         */
        static int64_t get_timestamp_ns();
    };

    /**
     * Convert BBOData to JSON string
     * @param bbo BBO data structure
     * @return JSON string
     */
    std::string bbo_to_json(const BBOData &bbo);

} // namespace gateway
