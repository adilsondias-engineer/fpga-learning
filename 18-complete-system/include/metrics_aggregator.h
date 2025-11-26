#pragma once

#include <string>
#include <map>
#include <vector>
#include <atomic>
#include <mutex>
#include <thread>
#include <cstdint>

namespace trading_system {

/**
 * System-wide aggregated metrics
 */
struct SystemMetrics {
    // Throughput
    uint64_t total_bbo_updates;
    uint64_t total_orders_submitted;
    uint64_t total_fills_received;

    // Position tracking (aggregated across all symbols)
    int32_t total_position;
    double total_realized_pnl;
    double total_unrealized_pnl;

    // Per-symbol breakdown
    std::map<std::string, int32_t> positions_by_symbol;
    std::map<std::string, double> pnl_by_symbol;

    // Performance metrics
    uint64_t e2e_latency_min_ns;
    uint64_t e2e_latency_max_ns;
    uint64_t e2e_latency_p50_ns;
    uint64_t e2e_latency_p99_ns;
    double e2e_latency_mean_ns;

    // Component latencies
    uint64_t p14_latency_p99_ns;  // Order Gateway
    uint64_t p15_latency_p99_ns;  // Market Maker
    uint64_t p16_latency_p99_ns;  // Order Execution

    // Shared memory health
    uint64_t order_ring_depth;
    uint64_t order_ring_max_depth;
    uint64_t order_ring_wraps;
    uint64_t fill_ring_depth;
    uint64_t fill_ring_max_depth;
    uint64_t fill_ring_wraps;

    // System uptime
    uint64_t uptime_seconds;

    SystemMetrics()
        : total_bbo_updates(0)
        , total_orders_submitted(0)
        , total_fills_received(0)
        , total_position(0)
        , total_realized_pnl(0.0)
        , total_unrealized_pnl(0.0)
        , e2e_latency_min_ns(UINT64_MAX)
        , e2e_latency_max_ns(0)
        , e2e_latency_p50_ns(0)
        , e2e_latency_p99_ns(0)
        , e2e_latency_mean_ns(0.0)
        , p14_latency_p99_ns(0)
        , p15_latency_p99_ns(0)
        , p16_latency_p99_ns(0)
        , order_ring_depth(0)
        , order_ring_max_depth(0)
        , order_ring_wraps(0)
        , fill_ring_depth(0)
        , fill_ring_max_depth(0)
        , fill_ring_wraps(0)
        , uptime_seconds(0)
    {}
};

/**
 * Metrics aggregator - collects and aggregates metrics from all components
 */
class MetricsAggregator {
public:
    MetricsAggregator();
    ~MetricsAggregator();

    /**
     * Collect metrics from all components
     * Fetches Prometheus metrics from P14, P15, P16 and aggregates
     */
    void collect_metrics();

    /**
     * Get current aggregated metrics
     */
    SystemMetrics get_metrics() const;

    /**
     * Export metrics in Prometheus format
     */
    std::string export_prometheus() const;

    /**
     * Start metrics collection thread
     * @param interval_ms Collection interval in milliseconds
     */
    void start(int interval_ms = 1000);

    /**
     * Stop metrics collection thread
     */
    void stop();

private:
    mutable std::mutex metrics_mutex_;
    SystemMetrics current_metrics_;

    std::atomic<bool> running_;
    std::thread collection_thread_;

    // Prometheus endpoint URLs
    std::string p14_metrics_url_;
    std::string p15_metrics_url_;
    std::string p16_metrics_url_;

    // Collection thread
    void collection_loop(int interval_ms);

    // HTTP fetch (simple implementation)
    std::string fetch_metrics(const std::string& url);

    // Parse Prometheus metrics
    void parse_prometheus_metrics(const std::string& component, const std::string& metrics_text);

    // Extract metric value from Prometheus format
    double extract_metric_value(const std::string& metrics_text, const std::string& metric_name);
};

} // namespace trading_system
