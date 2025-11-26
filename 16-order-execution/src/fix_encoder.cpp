#include "../include/fix_encoder.h"
#include <iomanip>
#include <sstream>

namespace fix {

std::string FIXEncoder::encode_new_order(const trading::OrderRequest& order) {
    std::ostringstream body;

    // Tag 11: ClOrdID
    body << "11=" << order.get_order_id() << "\x01";

    // Tag 21: HandlInst (1 = Automated execution)
    body << "21=1\x01";

    // Tag 55: Symbol
    body << "55=" << order.get_symbol() << "\x01";

    // Tag 54: Side
    body << "54=" << side_to_fix(order.side) << "\x01";

    // Tag 60: TransactTime
    body << "60=" << get_timestamp() << "\x01";

    // Tag 38: OrderQty
    body << "38=" << order.quantity << "\x01";

    // Tag 40: OrdType
    body << "40=" << order_type_to_fix(order.order_type) << "\x01";

    // Tag 44: Price (only for limit orders)
    if (order.order_type == 'L') {
        body << "44=" << std::fixed << std::setprecision(2) << order.price << "\x01";
    }

    // Tag 59: TimeInForce
    body << "59=" << tif_to_fix(order.time_in_force) << "\x01";

    return build_message("D", body.str());
}

std::string FIXEncoder::encode_cancel(const std::string& order_id, const std::string& orig_order_id) {
    std::ostringstream body;

    // Tag 11: ClOrdID (new order ID for cancel request)
    body << "11=" << order_id << "\x01";

    // Tag 41: OrigClOrdID
    body << "41=" << orig_order_id << "\x01";

    // Tag 60: TransactTime
    body << "60=" << get_timestamp() << "\x01";

    return build_message("F", body.str());
}

std::string FIXEncoder::encode_heartbeat() {
    return build_message("0", "");
}

std::string FIXEncoder::encode_logon() {
    std::ostringstream body;

    // Tag 98: EncryptMethod (0 = None)
    body << "98=0\x01";

    // Tag 108: HeartBtInt (30 seconds)
    body << "108=30\x01";

    return build_message("A", body.str());
}

std::string FIXEncoder::encode_logout() {
    return build_message("5", "");
}

std::string FIXEncoder::build_message(const std::string& msg_type, const std::string& body) {
    std::ostringstream msg;

    // Begin String (Tag 8)
    msg << "8=FIX.4.2\x01";

    // Calculate body length
    std::ostringstream header_body;
    header_body << "35=" << msg_type << "\x01";
    header_body << "49=" << sender_comp_id_ << "\x01";
    header_body << "56=" << target_comp_id_ << "\x01";
    header_body << "34=" << seq_num_++ << "\x01";
    header_body << "52=" << get_timestamp() << "\x01";
    header_body << body;

    // Body Length (Tag 9)
    msg << "9=" << header_body.str().length() << "\x01";
    msg << header_body.str();

    // Checksum (Tag 10)
    std::string checksum = calculate_checksum(msg.str());
    msg << "10=" << checksum << "\x01";

    return msg.str();
}

std::string FIXEncoder::calculate_checksum(const std::string& msg) {
    int sum = 0;
    for (char c : msg) {
        sum += static_cast<unsigned char>(c);
    }
    sum %= 256;

    std::ostringstream ss;
    ss << std::setfill('0') << std::setw(3) << sum;
    return ss.str();
}

std::string FIXEncoder::get_timestamp() {
    auto now = std::chrono::system_clock::now();
    auto time_t_now = std::chrono::system_clock::to_time_t(now);
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now.time_since_epoch()) % 1000;

    std::tm tm_now;
    gmtime_r(&time_t_now, &tm_now);

    std::ostringstream ss;
    ss << std::put_time(&tm_now, "%Y%m%d-%H:%M:%S");
    ss << "." << std::setfill('0') << std::setw(3) << ms.count();

    return ss.str();
}

char FIXEncoder::side_to_fix(char side) {
    return (side == 'B') ? '1' : '2';  // 1=Buy, 2=Sell
}

char FIXEncoder::order_type_to_fix(char type) {
    return (type == 'M') ? '1' : '2';  // 1=Market, 2=Limit
}

char FIXEncoder::tif_to_fix(char tif) {
    switch (tif) {
        case 'D': return '0';  // Day
        case 'I': return '3';  // IOC
        case 'F': return '4';  // FOK
        default: return '0';
    }
}

} // namespace fix
