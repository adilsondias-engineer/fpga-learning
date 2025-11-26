#include "metrics_aggregator.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <chrono>
#include <thread>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cstring>

namespace trading_system {

MetricsAggregator::MetricsAggregator()
    : running_(false)
    , p14_metrics_url_("http://localhost:9091/metrics")
    , p15_metrics_url_("http://localhost:9092/metrics")
    , p16_metrics_url_("http://localhost:9093/metrics")
{
}

MetricsAggregator::~MetricsAggregator() {
    stop();
}

void MetricsAggregator::start(int interval_ms) {
    if (running_.load()) {
        return;
    }

    running_.store(true);
    collection_thread_ = std::thread(&MetricsAggregator::collection_loop, this, interval_ms);
}

void MetricsAggregator::stop() {
    if (!running_.load()) {
        return;
    }

    running_.store(false);

    if (collection_thread_.joinable()) {
        collection_thread_.join();
    }
}

void MetricsAggregator::collect_metrics() {
    std::lock_guard<std::mutex> lock(metrics_mutex_);

    // Fetch metrics from each component
    // Note: This is a simplified implementation
    // In production, would use proper HTTP client library (libcurl, boost::beast, etc.)

    // For now, just update counters as placeholders
    // Real implementation would parse Prometheus metrics from each component

    current_metrics_.total_bbo_updates++;
    current_metrics_.uptime_seconds++;
}

SystemMetrics MetricsAggregator::get_metrics() const {
    std::lock_guard<std::mutex> lock(metrics_mutex_);
    return current_metrics_;
}

std::string MetricsAggregator::export_prometheus() const {
    std::lock_guard<std::mutex> lock(metrics_mutex_);
    std::ostringstream oss;

    // System-wide counters
    oss << "# HELP trading_system_bbo_updates_total Total BBO updates received\n";
    oss << "# TYPE trading_system_bbo_updates_total counter\n";
    oss << "trading_system_bbo_updates_total " << current_metrics_.total_bbo_updates << "\n\n";

    oss << "# HELP trading_system_orders_submitted_total Total orders submitted\n";
    oss << "# TYPE trading_system_orders_submitted_total counter\n";
    oss << "trading_system_orders_submitted_total " << current_metrics_.total_orders_submitted << "\n\n";

    oss << "# HELP trading_system_fills_received_total Total fills received\n";
    oss << "# TYPE trading_system_fills_received_total counter\n";
    oss << "trading_system_fills_received_total " << current_metrics_.total_fills_received << "\n\n";

    // Position tracking
    oss << "# HELP trading_system_position Current position by symbol\n";
    oss << "# TYPE trading_system_position gauge\n";
    for (const auto& [symbol, position] : current_metrics_.positions_by_symbol) {
        oss << "trading_system_position{symbol=\"" << symbol << "\"} " << position << "\n";
    }
    oss << "\n";

    oss << "# HELP trading_system_total_position Total position across all symbols\n";
    oss << "# TYPE trading_system_total_position gauge\n";
    oss << "trading_system_total_position " << current_metrics_.total_position << "\n\n";

    // PnL tracking
    oss << "# HELP trading_system_realized_pnl_usd Realized PnL in USD\n";
    oss << "# TYPE trading_system_realized_pnl_usd gauge\n";
    oss << "trading_system_realized_pnl_usd " << std::fixed << std::setprecision(2)
        << current_metrics_.total_realized_pnl << "\n\n";

    oss << "# HELP trading_system_unrealized_pnl_usd Unrealized PnL in USD\n";
    oss << "# TYPE trading_system_unrealized_pnl_usd gauge\n";
    oss << "trading_system_unrealized_pnl_usd " << std::fixed << std::setprecision(2)
        << current_metrics_.total_unrealized_pnl << "\n\n";

    // End-to-end latency
    oss << "# HELP trading_system_e2e_latency_ns End-to-end latency (nanoseconds)\n";
    oss << "# TYPE trading_system_e2e_latency_ns gauge\n";
    oss << "trading_system_e2e_latency_ns{quantile=\"min\"} " << current_metrics_.e2e_latency_min_ns << "\n";
    oss << "trading_system_e2e_latency_ns{quantile=\"p50\"} " << current_metrics_.e2e_latency_p50_ns << "\n";
    oss << "trading_system_e2e_latency_ns{quantile=\"p99\"} " << current_metrics_.e2e_latency_p99_ns << "\n";
    oss << "trading_system_e2e_latency_ns{quantile=\"max\"} " << current_metrics_.e2e_latency_max_ns << "\n";
    oss << "trading_system_e2e_latency_ns{quantile=\"mean\"} " << static_cast<uint64_t>(current_metrics_.e2e_latency_mean_ns) << "\n\n";

    // Component latencies
    oss << "# HELP trading_system_component_latency_p99_ns Component P99 latency (nanoseconds)\n";
    oss << "# TYPE trading_system_component_latency_p99_ns gauge\n";
    oss << "trading_system_component_latency_p99_ns{component=\"order_gateway\"} " << current_metrics_.p14_latency_p99_ns << "\n";
    oss << "trading_system_component_latency_p99_ns{component=\"market_maker\"} " << current_metrics_.p15_latency_p99_ns << "\n";
    oss << "trading_system_component_latency_p99_ns{component=\"order_execution\"} " << current_metrics_.p16_latency_p99_ns << "\n\n";

    // Ring buffer health
    oss << "# HELP trading_system_ring_buffer_depth Current ring buffer depth\n";
    oss << "# TYPE trading_system_ring_buffer_depth gauge\n";
    oss << "trading_system_ring_buffer_depth{buffer=\"order_ring\"} " << current_metrics_.order_ring_depth << "\n";
    oss << "trading_system_ring_buffer_depth{buffer=\"fill_ring\"} " << current_metrics_.fill_ring_depth << "\n\n";

    oss << "# HELP trading_system_ring_buffer_max_depth Maximum ring buffer depth observed\n";
    oss << "# TYPE trading_system_ring_buffer_max_depth gauge\n";
    oss << "trading_system_ring_buffer_max_depth{buffer=\"order_ring\"} " << current_metrics_.order_ring_max_depth << "\n";
    oss << "trading_system_ring_buffer_max_depth{buffer=\"fill_ring\"} " << current_metrics_.fill_ring_max_depth << "\n\n";

    oss << "# HELP trading_system_ring_buffer_wraps_total Ring buffer wrap count\n";
    oss << "# TYPE trading_system_ring_buffer_wraps_total counter\n";
    oss << "trading_system_ring_buffer_wraps_total{buffer=\"order_ring\"} " << current_metrics_.order_ring_wraps << "\n";
    oss << "trading_system_ring_buffer_wraps_total{buffer=\"fill_ring\"} " << current_metrics_.fill_ring_wraps << "\n\n";

    // System uptime
    oss << "# HELP trading_system_uptime_seconds System uptime in seconds\n";
    oss << "# TYPE trading_system_uptime_seconds counter\n";
    oss << "trading_system_uptime_seconds " << current_metrics_.uptime_seconds << "\n\n";

    return oss.str();
}

void MetricsAggregator::collection_loop(int interval_ms) {
    while (running_.load()) {
        collect_metrics();
        std::this_thread::sleep_for(std::chrono::milliseconds(interval_ms));
    }
}

std::string MetricsAggregator::fetch_metrics(const std::string& url) {
    // TODO: Implement proper HTTP client
    // For now, return empty string
    // In production, would use libcurl or boost::beast
    return "";
}

void MetricsAggregator::parse_prometheus_metrics(const std::string& component, const std::string& metrics_text) {
    // TODO: Implement Prometheus metrics parsing
    // Parse lines like:
    // metric_name{label="value"} 123.45
    // Would extract values and update current_metrics_
}

double MetricsAggregator::extract_metric_value(const std::string& metrics_text, const std::string& metric_name) {
    // Simple metric extraction (production would use regex or proper parser)
    size_t pos = metrics_text.find(metric_name);
    if (pos == std::string::npos) {
        return 0.0;
    }

    // Find the value after the metric name
    size_t value_start = metrics_text.find_first_of("0123456789.-", pos);
    if (value_start == std::string::npos) {
        return 0.0;
    }

    size_t value_end = metrics_text.find_first_not_of("0123456789.-", value_start);
    std::string value_str = metrics_text.substr(value_start, value_end - value_start);

    try {
        return std::stod(value_str);
    } catch (...) {
        return 0.0;
    }
}

} // namespace trading_system
