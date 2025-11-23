/*
TCP Client - Connects to Project 14 Order Gateway
Receives JSON BBO messages over TCP
*/

#pragma once

#include <string>
#include <memory>
#include <boost/asio.hpp>
#include "bbo_parser.h"

namespace gateway {

    class PerfMonitor;  // Forward declaration

    class TCPClient {
    public:
        /**
         * Create TCP client to connect to Order Gateway
         *
         * @param host Gateway hostname/IP (e.g., "localhost" or "192.168.0.99")
         * @param port TCP port (default: 9999)
         */
        explicit TCPClient(const std::string& host, int port);
        ~TCPClient();

        // Connect to server
        void connect();

        // Disconnect from server
        void disconnect();

        // Read next BBO message (blocking)
        BBOData read_bbo();

        // Check if connected
        bool isConnected() const;

        // Set performance monitor (optional)
        void setPerfMonitor(PerfMonitor* monitor) { perf_monitor_ = monitor; }

    private:
        // Parse JSON BBO message
        BBOData parseJsonBBO(const std::string& json_line);

        // Connection info
        std::string host_;
        int port_;

        // Boost.Asio components
        boost::asio::io_context io_context_;
        std::unique_ptr<boost::asio::ip::tcp::socket> socket_;
        boost::asio::streambuf receive_buffer_;

        // Connection state
        bool connected_{false};

        // Performance monitoring
        PerfMonitor* perf_monitor_{nullptr};
    };

} // namespace gateway
