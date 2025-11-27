#pragma once

#include "latency_tracker.h"
#include <string>
#include <memory>
#include <thread>
#include <atomic>
#include <vector>

namespace timestamp {

/**
 * Prometheus metrics HTTP exporter
 * Exposes /metrics endpoint on specified port
 */
class PrometheusExporter {
public:
    /**
     * Create Prometheus exporter
     * @param port HTTP port for /metrics endpoint (default: 9090)
     */
    explicit PrometheusExporter(uint16_t port = 9090);

    ~PrometheusExporter();

    // No copy
    PrometheusExporter(const PrometheusExporter&) = delete;
    PrometheusExporter& operator=(const PrometheusExporter&) = delete;

    /**
     * Register latency tracker for export
     * @param tracker Latency tracker to export metrics from
     */
    void register_tracker(const LatencyTracker* tracker);

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
    bool is_running() const { return running_; }

    /**
     * Get metrics endpoint URL
     */
    std::string get_metrics_url() const;

private:
    uint16_t port_;
    std::atomic<bool> running_;
    std::thread server_thread_;
    int server_socket_;

    // Registered trackers
    std::vector<const LatencyTracker*> trackers_;

    // HTTP server loop
    void server_loop();

    // Handle HTTP request
    void handle_request(int client_socket);

    // Generate Prometheus metrics response
    std::string generate_metrics() const;

    // Send HTTP response
    void send_response(int client_socket, const std::string& content);
};

} // namespace timestamp
