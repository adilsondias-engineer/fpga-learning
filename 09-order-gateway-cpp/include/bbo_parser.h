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
        /**
         * Parse BBO line from FPGA
         * @param line ASCII line from UART (ending with \n)
         * @return BBOData struct (valid=false if NODATA or parse error)
         */
        static BBOData parse(const std::string &line);

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
