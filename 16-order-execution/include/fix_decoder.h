#pragma once

#include <string>
#include <map>
#include <stdexcept>
#include "../../common/order_data.h"

namespace fix {

/**
 * FIX Protocol 4.2 Message Decoder
 * Parses incoming FIX messages (ExecutionReport, Heartbeat, etc.)
 */
class FIXDecoder {
public:
    struct ExecutionReport {
        std::string order_id;       // Tag 11: ClOrdID
        std::string exec_id;        // Tag 17: ExecID
        char exec_type;             // Tag 150: ExecType
        char order_status;          // Tag 39: OrdStatus
        std::string symbol;         // Tag 55: Symbol
        char side;                  // Tag 54: Side
        uint32_t order_qty;         // Tag 38: OrderQty
        uint32_t cum_qty;           // Tag 14: CumQty
        uint32_t leaves_qty;        // Tag 151: LeavesQty
        double avg_price;           // Tag 6: AvgPx
        double last_px;             // Tag 31: LastPx
        uint32_t last_qty;          // Tag 32: LastQty
        std::string transact_time;  // Tag 60: TransactTime
        std::string text;           // Tag 58: Text (for rejects)
    };

    // Parse FIX message and extract fields
    std::map<std::string, std::string> parse_message(const std::string& fix_msg);

    // Get message type from parsed fields
    std::string get_msg_type(const std::map<std::string, std::string>& fields);

    // Decode ExecutionReport (MsgType=8)
    ExecutionReport decode_execution_report(const std::string& fix_msg);

    // Validate checksum
    bool validate_checksum(const std::string& fix_msg);

private:
    char fix_to_side(char fix_side);  // '1' -> 'B', '2' -> 'S'
};

} // namespace fix
