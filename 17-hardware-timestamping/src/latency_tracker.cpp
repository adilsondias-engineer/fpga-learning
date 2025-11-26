#include "latency_tracker.h"
#include <algorithm>
#include <sstream>
#include <iomanip>
#include <cmath>

namespace timestamp {

LatencyTracker::LatencyTracker(const std::string& component_name, size_t max_samples)
    : component_name_(component_name)
    , max_samples_(max_samples)
    , sample_index_(0)
    , count_(0)
    , sum_ns_(0)
    , min_ns_(UINT64_MAX)
    , max_ns_(0)
{
    // Initialize histogram buckets to zero
    for (auto& bucket : histogram_) {
        bucket.store(0, std::memory_order_relaxed);
    }

    // Pre-allocate samples vector
    samples_.reserve(max_samples_);
}

void LatencyTracker::record_latency(uint64_t latency_ns) {
    // Update histogram (lock-free)
    size_t bucket_idx = find_bucket(latency_ns);
    histogram_[bucket_idx].fetch_add(1, std::memory_order_relaxed);

    // Update count and sum (lock-free)
    count_.fetch_add(1, std::memory_order_relaxed);
    sum_ns_.fetch_add(latency_ns, std::memory_order_relaxed);

    // Update min/max (lock-free CAS loop)
    uint64_t current_min = min_ns_.load(std::memory_order_relaxed);
    while (latency_ns < current_min &&
           !min_ns_.compare_exchange_weak(current_min, latency_ns, std::memory_order_relaxed)) {
        // Retry if CAS failed
    }

    uint64_t current_max = max_ns_.load(std::memory_order_relaxed);
    while (latency_ns > current_max &&
           !max_ns_.compare_exchange_weak(current_max, latency_ns, std::memory_order_relaxed)) {
        // Retry if CAS failed
    }

    // Store sample for percentile calculation (requires lock)
    {
        std::lock_guard<std::mutex> lock(samples_mutex_);
        if (samples_.size() < max_samples_) {
            samples_.push_back(latency_ns);
        } else {
            // Ring buffer - overwrite oldest sample
            samples_[sample_index_] = latency_ns;
            sample_index_ = (sample_index_ + 1) % max_samples_;
        }
    }
}

LatencyStats LatencyTracker::get_stats() const {
    LatencyStats stats = {};

    stats.count = count_.load(std::memory_order_relaxed);
    if (stats.count == 0) {
        return stats;  // No measurements yet
    }

    stats.sum_ns = sum_ns_.load(std::memory_order_relaxed);
    stats.min_ns = min_ns_.load(std::memory_order_relaxed);
    stats.max_ns = max_ns_.load(std::memory_order_relaxed);
    stats.mean_ns = static_cast<double>(stats.sum_ns) / stats.count;

    // Calculate standard deviation and percentiles (requires samples copy)
    std::vector<uint64_t> sorted_samples;
    {
        std::lock_guard<std::mutex> lock(samples_mutex_);
        sorted_samples = samples_;
    }

    if (!sorted_samples.empty()) {
        // Sort for percentile calculation
        std::sort(sorted_samples.begin(), sorted_samples.end());

        // Calculate standard deviation
        double variance = 0.0;
        for (uint64_t sample : sorted_samples) {
            double diff = sample - stats.mean_ns;
            variance += diff * diff;
        }
        stats.stddev_ns = std::sqrt(variance / sorted_samples.size());

        // Calculate percentiles
        stats.p50_ns = calculate_percentile(sorted_samples, 0.50);
        stats.p90_ns = calculate_percentile(sorted_samples, 0.90);
        stats.p95_ns = calculate_percentile(sorted_samples, 0.95);
        stats.p99_ns = calculate_percentile(sorted_samples, 0.99);
        stats.p99_9_ns = calculate_percentile(sorted_samples, 0.999);
    }

    return stats;
}

std::string LatencyTracker::export_prometheus() const {
    std::ostringstream oss;

    // Metric prefix
    std::string metric_name = "latency_" + component_name_;

    // Replace spaces/dashes with underscores
    for (char& c : metric_name) {
        if (c == ' ' || c == '-') {
            c = '_';
        }
    }

    // Histogram buckets
    oss << "# HELP " << metric_name << "_ns Latency histogram (nanoseconds)\n";
    oss << "# TYPE " << metric_name << "_ns histogram\n";

    uint64_t cumulative = 0;
    for (size_t i = 0; i < NUM_BUCKETS; ++i) {
        cumulative += histogram_[i].load(std::memory_order_relaxed);
        oss << metric_name << "_ns_bucket{le=\"" << bucket_boundaries_[i] << "\"} "
            << cumulative << "\n";
    }

    // Total count and sum
    uint64_t count = count_.load(std::memory_order_relaxed);
    uint64_t sum = sum_ns_.load(std::memory_order_relaxed);

    oss << metric_name << "_ns_bucket{le=\"+Inf\"} " << count << "\n";
    oss << metric_name << "_ns_sum " << sum << "\n";
    oss << metric_name << "_ns_count " << count << "\n";

    // Percentiles as gauges
    LatencyStats stats = get_stats();

    oss << "\n# HELP " << metric_name << "_percentile_ns Latency percentiles (nanoseconds)\n";
    oss << "# TYPE " << metric_name << "_percentile_ns gauge\n";
    oss << metric_name << "_percentile_ns{percentile=\"p50\"} " << stats.p50_ns << "\n";
    oss << metric_name << "_percentile_ns{percentile=\"p90\"} " << stats.p90_ns << "\n";
    oss << metric_name << "_percentile_ns{percentile=\"p95\"} " << stats.p95_ns << "\n";
    oss << metric_name << "_percentile_ns{percentile=\"p99\"} " << stats.p99_ns << "\n";
    oss << metric_name << "_percentile_ns{percentile=\"p99_9\"} " << stats.p99_9_ns << "\n";

    // Summary statistics
    oss << "\n# HELP " << metric_name << "_summary_ns Latency summary statistics (nanoseconds)\n";
    oss << "# TYPE " << metric_name << "_summary_ns gauge\n";
    oss << metric_name << "_summary_ns{stat=\"min\"} " << stats.min_ns << "\n";
    oss << metric_name << "_summary_ns{stat=\"max\"} " << stats.max_ns << "\n";
    oss << metric_name << "_summary_ns{stat=\"mean\"} " << std::fixed << std::setprecision(2) << stats.mean_ns << "\n";
    oss << metric_name << "_summary_ns{stat=\"stddev\"} " << stats.stddev_ns << "\n";

    return oss.str();
}

void LatencyTracker::reset() {
    // Reset histogram
    for (auto& bucket : histogram_) {
        bucket.store(0, std::memory_order_relaxed);
    }

    // Reset statistics
    count_.store(0, std::memory_order_relaxed);
    sum_ns_.store(0, std::memory_order_relaxed);
    min_ns_.store(UINT64_MAX, std::memory_order_relaxed);
    max_ns_.store(0, std::memory_order_relaxed);

    // Reset samples
    {
        std::lock_guard<std::mutex> lock(samples_mutex_);
        samples_.clear();
        sample_index_ = 0;
    }
}

size_t LatencyTracker::find_bucket(uint64_t latency_ns) const {
    // Binary search for bucket
    for (size_t i = 0; i < NUM_BUCKETS; ++i) {
        if (latency_ns <= bucket_boundaries_[i]) {
            return i;
        }
    }
    return NUM_BUCKETS - 1;  // Overflow bucket
}

uint64_t LatencyTracker::calculate_percentile(const std::vector<uint64_t>& sorted_samples, double percentile) const {
    if (sorted_samples.empty()) {
        return 0;
    }

    double index = percentile * (sorted_samples.size() - 1);
    size_t lower = static_cast<size_t>(std::floor(index));
    size_t upper = static_cast<size_t>(std::ceil(index));

    if (lower == upper) {
        return sorted_samples[lower];
    }

    // Linear interpolation
    double weight = index - lower;
    return static_cast<uint64_t>(
        sorted_samples[lower] * (1.0 - weight) + sorted_samples[upper] * weight
    );
}

} // namespace timestamp
