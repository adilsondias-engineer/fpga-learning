#pragma once

#include <atomic>
#include <array>
#include <string>
#include <vector>
#include <mutex>
#include <cstdint>

namespace timestamp {

/**
 * Latency statistics
 */
struct LatencyStats {
    uint64_t count;
    uint64_t sum_ns;
    uint64_t min_ns;
    uint64_t max_ns;
    double mean_ns;
    double stddev_ns;

    // Percentiles
    uint64_t p50_ns;
    uint64_t p90_ns;
    uint64_t p95_ns;
    uint64_t p99_ns;
    uint64_t p99_9_ns;
};

/**
 * Latency tracker with histogram and percentile calculation
 * Thread-safe for concurrent latency recording
 */
class LatencyTracker {
public:
    /**
     * Create latency tracker
     * @param component_name Name of component being tracked
     * @param max_samples Maximum samples to store for percentile calculation
     */
    explicit LatencyTracker(const std::string& component_name, size_t max_samples = 100000);

    /**
     * Record latency measurement
     * @param latency_ns Latency in nanoseconds
     */
    void record_latency(uint64_t latency_ns);

    /**
     * Get current statistics
     * @return Latency statistics including percentiles
     */
    LatencyStats get_stats() const;

    /**
     * Export metrics in Prometheus format
     * @return Prometheus-formatted metrics string
     */
    std::string export_prometheus() const;

    /**
     * Reset all measurements
     */
    void reset();

    /**
     * Get component name
     */
    const std::string& get_component_name() const { return component_name_; }

private:
    std::string component_name_;

    // Histogram buckets (atomic for lock-free updates)
    static constexpr size_t NUM_BUCKETS = 25;
    std::array<std::atomic<uint64_t>, NUM_BUCKETS> histogram_;

    // Bucket boundaries (nanoseconds)
    static constexpr std::array<uint64_t, NUM_BUCKETS> bucket_boundaries_ = {
        50,       // 0-50ns
        100,      // 50-100ns
        200,      // 100-200ns
        500,      // 200-500ns
        1000,     // 500ns-1μs
        2000,     // 1-2μs
        5000,     // 2-5μs
        10000,    // 5-10μs
        20000,    // 10-20μs
        50000,    // 20-50μs
        100000,   // 50-100μs
        200000,   // 100-200μs
        500000,   // 200-500μs
        1000000,  // 500μs-1ms
        2000000,  // 1-2ms
        5000000,  // 2-5ms
        10000000, // 5-10ms
        20000000, // 10-20ms
        50000000, // 20-50ms
        100000000, // 50-100ms
        200000000, // 100-200ms
        500000000, // 200-500ms
        1000000000, // 500ms-1s
        5000000000, // 1-5s
        UINT64_MAX  // 5s+
    };

    // Raw samples for percentile calculation (ring buffer)
    mutable std::mutex samples_mutex_;
    std::vector<uint64_t> samples_;
    size_t max_samples_;
    size_t sample_index_;

    // Statistics (updated on each record)
    std::atomic<uint64_t> count_;
    std::atomic<uint64_t> sum_ns_;
    std::atomic<uint64_t> min_ns_;
    std::atomic<uint64_t> max_ns_;

    // Find bucket index for latency value
    size_t find_bucket(uint64_t latency_ns) const;

    // Calculate percentile from sorted samples
    uint64_t calculate_percentile(const std::vector<uint64_t>& sorted_samples, double percentile) const;
};

} // namespace timestamp
