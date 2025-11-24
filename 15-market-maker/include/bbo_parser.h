#pragma once

#include "bbo_data.h"  // BBOData from common
#include <string>

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
        

    private:
        
    };

    /**
     * Convert BBOData to JSON string
     * @param bbo BBO data structure
     * @return JSON string
     */
    std::string bbo_to_json(const BBOData &bbo);

} // namespace gateway
