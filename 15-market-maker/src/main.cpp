#include <iostream>
#include <csignal>
#include <fstream>
#include <chrono>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <nlohmann/json.hpp>
#include "market_maker_fsm.h"
#include "tcp_client.h"
#include "disruptor_client.h"
#include "bbo_parser.h"
#include "common/perf_monitor.h"

#ifdef __linux__
#include <sched.h>
#include <pthread.h>
#include <cstring>

void enableRealTimeScheduling() {
    struct sched_param param;
    param.sched_priority = 50;

    if (sched_setscheduler(0, SCHED_FIFO, &param) == -1) {
        spdlog::warn("Failed to set RT scheduling: {}", strerror(errno));
    } else {
        spdlog::info("RT scheduling enabled (SCHED_FIFO, priority 50)");
    }
}

void setCpuAffinity(const std::vector<int>& cores) {
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);

    for (int core : cores) {
        CPU_SET(core, &cpuset);
    }

    if (pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset) == 0) {
        std::string cores_str;
        for (size_t i = 0; i < cores.size(); ++i) {
            if (i > 0) cores_str += ",";
            cores_str += std::to_string(cores[i]);
        }
        spdlog::info("CPU affinity set to cores: {}", cores_str);
    }
}
#endif

volatile bool g_running = true;

// Common listener interface (polymorphic)
struct ListenerBase {
    virtual ~ListenerBase() = default;
    virtual void start() = 0;
    virtual void stop() = 0;
    virtual gateway::BBOData read_bbo() = 0;
    virtual bool isRunning() const = 0;
    virtual void setPerfMonitor(gateway::PerfMonitor* monitor) = 0;
};

// TCP client wrapper
struct TCPClientWrapper : public ListenerBase {
    std::unique_ptr<gateway::TCPClient> impl;

    TCPClientWrapper(const std::string& host, int port)
        : impl(std::make_unique<gateway::TCPClient>(host, port)) {}

    void start() override { impl->connect(); }
    void stop() override { impl->disconnect(); }
    gateway::BBOData read_bbo() override { return impl->read_bbo(); }
    bool isRunning() const override { return impl->isConnected(); }
    void setPerfMonitor(gateway::PerfMonitor* monitor) override { impl->setPerfMonitor(monitor); }
};

// Disruptor client wrapper
struct DisruptorClientWrapper : public ListenerBase {
    std::unique_ptr<gateway::DisruptorClient> impl;
    gateway::PerfMonitor* monitor_;

    DisruptorClientWrapper(const std::string& shm_name = "gateway")
        : impl(std::make_unique<gateway::DisruptorClient>(shm_name)), monitor_(nullptr) {}

    void start() override { impl->connect(); }
    void stop() override { impl->disconnect(); }
    gateway::BBOData read_bbo() override {
        // Read BBO from Disruptor
        gateway::BBOData bbo = impl->read_bbo(100000);  // 100ms timeout

        // Debug: check BBO state for first few samples
        static int debug_count = 0;
        if (++debug_count <= 3) {
            spdlog::info("BBO #{}: valid={}, timestamp_ns={}, monitor={}",
                         debug_count, bbo.valid, bbo.timestamp_ns,
                         monitor_ ? "set" : "null");
        }

        // Measure latency from BBO timestamp to now (end-to-end latency)
        if (bbo.valid && bbo.timestamp_ns > 0) {
            auto now = std::chrono::high_resolution_clock::now();
            auto now_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
                now.time_since_epoch()).count();
            uint64_t latency_ns = now_ns - bbo.timestamp_ns;

            if (monitor_) {
                monitor_->recordLatency(latency_ns);
                // Debug: log first 5 samples
                static int sample_count = 0;
                if (++sample_count <= 5) {
                    spdlog::info("Recorded latency sample #{}: {} ns ({} μs)",
                                 sample_count, latency_ns, latency_ns / 1000.0);
                }
            } else {
                spdlog::warn("Monitor is null!");
            }
        }

        return bbo;
    }
    bool isRunning() const override { return impl->isConnected(); }
    void setPerfMonitor(gateway::PerfMonitor* monitor) override { monitor_ = monitor; }
};

std::unique_ptr<ListenerBase> g_listener;
gateway::PerfMonitor g_parse_latency;  // Global performance monitor

void signalHandler(int signal) {
    spdlog::info("Received signal {}, shutting down...", signal);
    g_running = false;
    // Don't stop listener here - let main loop clean up properly
}

mm::BBO convertBboData(const gateway::BBOData& bbo_data) {
    mm::BBO bbo;
    bbo.symbol = bbo_data.get_symbol();
    bbo.bid_price = bbo_data.bid_price;
    bbo.bid_shares = bbo_data.bid_shares;
    bbo.ask_price = bbo_data.ask_price;
    bbo.ask_shares = bbo_data.ask_shares;
    bbo.spread = bbo_data.spread;
    bbo.timestamp_ns = static_cast<uint64_t>(bbo_data.timestamp_ns);
    bbo.valid = bbo_data.valid;
    return bbo;
}

