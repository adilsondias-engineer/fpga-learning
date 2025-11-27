#pragma once

#include <string>
#include <random>
#include <boost/asio.hpp>
#include "fix_encoder.h"
#include "fix_decoder.h"

namespace exchange {

/**
 * Simulated Exchange - FIX Acceptor for Testing
 * Accepts FIX connections, receives orders, generates fills
 */
class SimulatedExchange {
public:
    SimulatedExchange(boost::asio::io_context& io_context, uint16_t port);

    void set_fill_latency_us(uint64_t latency_us) { fill_latency_us_ = latency_us; }
    void set_fill_ratio(double ratio) { fill_ratio_ = ratio; }  // 0.0 - 1.0
    void set_reject_rate(double rate) { reject_rate_ = rate; }  // 0.0 - 1.0

    void run();

private:
    void accept_connection();
    void handle_message(const std::string& fix_msg);
    void process_logon(const std::map<std::string, std::string>& fields);
    void process_new_order(const std::map<std::string, std::string>& fields);
    void send_execution_report(const std::string& order_id, const std::string& symbol,
                               char side, uint32_t qty, double price, char exec_type, char order_status);
    void send_heartbeat();
    void send_message(const std::string& msg);

    boost::asio::io_context& io_context_;
    boost::asio::ip::tcp::acceptor acceptor_;
    boost::asio::ip::tcp::socket socket_;

    fix::FIXEncoder encoder_;
    fix::FIXDecoder decoder_;

    uint64_t fill_latency_us_;
    double fill_ratio_;
    double reject_rate_;

    std::mt19937 rng_;
    std::uniform_real_distribution<double> dist_;

    uint32_t exec_id_counter_;
    bool logged_in_;
};

} // namespace exchange
