#include "../include/fix_decoder.h"
#include <sstream>

namespace fix {

std::map<std::string, std::string> FIXDecoder::parse_message(const std::string& fix_msg) {
    std::map<std::string, std::string> fields;

    size_t pos = 0;
    while (pos < fix_msg.length()) {
        // Find the tag=value delimiter
        size_t eq_pos = fix_msg.find('=', pos);
        if (eq_pos == std::string::npos) break;

        // Find the SOH (0x01) separator
        size_t soh_pos = fix_msg.find('\x01', eq_pos);
        if (soh_pos == std::string::npos) soh_pos = fix_msg.length();

        // Extract tag and value
        std::string tag = fix_msg.substr(pos, eq_pos - pos);
        std::string value = fix_msg.substr(eq_pos + 1, soh_pos - eq_pos - 1);

        fields[tag] = value;

        pos = soh_pos + 1;
    }

    return fields;
}

std::string FIXDecoder::get_msg_type(const std::map<std::string, std::string>& fields) {
    auto it = fields.find("35");
    if (it != fields.end()) {
        return it->second;
    }
    return "";
}

FIXDecoder::ExecutionReport FIXDecoder::decode_execution_report(const std::string& fix_msg) {
    auto fields = parse_message(fix_msg);

    ExecutionReport report;

    report.order_id = fields["11"];
    report.exec_id = fields["17"];
    report.exec_type = fields["150"].empty() ? '0' : fields["150"][0];
    report.order_status = fields["39"].empty() ? '0' : fields["39"][0];
    report.symbol = fields["55"];
    report.side = fix_to_side(fields["54"].empty() ? '1' : fields["54"][0]);

    report.order_qty = fields["38"].empty() ? 0 : std::stoul(fields["38"]);
    report.cum_qty = fields["14"].empty() ? 0 : std::stoul(fields["14"]);
    report.leaves_qty = fields["151"].empty() ? 0 : std::stoul(fields["151"]);

    report.avg_price = fields["6"].empty() ? 0.0 : std::stod(fields["6"]);
    report.last_px = fields["31"].empty() ? 0.0 : std::stod(fields["31"]);
    report.last_qty = fields["32"].empty() ? 0 : std::stoul(fields["32"]);

    report.transact_time = fields["60"];
    report.text = fields["58"];

    return report;
}

bool FIXDecoder::validate_checksum(const std::string& fix_msg) {
    // Find checksum field (Tag 10)
    size_t checksum_pos = fix_msg.rfind("10=");
    if (checksum_pos == std::string::npos) return false;

    // Extract expected checksum
    std::string checksum_str = fix_msg.substr(checksum_pos + 3, 3);
    int expected_checksum = std::stoi(checksum_str);

    // Calculate actual checksum (sum of all bytes before checksum field)
    int sum = 0;
    for (size_t i = 0; i < checksum_pos; i++) {
        sum += static_cast<unsigned char>(fix_msg[i]);
    }
    int calculated_checksum = sum % 256;

    return expected_checksum == calculated_checksum;
}

char FIXDecoder::fix_to_side(char fix_side) {
    return (fix_side == '1') ? 'B' : 'S';  // 1=Buy, 2=Sell
}

} // namespace fix
