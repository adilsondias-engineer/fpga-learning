#include <iostream>
#include <csignal>
#include <fstream>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <nlohmann/json.hpp>
#include "market_maker_fsm.h"
#include "tcp_client.h"
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

std::unique_ptr<ListenerBase> g_listener;
gateway::PerfMonitor g_parse_latency;  // Global performance monitor

void signalHandler(int signal) {
    spdlog::info("Received signal {}, shutting down...", signal);
    g_running = false;
    if (g_listener) {
        g_listener->stop();
    }
}

mm::BBO convertBboData(const gateway::BBOData& bbo_data) {
    mm::BBO bbo;
    bbo.symbol = bbo_data.symbol;
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
    std::vector<int> cpu_cores = {2, 3};

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
        // Create TCP client to connect to Order Gateway (Project 14)
        spdlog::info("Connecting to Order Gateway at {}:{}...", gateway_host, gateway_port);
        g_listener = std::make_unique<TCPClientWrapper>(gateway_host, gateway_port);
        g_listener->setPerfMonitor(&g_parse_latency);
        g_listener->start();
        spdlog::info("Connected to Order Gateway");

        std::signal(SIGINT, signalHandler);
        std::signal(SIGTERM, signalHandler);

        spdlog::info("Market Maker FSM running");
        spdlog::info("Press Ctrl+C to stop");

        while (g_running) {
            try {
                gateway::BBOData bbo_data = g_listener->read_bbo();
                mm::BBO bbo = convertBboData(bbo_data);

                if (bbo.valid) {
                    fsm.onBboUpdate(bbo);
                }
            } catch (const std::exception& e) {
                if (g_running) {
                    spdlog::error("Error processing BBO: {}", e.what());
                }
                break;
            }
        }

        if (g_listener) {
            g_listener->stop();
        }

        // Print performance statistics
        if (g_parse_latency.count() > 0) {
            g_parse_latency.printSummary("Project 15 (TCP Client)");
            g_parse_latency.saveToFile("project15_latency.csv");
        }

        spdlog::info("Shutdown complete");

    } catch (const std::exception& e) {
        spdlog::error("Fatal error: {}", e.what());
        return 1;
    }

    return 0;
}