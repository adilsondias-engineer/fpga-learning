#pragma once

#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <atomic>
#include <chrono>
#include <thread>
#include <nlohmann/json.hpp>
#include "metrics_aggregator.h"
#include "prometheus_server.h"

namespace trading_system {

using json = nlohmann::json;

/**
 * Component identifier
 */
enum class Component {
    HARDWARE_TIMESTAMPING,  // Project 17
    ORDER_GATEWAY,          // Project 14
    MARKET_MAKER,           // Project 15
    SIMULATED_EXCHANGE,     // Simulated Exchange for Project 16
    ORDER_EXECUTION         // Project 16
};

/**
 * Component state
 */
enum class ComponentState {
    STOPPED,
    STARTING,
    RUNNING,
    STOPPING,
    FAILED
};

/**
 * Process information for managed component
 */
struct ProcessInfo {
    Component component;
    std::string name;
    std::string executable;
    std::string config_file;
    std::vector<std::string> args;
    std::vector<std::string> args_xdp;
    bool enable_xdp;
    bool requires_sudo;
    std::string working_directory;
    std::vector<std::string> dependencies;

    pid_t pid;
    ComponentState state;
    std::chrono::steady_clock::time_point started_at;
    std::chrono::steady_clock::time_point last_heartbeat;

    int restart_count;
    int exit_code;

    // Health check configuration
    std::string healthcheck_type;  // "tcp", "prometheus", "file"
    std::string healthcheck_url;
    std::string healthcheck_host;
    uint16_t healthcheck_port;
    int healthcheck_timeout_ms;

    // Metrics
    uint64_t packets_processed;
    uint64_t errors;
    uint64_t latency_p50_ns;
    uint64_t latency_p99_ns;

    ProcessInfo()
        : component(Component::ORDER_GATEWAY)
        , enable_xdp(false)
        , requires_sudo(false)
        , pid(-1)
        , state(ComponentState::STOPPED)
        , restart_count(0)
        , exit_code(0)
        , healthcheck_port(0)
        , healthcheck_timeout_ms(1000)
        , packets_processed(0)
        , errors(0)
        , latency_p50_ns(0)
        , latency_p99_ns(0)
    {}
};

/**
 * System health status
 */
struct SystemHealth {
    bool all_components_running;
    bool ring_buffers_healthy;
    bool shared_memory_healthy;

    std::unordered_map<Component, bool> component_health;

    uint64_t total_bbo_updates;
    uint64_t total_orders;
    uint64_t total_fills;

    int32_t current_position;
    double unrealized_pnl;

    std::chrono::steady_clock::time_point last_check;
};

/**
 * System orchestrator - manages lifecycle of all trading components
 */
class SystemOrchestrator {
public:
    /**
     * Create system orchestrator
     * @param config_file Path to system_config.json
     */
    explicit SystemOrchestrator(const std::string& config_file);

    ~SystemOrchestrator();

    // Delete copy/move
    SystemOrchestrator(const SystemOrchestrator&) = delete;
    SystemOrchestrator& operator=(const SystemOrchestrator&) = delete;

    /**
     * Start entire trading system
     * @return true if all components started successfully
     */
    bool start();

    /**
     * Stop entire trading system
     * @param force If true, send SIGKILL immediately
     */
    void stop(bool force = false);

    /**
     * Restart entire system (stop + start)
     */
    bool restart();

    /**
     * Start specific component
     * @param comp Component to start
     * @return true if started successfully
     */
    bool start_component(Component comp);

    /**
     * Stop specific component
     * @param comp Component to stop
     * @param force If true, send SIGKILL immediately
     */
    void stop_component(Component comp, bool force = false);

    /**
     * Check if component is running
     */
    bool is_running(Component comp) const;

    /**
     * Get component state
     */
    ComponentState get_component_state(Component comp) const;

    /**
     * Get system health
     */
    SystemHealth get_system_health();

    /**
     * Get process info for component
     */
    const ProcessInfo& get_process_info(Component comp) const;

    /**
     * Run monitoring loop (blocks until stopped)
     */
    void run();

private:
    // Configuration
    json config_;
    std::string config_file_;

    // Process management
    std::unordered_map<Component, ProcessInfo> processes_;
    std::atomic<bool> running_;

    // Monitoring thread
    std::thread monitor_thread_;
    int healthcheck_interval_ms_;
    int startup_timeout_seconds_;
    int shutdown_timeout_seconds_;
    bool enable_auto_restart_;

    // Shared memory paths
    std::vector<std::string> shared_memory_paths_;

    // Metrics and monitoring
    std::unique_ptr<MetricsAggregator> metrics_aggregator_;
    std::unique_ptr<PrometheusServer> prometheus_server_;
    uint16_t prometheus_port_;
    bool enable_prometheus_;

    // Load configuration
    void load_config();
    void parse_component_config(const std::string& key, Component comp);

    // Process management
    pid_t spawn_process(const ProcessInfo& info);
    bool wait_for_component_ready(Component comp);
    bool check_component_health(Component comp);
    void monitor_processes();
    bool check_process_alive(pid_t pid);
    void reap_zombie_processes();

    // Shared memory management
    void cleanup_shared_memory();
    bool create_shared_memory();
    bool verify_shared_memory();

    // Dependency management
    bool start_components_in_order();
    bool are_dependencies_running(const ProcessInfo& info);

    // Utilities
    std::string component_to_string(Component comp) const;
    Component string_to_component(const std::string& str) const;
    void log(const std::string& level, const std::string& message);
};

} // namespace trading_system
