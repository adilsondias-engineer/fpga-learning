#include "timestamp_socket.h"
#include "latency_tracker.h"
#include "prometheus_exporter.h"
#include <iostream>
#include <csignal>
#include <thread>
#include <atomic>
#include <fstream>
#include <nlohmann/json.hpp>

using json = nlohmann::json;
using namespace timestamp;

// Global flag for graceful shutdown
std::atomic<bool> g_running{true};

void signal_handler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        std::cout << "\nReceived shutdown signal, exiting gracefully..." << std::endl;
        g_running.store(false);
    }
}

struct Config {
    uint16_t udp_port = 12345;
    uint16_t metrics_port = 9090;
    std::string interface = "";
    uint64_t warning_threshold_ns = 100000;    // 100μs
    uint64_t critical_threshold_ns = 1000000;  // 1ms
    size_t max_samples = 100000;
    bool enable_console_output = true;
    uint64_t stats_interval_ms = 5000;
};

Config load_config(const std::string& config_file) {
    Config config;

    try {
        std::ifstream file(config_file);
        if (!file.is_open()) {
            std::cerr << "Warning: Could not open config file '" << config_file
                      << "', using defaults" << std::endl;
            return config;
        }

        json j;
        file >> j;

        if (j.contains("udp_port")) config.udp_port = j["udp_port"];
        if (j.contains("metrics_port")) config.metrics_port = j["metrics_port"];
        if (j.contains("interface")) config.interface = j["interface"];
        if (j.contains("warning_threshold_ns")) config.warning_threshold_ns = j["warning_threshold_ns"];
        if (j.contains("critical_threshold_ns")) config.critical_threshold_ns = j["critical_threshold_ns"];
        if (j.contains("max_samples")) config.max_samples = j["max_samples"];
        if (j.contains("enable_console_output")) config.enable_console_output = j["enable_console_output"];
        if (j.contains("stats_interval_ms")) config.stats_interval_ms = j["stats_interval_ms"];

        std::cout << "Configuration loaded from '" << config_file << "'" << std::endl;
    } catch (const std::exception& e) {
        std::cerr << "Error loading config: " << e.what() << ", using defaults" << std::endl;
    }

    return config;
}

void print_stats(const LatencyTracker& tracker) {
    LatencyStats stats = tracker.get_stats();

    if (stats.count == 0) {
        std::cout << "\n[" << tracker.get_component_name() << "] No measurements yet" << std::endl;
        return;
    }

    std::cout << "\n========================================" << std::endl;
    std::cout << "[" << tracker.get_component_name() << "] Latency Statistics" << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "Total measurements: " << stats.count << std::endl;
    std::cout << "----------------------------------------" << std::endl;
    std::cout << "Min:    " << stats.min_ns << " ns" << std::endl;
    std::cout << "Max:    " << stats.max_ns << " ns" << std::endl;
    std::cout << "Mean:   " << static_cast<uint64_t>(stats.mean_ns) << " ns" << std::endl;
    std::cout << "StdDev: " << static_cast<uint64_t>(stats.stddev_ns) << " ns" << std::endl;
    std::cout << "----------------------------------------" << std::endl;
    std::cout << "Percentiles:" << std::endl;
    std::cout << "  P50 (median):  " << stats.p50_ns << " ns" << std::endl;
    std::cout << "  P90:           " << stats.p90_ns << " ns" << std::endl;
    std::cout << "  P95:           " << stats.p95_ns << " ns" << std::endl;
    std::cout << "  P99:           " << stats.p99_ns << " ns" << std::endl;
    std::cout << "  P99.9:         " << stats.p99_9_ns << " ns" << std::endl;
    std::cout << "========================================\n" << std::endl;
}

void print_packet_info(const TimestampedPacket& packet, const Config& config) {
    if (!config.enable_console_output) {
        return;
    }

    // Print packet metadata
    std::cout << "[PACKET] "
              << "Size: " << packet.data_len << " bytes, "
              << "Kernel→App latency: " << packet.kernel_to_app_ns << " ns";

    // Warn on high latency
    if (packet.kernel_to_app_ns > config.critical_threshold_ns) {
        std::cout << " [CRITICAL]";
    } else if (packet.kernel_to_app_ns > config.warning_threshold_ns) {
        std::cout << " [WARNING]";
    }

    std::cout << std::endl;
}

int main(int argc, char* argv[]) {
    // Load configuration
    std::string config_file = "config.json";
    if (argc > 1) {
        config_file = argv[1];
    }

    Config config = load_config(config_file);

    // Setup signal handlers
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    std::cout << "========================================" << std::endl;
    std::cout << "Hardware Timestamping Demo (Project 17)" << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "UDP Port:           " << config.udp_port << std::endl;
    std::cout << "Metrics Port:       " << config.metrics_port << std::endl;
    std::cout << "Interface:          " << (config.interface.empty() ? "any" : config.interface) << std::endl;
    std::cout << "Warning threshold:  " << config.warning_threshold_ns << " ns" << std::endl;
    std::cout << "Critical threshold: " << config.critical_threshold_ns << " ns" << std::endl;
    std::cout << "Max samples:        " << config.max_samples << std::endl;
    std::cout << "========================================\n" << std::endl;

    try {
        // Create timestamping socket
        TimestampSocket socket(
            config.udp_port,
            config.interface.empty() ? nullptr : config.interface.c_str()
        );

        if (!socket.is_timestamping_enabled()) {
            std::cerr << "Warning: Hardware timestamping not available, using fallback" << std::endl;
        } else {
            std::cout << "Kernel-level timestamping enabled via SO_TIMESTAMPING" << std::endl;
        }

        // Create latency tracker
        LatencyTracker tracker("kernel_to_app", config.max_samples);

        // Create Prometheus exporter
        PrometheusExporter exporter(config.metrics_port);
        exporter.register_tracker(&tracker);
        exporter.start();

        std::cout << "Prometheus metrics available at: " << exporter.get_metrics_url() << std::endl;
        std::cout << "\nListening for UDP packets on port " << config.udp_port << "..." << std::endl;
        std::cout << "Press Ctrl+C to exit\n" << std::endl;

        // Statistics printing thread
        std::thread stats_thread([&]() {
            while (g_running.load()) {
                std::this_thread::sleep_for(std::chrono::milliseconds(config.stats_interval_ms));
                if (g_running.load()) {
                    print_stats(tracker);
                }
            }
        });

        // Main packet reception loop
        while (g_running.load()) {
            try {
                // Receive packet with timestamps
                TimestampedPacket packet = socket.receive_with_timestamp();

                // Record latency
                tracker.record_latency(packet.kernel_to_app_ns);

                // Print packet info
                print_packet_info(packet, config);

            } catch (const std::exception& e) {
                if (g_running.load()) {
                    std::cerr << "Error receiving packet: " << e.what() << std::endl;
                }
                break;
            }
        }

        // Wait for stats thread
        stats_thread.join();

        // Print final statistics
        std::cout << "\nFinal Statistics:" << std::endl;
        print_stats(tracker);

        // Stop Prometheus exporter
        exporter.stop();

        std::cout << "Shutdown complete" << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
