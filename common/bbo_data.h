#pragma once

#include <string>
#include <cstdint>
#include <cstring>

namespace gateway {

/**
 * Best Bid/Offer (BBO) data structure
 * Shared between Project 14 (Order Gateway) and Project 15 (Market Maker)
 *
 * IMPORTANT: Uses fixed-size char array for symbol instead of std::string
 * because this struct is used in shared memory between processes.
 * std::string contains pointers that are invalid across process boundaries.
 */
struct BBOData {
    static constexpr size_t SYMBOL_MAX_LEN = 16;
    char symbol[SYMBOL_MAX_LEN];  // Fixed-size for shared memory compatibility
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
        spread(0.0), timestamp_ns(0), valid(false) {
        std::memset(symbol, 0, SYMBOL_MAX_LEN);
    }

    // Helper to set symbol from std::string
    void set_symbol(const std::string& sym) {
        std::strncpy(symbol, sym.c_str(), SYMBOL_MAX_LEN - 1);
        symbol[SYMBOL_MAX_LEN - 1] = '\0';  // Ensure null termination
    }

    // Helper to get symbol as std::string
    std::string get_symbol() const {
        return std::string(symbol);
    }
};

}  // namespace gateway
