#pragma once

#include <string>
#include <sstream>
#include <iomanip>
#include <chrono>
#include "../../common/order_data.h"

namespace fix {

/**
 * FIX Protocol 4.2 Message Encoder
 * Generates FIX messages for order submission
 */
class FIXEncoder {
public:
    FIXEncoder(const std::string& sender_comp_id, const std::string& target_comp_id)
        : sender_comp_id_(sender_comp_id)
        , target_comp_id_(target_comp_id)
        , seq_num_(1) {}

    // Encode NewOrderSingle (MsgType=D)
    std::string encode_new_order(const trading::OrderRequest& order);

    // Encode OrderCancelRequest (MsgType=F)
    std::string encode_cancel(const std::string& order_id, const std::string& orig_order_id);

    // Encode Heartbeat (MsgType=0)
    std::string encode_heartbeat();

    // Encode Logon (MsgType=A)
    std::string encode_logon();

    // Encode Logout (MsgType=5)
    std::string encode_logout();

    uint32_t get_seq_num() const { return seq_num_; }
    void set_seq_num(uint32_t seq) { seq_num_ = seq; }

private:
    std::string build_message(const std::string& msg_type, const std::string& body);
    std::string calculate_checksum(const std::string& msg);
    std::string get_timestamp();
    char side_to_fix(char side);  // 'B' -> '1', 'S' -> '2'
    char order_type_to_fix(char type);  // 'L' -> '2', 'M' -> '1'
    char tif_to_fix(char tif);  // 'D' -> '0', 'I' -> '3', 'F' -> '4'

    std::string sender_comp_id_;
    std::string target_comp_id_;
    uint32_t seq_num_;
};

} // namespace fix
