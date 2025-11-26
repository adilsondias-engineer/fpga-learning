#include <iostream>
#include <fstream>
#include <signal.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <spdlog/spdlog.h>
#include <boost/asio.hpp>
#include <nlohmann/json.hpp>
#include "../include/fix_encoder.h"
#include "../include/fix_decoder.h"
#include "../../common/disruptor/OrderRingBuffer.h"
#include "../../common/disruptor/FillRingBuffer.h"

using json = nlohmann::json;
volatile sig_atomic_t g_running = 1;

void signal_handler(int signal) {
    spdlog::info("Received signal {}, shutting down...", signal);
    g_running = 0;
}

class OrderExecutionEngine {
public:
    OrderExecutionEngine(const json& config)
        : io_context_()
        , socket_(io_context_)
        , encoder_(config["fix"]["sender_comp_id"], config["fix"]["target_comp_id"])
        , order_shm_fd_(-1)
        , fill_shm_fd_(-1)
        , order_ring_(nullptr)
        , fill_ring_(nullptr)
        , orders_processed_(0) {

        // Initialize shared memory for orders (consumer)
        std::string order_path = config["disruptor"]["order_queue_path"];
        order_shm_fd_ = shm_open(order_path.c_str(), O_RDWR, 0666);
        if (order_shm_fd_ == -1) {
            throw std::runtime_error("Failed to open order shared memory");
        }

        void* order_addr = mmap(nullptr, sizeof(disruptor::OrderRingBuffer),
                               PROT_READ | PROT_WRITE, MAP_SHARED, order_shm_fd_, 0);
        if (order_addr == MAP_FAILED) {
            throw std::runtime_error("Failed to mmap order shared memory");
        }
        order_ring_ = static_cast<disruptor::OrderRingBuffer*>(order_addr);

        // Initialize shared memory for fills (producer)
        std::string fill_path = config["disruptor"]["fill_queue_path"];
        fill_shm_fd_ = shm_open(fill_path.c_str(), O_CREAT | O_RDWR, 0666);
        if (fill_shm_fd_ == -1) {
            throw std::runtime_error("Failed to create fill shared memory");
        }

        ftruncate(fill_shm_fd_, sizeof(disruptor::FillRingBuffer));

        void* fill_addr = mmap(nullptr, sizeof(disruptor::FillRingBuffer),
                              PROT_READ | PROT_WRITE, MAP_SHARED, fill_shm_fd_, 0);
        if (fill_addr == MAP_FAILED) {
            throw std::runtime_error("Failed to mmap fill shared memory");
        }
        fill_ring_ = new (fill_addr) disruptor::FillRingBuffer();

        spdlog::info("Order Execution Engine initialized");
    }

    ~OrderExecutionEngine() {
        if (order_ring_) {
            munmap(order_ring_, sizeof(disruptor::OrderRingBuffer));
        }
        if (fill_ring_) {
            munmap(fill_ring_, sizeof(disruptor::FillRingBuffer));
        }
        if (order_shm_fd_ != -1) close(order_shm_fd_);
        if (fill_shm_fd_ != -1) close(fill_shm_fd_);
    }

    void connect_to_exchange(const std::string& host, uint16_t port) {
        using boost::asio::ip::tcp;

        tcp::resolver resolver(io_context_);
        auto endpoints = resolver.resolve(host, std::to_string(port));

        boost::asio::connect(socket_, endpoints);
        spdlog::info("Connected to exchange at {}:{}", host, port);

        // Send logon
        std::string logon = encoder_.encode_logon();
        boost::asio::write(socket_, boost::asio::buffer(logon));
        spdlog::info("Sent FIX Logon");
    }

    void run() {
        spdlog::info("Order Execution Engine running...");

        while (g_running) {
            // Try to read order from ring buffer
            trading::OrderRequest order;
            if (order_ring_->try_read(order)) {
                process_order(order);
            }

            // Try to read execution reports from exchange
            read_execution_reports();

            std::this_thread::yield();
        }

        spdlog::info("Processed {} orders", orders_processed_);
    }

private:
    void process_order(const trading::OrderRequest& order) {
        spdlog::info("Processing order: {} {} {} @{}",
                    order.get_order_id(), order.get_symbol(),
                    order.quantity, order.price);

        // Encode as FIX NewOrderSingle
        std::string fix_msg = encoder_.encode_new_order(order);

        // Send to exchange
        try {
            boost::asio::write(socket_, boost::asio::buffer(fix_msg));
            orders_processed_++;
            spdlog::debug("Sent order to exchange");
        } catch (const std::exception& e) {
            spdlog::error("Failed to send order: {}", e.what());
        }
    }

    void read_execution_reports() {
        // Non-blocking read
        boost::system::error_code ec;
        size_t available = socket_.available(ec);

        if (available > 0) {
            std::vector<char> buffer(available);
            size_t len = socket_.read_some(boost::asio::buffer(buffer), ec);

            if (!ec && len > 0) {
                std::string msg(buffer.begin(), buffer.begin() + len);
                process_execution_report(msg);
            }
        }
    }

    void process_execution_report(const std::string& fix_msg) {
        try {
            auto report = decoder_.decode_execution_report(fix_msg);

            spdlog::info("Received ExecutionReport: {} ExecType={} Status={} Qty={} AvgPx={}",
                        report.order_id, report.exec_type, report.order_status,
                        report.cum_qty, report.avg_price);

            // Create fill notification
            trading::FillNotification fill;
            fill.set_order_id(report.order_id);
            fill.set_exec_id(report.exec_id);
            fill.set_symbol(report.symbol);
            fill.side = report.side;
            fill.fill_qty = report.last_qty;
            fill.cum_qty = report.cum_qty;
            fill.avg_price = report.avg_price;
            fill.transact_time = std::chrono::system_clock::now().time_since_epoch().count();
            fill.is_complete = (report.order_status == '2');  // '2' = Filled
            fill.valid = true;

            // Publish fill to Project 15
            fill_ring_->publish(fill);
            spdlog::debug("Published fill notification to Project 15");

        } catch (const std::exception& e) {
            spdlog::error("Failed to process execution report: {}", e.what());
        }
    }

    boost::asio::io_context io_context_;
    boost::asio::ip::tcp::socket socket_;
    fix::FIXEncoder encoder_;
    fix::FIXDecoder decoder_;

    int order_shm_fd_;
    int fill_shm_fd_;
    disruptor::OrderRingBuffer* order_ring_;
    disruptor::FillRingBuffer* fill_ring_;

    uint64_t orders_processed_;
};

int main() {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    spdlog::set_level(spdlog::level::info);
    spdlog::info("Starting Order Execution Engine...");

    try {
        // Load configuration
        std::ifstream config_file("config.json");
        json config = json::parse(config_file);

        // Create and run engine
        OrderExecutionEngine engine(config);
        engine.connect_to_exchange(
            config["exchange"]["host"],
            config["exchange"]["port"]
        );
        engine.run();

    } catch (const std::exception& e) {
        spdlog::error("Fatal error: {}", e.what());
        return 1;
    }

    spdlog::info("Order Execution Engine stopped");
    return 0;
}
