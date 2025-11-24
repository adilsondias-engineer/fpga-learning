#pragma once

#include <string>
#include <cstdint>

namespace gateway {

/**
 * Best Bid/Offer (BBO) data structure
 * Shared between Project 14 (Order Gateway) and Project 15 (Market Maker)
 */
struct BBOData {
    std::string symbol;
    double bid_price;
    uint32_t bid_shares;
    double ask_price;
    uint32_t ask_shares;
    double spread;
    int64_t timestamp_ns;
    bool valid;

    BBOData() :
        bid_price(0.0), bid_shares(0),
        ask_price(0.0), ask_shares(0),
        spread(0.0), timestamp_ns(0), valid(false) {}
};

}  // namespace gateway
