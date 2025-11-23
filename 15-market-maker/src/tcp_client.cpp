/*
TCP Client Implementation
*/

#include "tcp_client.h"
#include "common/perf_monitor.h"
#include <nlohmann/json.hpp>
#include <iostream>
#include <stdexcept>
#include <spdlog/spdlog.h>

using json = nlohmann::json;

namespace gateway {

TCPClient::TCPClient(const std::string& host, int port)
    : host_(host), port_(port), io_context_() {
}

TCPClient::~TCPClient() {
    disconnect();
}

void TCPClient::connect() {
    if (connected_) {
        return;
    }

    try {
        // Resolve hostname
        boost::asio::ip::tcp::resolver resolver(io_context_);
        auto endpoints = resolver.resolve(host_, std::to_string(port_));

        // Create socket
        socket_ = std::make_unique<boost::asio::ip::tcp::socket>(io_context_);

        // Connect to server
        boost::asio::connect(*socket_, endpoints);
        connected_ = true;

        spdlog::info("Connected to Order Gateway at {}:{}", host_, port_);
    } catch (const std::exception& e) {
        connected_ = false;
        throw std::runtime_error("Failed to connect to " + host_ + ":" + std::to_string(port_) + ": " + e.what());
    }
}

void TCPClient::disconnect() {
    if (socket_ && socket_->is_open()) {
        boost::system::error_code ec;
        socket_->close(ec);
    }
    connected_ = false;
}

bool TCPClient::isConnected() const {
    return connected_ && socket_ && socket_->is_open();
}

BBOData TCPClient::read_bbo() {
    if (!isConnected()) {
        throw std::runtime_error("TCP client not connected");
    }

    try {
        // Read until newline (JSON messages are newline-delimited)
        std::size_t n = boost::asio::read_until(*socket_, receive_buffer_, '\n');

        if (n == 0) {
            throw std::runtime_error("Connection closed by server");
        }

        // Extract JSON string
        std::istream is(&receive_buffer_);
        std::string json_line;
        std::getline(is, json_line);

        // Parse JSON to BBO
        BBOData bbo;
        if (perf_monitor_) {
            LatencyMeasurement measure(*perf_monitor_);
            bbo = parseJsonBBO(json_line);
        } else {
            bbo = parseJsonBBO(json_line);
        }

        return bbo;

    } catch (const boost::system::system_error& e) {
        connected_ = false;
        throw std::runtime_error("TCP read error: " + std::string(e.what()));
    }
}

BBOData TCPClient::parseJsonBBO(const std::string& json_line) {
    BBOData bbo{};

    try {
        auto j = json::parse(json_line);

        // Check message type
        if (j.value("type", "") != "bbo") {
            bbo.valid = false;
            return bbo;
        }

        // Parse BBO fields
        bbo.symbol = j.value("symbol", "");
        bbo.timestamp_ns = j.value("timestamp", 0LL);

        if (j.contains("bid")) {
            auto bid = j["bid"];
            bbo.bid_price = bid.value("price", 0.0);
            bbo.bid_shares = bid.value("shares", 0);
        }

        if (j.contains("ask")) {
            auto ask = j["ask"];
            bbo.ask_price = ask.value("price", 0.0);
            bbo.ask_shares = ask.value("shares", 0);
        }

        if (j.contains("spread")) {
            auto spread = j["spread"];
            bbo.spread = spread.value("price", 0.0);
            // Note: spread_percent not in Project 15 BBOData structure
        }

        bbo.valid = true;

    } catch (const json::exception& e) {
        spdlog::warn("JSON parse error: {}", e.what());
        bbo.valid = false;
    }

    return bbo;
}

} // namespace gateway
