#include "system_orchestrator.h"
#include <iostream>
#include <fstream>
#include <sstream>
#include <cstring>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>
#include <netinet/in.h>
#include <arpa/inet.h>

namespace trading_system {

SystemOrchestrator::SystemOrchestrator(const std::string& config_file)
    : config_file_(config_file)
    , running_(false)
    , healthcheck_interval_ms_(500)
    , startup_timeout_seconds_(30)
    , shutdown_timeout_seconds_(10)
    , enable_auto_restart_(false)
    , prometheus_port_(9094)
    , enable_prometheus_(true)
{
    load_config();

    // Initialize metrics aggregator
    metrics_aggregator_ = std::make_unique<MetricsAggregator>();

    // Initialize Prometheus server
    if (enable_prometheus_) {
        prometheus_server_ = std::make_unique<PrometheusServer>(prometheus_port_, metrics_aggregator_.get());
    }
}

SystemOrchestrator::~SystemOrchestrator() {
    stop(false);
}

void SystemOrchestrator::load_config() {
    std::ifstream file(config_file_);
    if (!file.is_open()) {
        throw std::runtime_error("Failed to open config file: " + config_file_);
    }

    file >> config_;

    // Load system-wide settings
    if (config_.contains("system")) {
        auto& sys = config_["system"];
        if (sys.contains("healthcheck_interval_ms")) {
            healthcheck_interval_ms_ = sys["healthcheck_interval_ms"];
        }
        if (sys.contains("startup_timeout_seconds")) {
            startup_timeout_seconds_ = sys["startup_timeout_seconds"];
        }
        if (sys.contains("shutdown_timeout_seconds")) {
            shutdown_timeout_seconds_ = sys["shutdown_timeout_seconds"];
        }
        if (sys.contains("enable_auto_restart")) {
            enable_auto_restart_ = sys["enable_auto_restart"];
        }
    }

    // Load component configurations
    parse_component_config("project_17", Component::HARDWARE_TIMESTAMPING);
    parse_component_config("project_14", Component::ORDER_GATEWAY);
    parse_component_config("project_15", Component::MARKET_MAKER);
    parse_component_config("simulated_exchange", Component::SIMULATED_EXCHANGE);
    parse_component_config("project_16", Component::ORDER_EXECUTION);

    // Load shared memory paths
    if (config_.contains("shared_memory")) {
        for (auto& [key, value] : config_["shared_memory"].items()) {
            if (value.contains("path")) {
                shared_memory_paths_.push_back(value["path"]);
            }
        }
    }

    log("INFO", "Configuration loaded successfully");
}

void SystemOrchestrator::parse_component_config(const std::string& key, Component comp) {
    if (!config_.contains(key)) {
        throw std::runtime_error("Missing component config: " + key);
    }

    auto& cfg = config_[key];
    ProcessInfo info;
    info.component = comp;
    info.name = cfg["name"];
    info.executable = cfg["executable"];
    info.config_file = cfg.value("config_file", "");
    
    // Parse command line arguments if provided
    if (cfg.contains("args")) {
        for (const auto& arg : cfg["args"]) {
            info.args.push_back(arg.get<std::string>());
        }
    }
    
    // Parse XDP command line arguments if provided
    if (cfg.contains("args_xdp")) {
        for (const auto& arg : cfg["args_xdp"]) {
            info.args_xdp.push_back(arg.get<std::string>());
        }
    }
    
    info.enable_xdp = cfg.value("enable_xdp", false);
    info.requires_sudo = cfg.value("requires_sudo", false);
    
    info.working_directory = cfg.value("working_directory", ".");

    // Dependencies
    if (cfg.contains("depends_on")) {
        for (auto& dep : cfg["depends_on"]) {
            info.dependencies.push_back(dep);
        }
    }

    // Health check configuration
    if (cfg.contains("healthcheck")) {
        auto& hc = cfg["healthcheck"];
        info.healthcheck_type = hc["type"];
        info.healthcheck_host = hc.value("host", "localhost");
        info.healthcheck_port = hc.value("port", 0);
        info.healthcheck_url = hc.value("url", "");
        info.healthcheck_timeout_ms = hc.value("timeout_ms", 1000);
    }

    processes_[comp] = info;
}

bool SystemOrchestrator::start() {
    log("INFO", "Starting FPGA Trading System...");

    // Cleanup stale shared memory
    cleanup_shared_memory();

    // Create shared memory segments
    if (!create_shared_memory()) {
        log("ERROR", "Failed to create shared memory segments");
        return false;
    }

    // Start components in dependency order
    if (!start_components_in_order()) {
        log("ERROR", "Failed to start all components");
        stop(true);
        return false;
    }

    // Start metrics aggregator
    metrics_aggregator_->start(1000);  // Collect metrics every 1 second

    // Start Prometheus server
    if (enable_prometheus_ && prometheus_server_) {
        prometheus_server_->start();
        log("INFO", "Prometheus metrics available at: " + prometheus_server_->get_metrics_url());
    }

    // Start monitoring thread
    running_.store(true);
    monitor_thread_ = std::thread(&SystemOrchestrator::monitor_processes, this);

    log("INFO", "Trading system started successfully");
    return true;
}

void SystemOrchestrator::stop(bool force) {
    log("INFO", "Stopping FPGA Trading System...");

    running_.store(false);

    // Stop Prometheus server
    if (prometheus_server_) {
        prometheus_server_->stop();
    }

    // Stop metrics aggregator
    if (metrics_aggregator_) {
        metrics_aggregator_->stop();
    }

    // Stop monitoring thread
    if (monitor_thread_.joinable()) {
        monitor_thread_.join();
    }

    // Stop components in reverse order
    std::vector<Component> stop_order = {
        Component::ORDER_EXECUTION,
        Component::SIMULATED_EXCHANGE,
        Component::MARKET_MAKER,
        Component::ORDER_GATEWAY,
        Component::HARDWARE_TIMESTAMPING
    };

    for (auto comp : stop_order) {
        stop_component(comp, force);
    }

    // Cleanup shared memory
    cleanup_shared_memory();

    // Reap any zombie processes
    reap_zombie_processes();

    log("INFO", "Trading system stopped");
}

bool SystemOrchestrator::restart() {
    log("INFO", "Restarting trading system...");
    stop(false);
    std::this_thread::sleep_for(std::chrono::seconds(2));
    return start();
}

bool SystemOrchestrator::start_component(Component comp) {
    auto& info = processes_[comp];

    if (info.state == ComponentState::RUNNING) {
        log("WARN", info.name + " is already running");
        return true;
    }

    // Check dependencies
    if (!are_dependencies_running(info)) {
        log("ERROR", "Dependencies not met for " + info.name);
        return false;
    }

    log("INFO", "Starting " + info.name + "...");

    info.state = ComponentState::STARTING;

    // Spawn process
    pid_t pid = spawn_process(info);
    if (pid < 0) {
        log("ERROR", "Failed to spawn " + info.name);
        info.state = ComponentState::FAILED;
        return false;
    }

    info.pid = pid;
    info.started_at = std::chrono::steady_clock::now();

    // Wait for component to be ready
    if (!wait_for_component_ready(comp)) {
        log("ERROR", info.name + " failed to start within timeout");
        stop_component(comp, true);
        info.state = ComponentState::FAILED;
        return false;
    }

    info.state = ComponentState::RUNNING;
    log("INFO", info.name + " started successfully (PID: " + std::to_string(pid) + ")");

    return true;
}

void SystemOrchestrator::stop_component(Component comp, bool force) {
    auto& info = processes_[comp];

    if (info.state == ComponentState::STOPPED || info.pid <= 0) {
        return;
    }

    log("INFO", "Stopping " + info.name + "...");

    info.state = ComponentState::STOPPING;

    if (force) {
        // Send SIGKILL immediately
        kill(info.pid, SIGKILL);
    } else {
        // Send SIGTERM and wait
        kill(info.pid, SIGTERM);

        auto start = std::chrono::steady_clock::now();
        while (check_process_alive(info.pid)) {
            auto elapsed = std::chrono::steady_clock::now() - start;
            if (elapsed > std::chrono::seconds(shutdown_timeout_seconds_)) {
                log("WARN", info.name + " didn't stop gracefully, sending SIGKILL");
                kill(info.pid, SIGKILL);
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }

    // Wait for process to exit
    int status;
    waitpid(info.pid, &status, 0);

    info.pid = -1;
    info.state = ComponentState::STOPPED;
    info.exit_code = WEXITSTATUS(status);

    log("INFO", info.name + " stopped");
}

bool SystemOrchestrator::is_running(Component comp) const {
    auto it = processes_.find(comp);
    if (it == processes_.end()) {
        return false;
    }
    return it->second.state == ComponentState::RUNNING;
}

ComponentState SystemOrchestrator::get_component_state(Component comp) const {
    auto it = processes_.find(comp);
    if (it == processes_.end()) {
        return ComponentState::STOPPED;
    }
    return it->second.state;
}

SystemHealth SystemOrchestrator::get_system_health() {
    SystemHealth health;
    health.last_check = std::chrono::steady_clock::now();

    // Check all components
    health.all_components_running = true;
    for (auto& [comp, info] : processes_) {
        bool comp_healthy = check_component_health(comp);
        health.component_health[comp] = comp_healthy;

        if (!comp_healthy) {
            health.all_components_running = false;
        }
    }

    // Check ring buffers
    health.ring_buffers_healthy = verify_shared_memory();
    health.shared_memory_healthy = verify_shared_memory();

    // TODO: Collect metrics from components
    health.total_bbo_updates = 0;
    health.total_orders = 0;
    health.total_fills = 0;
    health.current_position = 0;
    health.unrealized_pnl = 0.0;

    return health;
}

const ProcessInfo& SystemOrchestrator::get_process_info(Component comp) const {
    return processes_.at(comp);
}

void SystemOrchestrator::run() {
    log("INFO", "Orchestrator monitoring started");

    while (running_.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(healthcheck_interval_ms_));

        // Health checks are done in monitor_processes() thread
    }

    log("INFO", "Orchestrator monitoring stopped");
}

// Private methods

pid_t SystemOrchestrator::spawn_process(const ProcessInfo& info) {
    // Debug: Log what arguments we're about to use
    log("DEBUG", "Spawning " + info.name + " with executable: " + info.executable);
    log("DEBUG", "Regular args count: " + std::to_string(info.args.size()));
    log("DEBUG", "XDP args count: " + std::to_string(info.args_xdp.size()));
    log("DEBUG", "Config file: " + info.config_file);
    log("DEBUG", "Requires sudo: " + std::string(info.requires_sudo ? "true" : "false"));
    
    pid_t pid = fork();

    if (pid < 0) {
        log("ERROR", "Fork failed: " + std::string(strerror(errno)));
        return -1;
    }

    if (pid == 0) {
        // Child process

        // Change working directory
        if (!info.working_directory.empty()) {
            if (chdir(info.working_directory.c_str()) < 0) {
                std::cerr << "Failed to chdir to " << info.working_directory << std::endl;
                exit(1);
            }
        }

        // Build argument list
        std::vector<char*> args;
        args.push_back(const_cast<char*>(info.executable.c_str()));

        // Determine which arguments to use
        std::vector<std::string> selected_args;
        
        if (info.enable_xdp && !info.args_xdp.empty()) {
            // Use XDP args if XDP is enabled
            selected_args = info.args_xdp;
            std::cerr << "DEBUG: Using XDP args (" << selected_args.size() << " args) - XDP mode enabled" << std::endl;
            if (info.requires_sudo) {
                std::cerr << "WARNING: " << info.name << " is configured for XDP mode but not running with sudo." << std::endl;
                std::cerr << "INFO: XDP features may not work properly. Consider running with sudo for full XDP support." << std::endl;
            }
        } else if (!info.args.empty()) {
            // Use regular args
            selected_args = info.args;
            std::cerr << "DEBUG: Using regular args (" << selected_args.size() << " args)" << std::endl;
        } else if (!info.config_file.empty()) {
            // Fall back to config file
            std::cerr << "DEBUG: Using config file: " << info.config_file << std::endl;
            args.push_back(const_cast<char*>(info.config_file.c_str()));
        } else {
            std::cerr << "ERROR: No arguments or config file specified for " << info.name << std::endl;
        }

        // Add selected arguments
        for (const auto& arg : selected_args) {
            args.push_back(const_cast<char*>(arg.c_str()));
        }

        args.push_back(nullptr);
        
        // Debug: Print final command line
        std::cerr << "DEBUG: Final command: ";
        for (size_t i = 0; i < args.size() - 1; ++i) {
            std::cerr << args[i] << " ";
        }
        std::cerr << std::endl;

        // Execute
        execvp(info.executable.c_str(), args.data());

        // If execvp returns, it failed
        std::cerr << "Failed to execute " << info.executable << ": " << strerror(errno) << std::endl;
        exit(1);
    }

    // Parent process
    return pid;
}

bool SystemOrchestrator::wait_for_component_ready(Component comp) {
    auto& info = processes_[comp];
    auto start = std::chrono::steady_clock::now();

    while (true) {
        if (check_component_health(comp)) {
            return true;
        }

        // Check if process crashed
        if (!check_process_alive(info.pid)) {
            log("ERROR", info.name + " crashed during startup");
            return false;
        }

        // Check timeout
        auto elapsed = std::chrono::steady_clock::now() - start;
        if (elapsed > std::chrono::seconds(startup_timeout_seconds_)) {
            return false;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
}

bool SystemOrchestrator::check_component_health(Component comp) {
    auto& info = processes_[comp];

    // First check if process is alive
    if (!check_process_alive(info.pid)) {
        return false;
    }

    // Perform type-specific health check
    if (info.healthcheck_type == "tcp") {
        // Try to connect to TCP port
        int sock = socket(AF_INET, SOCK_STREAM, 0);
        if (sock < 0) {
            return false;
        }

        struct sockaddr_in addr = {};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(info.healthcheck_port);
        inet_pton(AF_INET, info.healthcheck_host.c_str(), &addr.sin_addr);

        // Set non-blocking for timeout
        struct timeval timeout;
        timeout.tv_sec = info.healthcheck_timeout_ms / 1000;
        timeout.tv_usec = (info.healthcheck_timeout_ms % 1000) * 1000;
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

        bool connected = (connect(sock, (struct sockaddr*)&addr, sizeof(addr)) == 0);
        close(sock);

        return connected;
    } else if (info.healthcheck_type == "prometheus") {
        // TODO: Implement HTTP GET to Prometheus endpoint
        // For now, just check if process is alive
        return check_process_alive(info.pid);
    }

    // Default: just check if process is alive
    return check_process_alive(info.pid);
}

void SystemOrchestrator::monitor_processes() {
    while (running_.load()) {
        for (auto& [comp, info] : processes_) {
            if (info.state == ComponentState::RUNNING) {
                if (!check_component_health(comp)) {
                    log("WARN", info.name + " health check failed");

                    // Check if process crashed
                    if (!check_process_alive(info.pid)) {
                        log("ERROR", info.name + " crashed (PID: " + std::to_string(info.pid) + ")");
                        info.state = ComponentState::FAILED;

                        if (enable_auto_restart_) {
                            log("INFO", "Auto-restarting " + info.name + "...");
                            info.restart_count++;
                            start_component(comp);
                        }
                    }
                }
            }
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(healthcheck_interval_ms_));
    }
}

bool SystemOrchestrator::check_process_alive(pid_t pid) {
    if (pid <= 0) {
        return false;
    }

    // Send signal 0 to check if process exists
    return (kill(pid, 0) == 0);
}

void SystemOrchestrator::reap_zombie_processes() {
    int status;
    while (waitpid(-1, &status, WNOHANG) > 0) {
        // Reap zombie
    }
}

void SystemOrchestrator::cleanup_shared_memory() {
    for (const auto& path : shared_memory_paths_) {
        if (shm_unlink(path.c_str()) == 0) {
            log("INFO", "Cleaned up shared memory: " + path);
        }
    }
}

bool SystemOrchestrator::create_shared_memory() {
    // Shared memory is created by the components themselves
    // This function could pre-create them if needed
    return true;
}

bool SystemOrchestrator::verify_shared_memory() {
    for (const auto& path : shared_memory_paths_) {
        int fd = shm_open(path.c_str(), O_RDONLY, 0666);
        if (fd < 0) {
            return false;
        }
        close(fd);
    }
    return true;
}

bool SystemOrchestrator::start_components_in_order() {
    // Start in dependency order
    std::vector<Component> start_order = {
        Component::ORDER_GATEWAY,
        Component::MARKET_MAKER,
        Component::SIMULATED_EXCHANGE,
        Component::ORDER_EXECUTION
    };

    for (auto comp : start_order) {
        // Add startup delay if configured
        std::string cfg_key;
        switch (comp) {
            case Component::ORDER_GATEWAY: cfg_key = "project_14"; break;
            case Component::MARKET_MAKER: cfg_key = "project_15"; break;
            case Component::SIMULATED_EXCHANGE: cfg_key = "simulated_exchange"; break;
            case Component::ORDER_EXECUTION: cfg_key = "project_16"; break;
            default: cfg_key = "unknown"; break;
        }

        if (config_[cfg_key].contains("startup_delay_ms")) {
            int delay = config_[cfg_key]["startup_delay_ms"];
            if (delay > 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(delay));
            }
        }

        if (!start_component(comp)) {
            return false;
        }
    }

    return true;
}

bool SystemOrchestrator::are_dependencies_running(const ProcessInfo& info) {
    for (const auto& dep_str : info.dependencies) {
        Component dep = string_to_component(dep_str);
        if (!is_running(dep)) {
            return false;
        }
    }
    return true;
}

std::string SystemOrchestrator::component_to_string(Component comp) const {
    switch (comp) {
        case Component::HARDWARE_TIMESTAMPING: return "HARDWARE_TIMESTAMPING";
        case Component::ORDER_GATEWAY: return "ORDER_GATEWAY";
        case Component::MARKET_MAKER: return "MARKET_MAKER";
        case Component::SIMULATED_EXCHANGE: return "SIMULATED_EXCHANGE";
        case Component::ORDER_EXECUTION: return "ORDER_EXECUTION";
        default: return "UNKNOWN";
    }
}

Component SystemOrchestrator::string_to_component(const std::string& str) const {
    if (str == "project_17" || str == "HARDWARE_TIMESTAMPING") return Component::HARDWARE_TIMESTAMPING;
    if (str == "project_14" || str == "ORDER_GATEWAY") return Component::ORDER_GATEWAY;
    if (str == "project_15" || str == "MARKET_MAKER") return Component::MARKET_MAKER;
    if (str == "simulated_exchange" || str == "SIMULATED_EXCHANGE") return Component::SIMULATED_EXCHANGE;
    if (str == "project_16" || str == "ORDER_EXECUTION") return Component::ORDER_EXECUTION;
    throw std::runtime_error("Unknown component: " + str);
}

void SystemOrchestrator::log(const std::string& level, const std::string& message) {
    auto now = std::chrono::system_clock::now();
    auto time_t = std::chrono::system_clock::to_time_t(now);
    char time_buf[32];
    strftime(time_buf, sizeof(time_buf), "%Y-%m-%d %H:%M:%S", localtime(&time_t));

    std::cout << "[" << time_buf << "] [" << level << "] [Orchestrator] " << message << std::endl;
}

} // namespace trading_system
