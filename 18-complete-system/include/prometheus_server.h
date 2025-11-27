#pragma once

#include "metrics_aggregator.h"
#include <string>
#include <thread>
#include <atomic>
#include <cstdint>

namespace trading_system {

/**
 * Simple HTTP server for Prometheus /metrics endpoint
 */
class PrometheusServer {
public:
    /**
     * Create Prometheus HTTP server
     * @param port HTTP port (default: 9094)
     * @param aggregator Metrics aggregator to export from
     */
    explicit PrometheusServer(uint16_t port, MetricsAggregator* aggregator);

    ~PrometheusServer();

    /**
     * Start HTTP server
     */
    void start();

    /**
     * Stop HTTP server
     */
    void stop();

    /**
     * Check if server is running
     */
    bool is_running() const { return running_.load(); }

    /**
     * Get metrics URL
     */
    std::string get_metrics_url() const;

private:
    uint16_t port_;
    MetricsAggregator* aggregator_;
    std::atomic<bool> running_;
    std::thread server_thread_;
    int server_socket_;

    // HTTP server loop
    void server_loop();

    // Handle HTTP request
    void handle_request(int client_socket);

    // Send HTTP response
    void send_response(int client_socket, const std::string& content);
};

} // namespace trading_system
