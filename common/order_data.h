#pragma once

#include <string>
#include <cstdint>
#include <cstring>

namespace trading {

/**
 * Order Request data structure
 * Shared between Project 15 (Market Maker) and Project 16 (Order Execution Engine)
 *
 * IMPORTANT: Uses fixed-size char arrays for shared memory compatibility.
 * std::string contains pointers invalid across process boundaries.
 */
struct OrderRequest {
    static constexpr size_t ORDER_ID_MAX_LEN = 32;
    static constexpr size_t SYMBOL_MAX_LEN = 16;

    char order_id[ORDER_ID_MAX_LEN];   // Unique order ID
    char symbol[SYMBOL_MAX_LEN];       // Symbol (e.g., "AAPL")
    char side;                         // 'B' = Buy, 'S' = Sell
    char order_type;                   // 'L' = Limit, 'M' = Market
    char time_in_force;                // 'D' = Day, 'I' = IOC, 'F' = FOK
    double price;                      // Limit price (0.0 for market orders)
    uint32_t quantity;                 // Shares
    int64_t timestamp_ns;              // Order creation timestamp
    bool valid;                        // Structure validity flag

    OrderRequest() :
        side('B'), order_type('L'), time_in_force('D'),
        price(0.0), quantity(0), timestamp_ns(0), valid(false) {
        std::memset(order_id, 0, ORDER_ID_MAX_LEN);
        std::memset(symbol, 0, SYMBOL_MAX_LEN);
    }

    void set_order_id(const std::string& id) {
        std::strncpy(order_id, id.c_str(), ORDER_ID_MAX_LEN - 1);
        order_id[ORDER_ID_MAX_LEN - 1] = '\0';
    }

    void set_symbol(const std::string& sym) {
        std::strncpy(symbol, sym.c_str(), SYMBOL_MAX_LEN - 1);
        symbol[SYMBOL_MAX_LEN - 1] = '\0';
    }

    std::string get_order_id() const {
        return std::string(order_id);
    }

    std::string get_symbol() const {
        return std::string(symbol);
    }
};

/**
 * Fill Notification data structure
 * Sent from Project 16 (Order Execution Engine) back to Project 15 (Market Maker)
 */
struct FillNotification {
    static constexpr size_t ORDER_ID_MAX_LEN = 32;
    static constexpr size_t SYMBOL_MAX_LEN = 16;
    static constexpr size_t EXEC_ID_MAX_LEN = 32;

    char order_id[ORDER_ID_MAX_LEN];   // Original order ID
    char exec_id[EXEC_ID_MAX_LEN];     // Execution ID from exchange
    char symbol[SYMBOL_MAX_LEN];       // Symbol
    char side;                         // 'B' = Buy, 'S' = Sell
    uint32_t fill_qty;                 // Shares filled in this report
    uint32_t cum_qty;                  // Total shares filled
    double avg_price;                  // Average fill price
    int64_t transact_time;             // Exchange timestamp
    bool is_complete;                  // true if fully filled
    bool valid;

    FillNotification() :
        side('B'), fill_qty(0), cum_qty(0), avg_price(0.0),
        transact_time(0), is_complete(false), valid(false) {
        std::memset(order_id, 0, ORDER_ID_MAX_LEN);
        std::memset(exec_id, 0, EXEC_ID_MAX_LEN);
        std::memset(symbol, 0, SYMBOL_MAX_LEN);
    }

    void set_order_id(const std::string& id) {
        std::strncpy(order_id, id.c_str(), ORDER_ID_MAX_LEN - 1);
        order_id[ORDER_ID_MAX_LEN - 1] = '\0';
    }

    void set_exec_id(const std::string& id) {
        std::strncpy(exec_id, id.c_str(), EXEC_ID_MAX_LEN - 1);
        exec_id[EXEC_ID_MAX_LEN - 1] = '\0';
    }

    void set_symbol(const std::string& sym) {
        std::strncpy(symbol, sym.c_str(), SYMBOL_MAX_LEN - 1);
        symbol[SYMBOL_MAX_LEN - 1] = '\0';
    }

    std::string get_order_id() const {
        return std::string(order_id);
    }

    std::string get_exec_id() const {
        return std::string(exec_id);
    }

    std::string get_symbol() const {
        return std::string(symbol);
    }
};

}  // namespace trading