int main(int argc, char** argv) {
    auto console = spdlog::stdout_color_mt("market_maker");
    spdlog::set_default_logger(console);
    spdlog::set_level(spdlog::level::info);

    std::string config_file = "config.json";
    if (argc > 1) {
        config_file = argv[1];
    }

    mm::MarketMakerFSM::Config mm_config;
    std::string gateway_host = "localhost";
    int gateway_port = 9999;
    bool enable_rt = false;
    bool enable_disruptor = false;
    std::vector<int> cpu_cores = {2, 3};
    bool enable_order_execution = false;

    std::ifstream config_stream(config_file);
    if (config_stream.is_open()) {
        try {
            nlohmann::json config_json;
            config_stream >> config_json;

            if (config_json.contains("min_spread_bps")) {
                mm_config.min_spread_bps = config_json["min_spread_bps"];
            }
            if (config_json.contains("edge_bps")) {
                mm_config.edge_bps = config_json["edge_bps"];
            }
            if (config_json.contains("max_position")) {
                mm_config.max_position = config_json["max_position"];
            }
            if (config_json.contains("position_skew_bps")) {
                mm_config.position_skew_bps = config_json["position_skew_bps"];
            }
            if (config_json.contains("quote_size")) {
                mm_config.quote_size = config_json["quote_size"];
            }
            if (config_json.contains("max_notional")) {
                mm_config.max_notional = config_json["max_notional"];
            }
            if (config_json.contains("gateway_host")) {
                gateway_host = config_json["gateway_host"].get<std::string>();
            }
            if (config_json.contains("gateway_port")) {
                gateway_port = config_json["gateway_port"];
            }
            if (config_json.contains("enable_rt")) {
                enable_rt = config_json["enable_rt"];
            }
            if (config_json.contains("cpu_cores")) {
                cpu_cores = config_json["cpu_cores"].get<std::vector<int>>();
            }
            if (config_json.contains("enable_disruptor")) {
                enable_disruptor = config_json["enable_disruptor"];
            }
            if (config_json.contains("enable_order_execution")) {
                mm_config.enable_order_execution = config_json["enable_order_execution"];
            }
            if (config_json.contains("order_ring_path")) {
                mm_config.order_ring_path = config_json["order_ring_path"].get<std::string>();
            }
            if (config_json.contains("fill_ring_path")) {
                mm_config.fill_ring_path = config_json["fill_ring_path"].get<std::string>();
            }

            spdlog::info("Loaded config from {}", config_file);
        } catch (const std::exception& e) {
            spdlog::warn("Failed to parse config file: {}, using defaults", e.what());
        }
    } else {
        spdlog::info("Config file not found, using defaults");
    }

    if (enable_rt) {
#ifdef __linux__
        enableRealTimeScheduling();
        setCpuAffinity(cpu_cores);
#else
        spdlog::warn("RT optimization only supported on Linux");
#endif
    }

    mm::MarketMakerFSM fsm(mm_config);

    try {
        // Create client to connect to Order Gateway (TCP or Disruptor)
        if (enable_disruptor) {
            spdlog::info("Connecting to Order Gateway via Disruptor (shared memory)...");
            g_listener = std::make_unique<DisruptorClientWrapper>("gateway");
        } else {
            spdlog::info("Connecting to Order Gateway at {}:{}...", gateway_host, gateway_port);
            g_listener = std::make_unique<TCPClientWrapper>(gateway_host, gateway_port);
        }

        g_listener->setPerfMonitor(&g_parse_latency);
        g_listener->start();

        if (enable_disruptor) {
            spdlog::info("Connected to Order Gateway (Disruptor Mode - Shared Memory)");
        } else {
            spdlog::info("Connected to Order Gateway (TCP Mode)");
        }

        std::signal(SIGINT, signalHandler);
        std::signal(SIGTERM, signalHandler);

        if (enable_disruptor) {
            spdlog::info("Market Maker FSM running (Disruptor Mode - Shared Memory)");
        } else {
            spdlog::info("Market Maker FSM running (TCP Client)");
        }
        spdlog::info("Press Ctrl+C to stop");

        while (g_running) {
            try {
                // Process any fill notifications from Project 16
                fsm.processFills();

                // Process BBO updates
                gateway::BBOData bbo_data = g_listener->read_bbo();
                mm::BBO bbo = convertBboData(bbo_data);

                if (bbo.valid) {
                    fsm.onBboUpdate(bbo);
                } else {
                    spdlog::warn("Received invalid BBO");
                }
            } catch (const std::exception& e) {
                if (g_running) {
                    // Timeout is expected when waiting for data - continue polling
                    std::string error_msg = e.what();
                    if (error_msg.find("timeout") != std::string::npos) {
                        // Just continue polling (silent - this is normal)
                        continue;
                    }
                    // For other errors, log and break
                    spdlog::error("Error processing BBO: {}", e.what());
                    break;
                }
            }
        }

        spdlog::info("Main loop exited, g_running={}", g_running);

        if (g_listener) {
            spdlog::info("Stopping listener...");
            g_listener->stop();
        }

        // Print performance statistics
        spdlog::info("Checking latency samples: count={}", g_parse_latency.count());
        if (g_parse_latency.count() > 0) {
            std::string mode = enable_disruptor ? "Disruptor" : "TCP Client";
            spdlog::info("Printing performance summary...");
            g_parse_latency.printSummary("Project 15 (" + mode + ")");
            g_parse_latency.saveToFile("project15_latency.csv");
        } else {
            spdlog::warn("No latency samples recorded");
        }

        spdlog::info("Shutdown complete");

    } catch (const std::exception& e) {
        spdlog::error("Fatal error: {}", e.what());
        return 1;
    }

    return 0;
}