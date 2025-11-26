#include <iostream>
#include <boost/asio.hpp>
#include <spdlog/spdlog.h>
#include "../include/fix_encoder.h"
#include "../include/fix_decoder.h"

using boost::asio::ip::tcp;

/**
 * Simulated Exchange - Minimal FIX Acceptor
 * Accepts FIX connections and immediately fills all orders
 */
class SimulatedExchange {
public:
    SimulatedExchange(boost::asio::io_context& io_context, uint16_t port)
        : acceptor_(io_context, tcp::endpoint(tcp::v4(), port))
        , socket_(io_context)
        , encoder_("SIMEXCH", "MMFIRM")
        , exec_id_counter_(1) {
        spdlog::info("Simulated Exchange started on port {}", port);
    }

    void run() {
        accept_connection();
    }

private:
    void accept_connection() {
        acceptor_.async_accept(socket_, [this](boost::system::error_code ec) {
            if (!ec) {
                spdlog::info("Client connected");
                handle_connection();
            }
            accept_connection();
        });
    }

    void handle_connection() {
        read_message();
    }

    void read_message() {
        auto buffer = std::make_shared<boost::asio::streambuf>();
        boost::asio::async_read_until(socket_, *buffer, "\x0110=",
            [this, buffer](boost::system::error_code ec, std::size_t bytes_transferred) {
                if (!ec) {
                    std::string msg{
                        boost::asio::buffers_begin(buffer->data()),
                        boost::asio::buffers_begin(buffer->data()) + bytes_transferred
                    };

                    // Find complete message (ends with checksum + SOH)
                    size_t checksum_end = msg.find('\x01', msg.find("10="));
                    if (checksum_end != std::string::npos) {
                        std::string complete_msg = msg.substr(0, checksum_end + 1);
                        handle_message(complete_msg);
                    }

                    read_message();
                }
            });
    }

    void handle_message(const std::string& fix_msg) {
        auto fields = decoder_.parse_message(fix_msg);
        std::string msg_type = decoder_.get_msg_type(fields);

        spdlog::debug("Received FIX message: MsgType={}", msg_type);

        if (msg_type == "A") {  // Logon
            send_logon_ack();
        } else if (msg_type == "D") {  // NewOrderSingle
            process_new_order(fields);
        } else if (msg_type == "0") {  // Heartbeat
            // Respond with heartbeat
            send_message(encoder_.encode_heartbeat());
        }
    }

    void send_logon_ack() {
        std::string logon = encoder_.encode_logon();
        send_message(logon);
        spdlog::info("Sent Logon acknowledgment");
    }

    void process_new_order(const std::map<std::string, std::string>& fields) {
        std::string order_id = fields.at("11");
        std::string symbol = fields.at("55");
        char side = fields.at("54")[0];
        uint32_t qty = std::stoul(fields.at("38"));
        double price = fields.count("44") ? std::stod(fields.at("44")) : 0.0;

        spdlog::info("Received order: {} {} {} @{}", order_id, symbol, qty, price);

        // Send immediate fill
        send_fill(order_id, symbol, side, qty, price);
    }

    void send_fill(const std::string& order_id, const std::string& symbol,
                   char side, uint32_t qty, double price) {
        std::ostringstream body;

        // Tag 11: ClOrdID
        body << "11=" << order_id << "\x01";

        // Tag 17: ExecID
        body << "17=EXEC" << exec_id_counter_++ << "\x01";

        // Tag 150: ExecType (2 = Fill)
        body << "150=2\x01";

        // Tag 39: OrdStatus (2 = Filled)
        body << "39=2\x01";

        // Tag 55: Symbol
        body << "55=" << symbol << "\x01";

        // Tag 54: Side
        body << "54=" << side << "\x01";

        // Tag 38: OrderQty
        body << "38=" << qty << "\x01";

        // Tag 14: CumQty
        body << "14=" << qty << "\x01";

        // Tag 151: LeavesQty
        body << "151=0\x01";

        // Tag 6: AvgPx
        body << "6=" << std::fixed << std::setprecision(2) << price << "\x01";

        // Tag 31: LastPx
        body << "31=" << std::fixed << std::setprecision(2) << price << "\x01";

        // Tag 32: LastQty
        body << "32=" << qty << "\x01";

        std::string exec_report = build_exec_report(body.str());
        send_message(exec_report);

        spdlog::info("Sent fill for order {}: {} @ {}", order_id, qty, price);
    }

    std::string build_exec_report(const std::string& body) {
        std::ostringstream msg;
        msg << "8=FIX.4.2\x01";

        std::ostringstream header_body;
        header_body << "35=8\x01";  // ExecutionReport
        header_body << "49=SIMEXCH\x01";
        header_body << "56=MMFIRM\x01";
        header_body << "34=" << encoder_.get_seq_num() << "\x01";
        header_body << "52=" << get_timestamp() << "\x01";
        header_body << body;

        msg << "9=" << header_body.str().length() << "\x01";
        msg << header_body.str();

        std::string checksum = calculate_checksum(msg.str());
        msg << "10=" << checksum << "\x01";

        return msg.str();
    }

    std::string calculate_checksum(const std::string& msg) {
        int sum = 0;
        for (char c : msg) {
            sum += static_cast<unsigned char>(c);
        }
        sum %= 256;

        std::ostringstream ss;
        ss << std::setfill('0') << std::setw(3) << sum;
        return ss.str();
    }

    std::string get_timestamp() {
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

    void send_message(const std::string& msg) {
        boost::asio::async_write(socket_, boost::asio::buffer(msg),
            [](boost::system::error_code ec, std::size_t /*bytes_transferred*/) {
                if (ec) {
                    spdlog::error("Send error: {}", ec.message());
                }
            });
    }

    tcp::acceptor acceptor_;
    tcp::socket socket_;
    fix::FIXEncoder encoder_;
    fix::FIXDecoder decoder_;
    uint32_t exec_id_counter_;
};

int main() {
    spdlog::set_level(spdlog::level::info);
    spdlog::info("Starting Simulated Exchange...");

    try {
        boost::asio::io_context io_context;
        SimulatedExchange exchange(io_context, 5001);
        exchange.run();
        io_context.run();
    } catch (const std::exception& e) {
        spdlog::error("Exception: {}", e.what());
        return 1;
    }

    return 0;
}
