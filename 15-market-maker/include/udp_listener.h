/*
UDP Listener
Listens for UDP packets from FPGA and parses them into BBOData
*/

#pragma once

#include <string>
#include <vector>
#include <memory>
#include <thread>
#include <mutex>
#include <boost/asio.hpp>
#include "bbo_parser.h"
#include <queue>
#include <condition_variable>

#define UDP_LISTEN_PORT 5000

#include "common/perf_monitor.h"

namespace gateway {

    class PerfMonitor;  // Forward declaration

    class UDPListener {
    public:
        explicit UDPListener(const std::string& ip_address = "0.0.0.0", int port = UDP_LISTEN_PORT);
        ~UDPListener();
        void start();
        void stop();
        void run();
        BBOData read_bbo();
        bool isRunning() const;

        // Method to set performance monitor
        void setPerfMonitor(PerfMonitor* monitor) { perf_monitor_ = monitor; }

    private:
        static constexpr size_t MAX_QUEUE_SIZE = 1000;
        bool running_{false};
        std::string ip_address_;
        int port_;
        boost::asio::io_context io_;
        boost::asio::ip::udp::socket socket_{io_};
        boost::asio::ip::udp::endpoint endpoint_;
        boost::asio::ip::udp::endpoint sender_endpoint_;
        std::vector<uint8_t> buffer_;
        std::thread thread_;
        std::mutex mutex_;
        std::condition_variable condition_;
        std::queue<BBOData> bbo_queue_;
        std::mutex bbo_queue_mutex_;
        std::condition_variable bbo_queue_condition_;
        void thread_func();
        void do_receive();
        void on_receive(const boost::system::error_code& error, std::size_t bytes_transferred);
        void process_bbo(const BBOData& bbo);

        // Performance monitoring
        PerfMonitor* perf_monitor_ = nullptr;
    };
}