#ifndef PERF_MONITOR_H
#define PERF_MONITOR_H

#include <chrono>
#include <fstream>
#include <vector>
#include <cstdint>
#include <algorithm>
#include <numeric>
#include <iostream>
#include <iomanip>
#include <math.h>
#include <cmath>

namespace gateway {

class PerfMonitor {
public:
    struct Metrics {
        double avg_us;
        double min_us;
        double max_us;
        double p50_us;  // Median
        double p95_us;
        double p99_us;
        double stddev_us;
        size_t count;
    };

    PerfMonitor() = default;

    void recordLatency(uint64_t latency_ns) {
        latencies_.push_back(latency_ns);
    }

    Metrics getMetrics() {
        if (latencies_.empty()) {
            return {0, 0, 0, 0, 0, 0, 0, 0};
        }

        std::sort(latencies_.begin(), latencies_.end());

        Metrics m;
        m.count = latencies_.size();

        // Convert to microseconds
        auto toUs = [](uint64_t ns) { return ns / 1000.0; };

        m.min_us = toUs(latencies_.front());
        m.max_us = toUs(latencies_.back());

        uint64_t sum = std::accumulate(latencies_.begin(), latencies_.end(), 0ULL);
        m.avg_us = toUs(sum / latencies_.size());

        // Percentiles
        m.p50_us = toUs(latencies_[latencies_.size() * 50 / 100]);
        m.p95_us = toUs(latencies_[latencies_.size() * 95 / 100]);
        m.p99_us = toUs(latencies_[latencies_.size() * 99 / 100]);

        // Standard deviation
        double variance = 0.0;
        double avg_ns = sum / static_cast<double>(latencies_.size());
        for (auto lat : latencies_) {
            double diff = lat - avg_ns;
            variance += diff * diff;
        }
        variance /= latencies_.size();
        m.stddev_us = std::sqrt(variance) / 1000.0;

        return m;
    }

    void saveToFile(const std::string& filename) {
        std::ofstream file(filename);
        file << "latency_ns\n";
        for (auto latency : latencies_) {
            file << latency << "\n";
        }
        std::cout << "[PERF] Saved " << latencies_.size() << " samples to " << filename << "\n";
    }

    void printSummary(const std::string& label) {
        auto m = getMetrics();
        std::cout << "\n=== " << label << " Performance Metrics ===\n";
        std::cout << "Samples:  " << m.count << "\n";
        std::cout << "Avg:      " << std::fixed << std::setprecision(2) << m.avg_us << " μs\n";
        std::cout << "Min:      " << m.min_us << " μs\n";
        std::cout << "Max:      " << m.max_us << " μs\n";
        std::cout << "P50:      " << m.p50_us << " μs\n";
        std::cout << "P95:      " << m.p95_us << " μs\n";
        std::cout << "P99:      " << m.p99_us << " μs\n";
        std::cout << "StdDev:   " << m.stddev_us << " μs\n";
    }

    void reset() {
        latencies_.clear();
    }

    size_t count() const {
        return latencies_.size();
    }

private:
    std::vector<uint64_t> latencies_;
};

// RAII latency measurement
class LatencyMeasurement {
public:
    LatencyMeasurement(PerfMonitor& monitor)
        : monitor_(monitor)
        , start_(std::chrono::high_resolution_clock::now()) {}

    ~LatencyMeasurement() {
        auto end = std::chrono::high_resolution_clock::now();
        auto latency = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start_).count();
        monitor_.recordLatency(latency);
    }

private:
    PerfMonitor& monitor_;
    std::chrono::high_resolution_clock::time_point start_;
};

} // namespace gateway

#endif // PERF_MONITOR_H
