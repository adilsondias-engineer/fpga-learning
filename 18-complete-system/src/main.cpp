#include "system_orchestrator.h"
#include <iostream>
#include <csignal>
#include <atomic>

using namespace trading_system;

// Global orchestrator pointer for signal handling
static SystemOrchestrator* g_orchestrator = nullptr;
static std::atomic<bool> g_shutdown_requested{false};

void signal_handler(int signal) {
    if (signal == SIGINT || signal == SIGTERM) {
        std::cout << "\nReceived shutdown signal, stopping trading system..." << std::endl;
        g_shutdown_requested.store(true);

        if (g_orchestrator) {
            g_orchestrator->stop(false);
        }
    }
}

void print_usage(const char* program) {
    std::cout << "Usage: " << program << " [config_file]" << std::endl;
    std::cout << std::endl;
    std::cout << "Arguments:" << std::endl;
    std::cout << "  config_file    Path to system_config.json (default: config/system_config.json)" << std::endl;
    std::cout << std::endl;
    std::cout << "Example:" << std::endl;
    std::cout << "  " << program << " config/system_config.json" << std::endl;
}

int main(int argc, char* argv[]) {
    // Default config file
    std::string config_file = "config/system_config.json";

    // Parse command line arguments
    if (argc > 1) {
        std::string arg = argv[1];
        if (arg == "--help" || arg == "-h") {
            print_usage(argv[0]);
            return 0;
        }
        config_file = argv[1];
    }

    std::cout << "========================================" << std::endl;
    std::cout << "FPGA Trading System - Orchestrator" << std::endl;
    std::cout << "Project 18: Complete System Integration" << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "Config file: " << config_file << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << std::endl;

    try {
        // Create orchestrator
        SystemOrchestrator orchestrator(config_file);
        g_orchestrator = &orchestrator;

        // Setup signal handlers
        std::signal(SIGINT, signal_handler);
        std::signal(SIGTERM, signal_handler);

        // Start trading system
        if (!orchestrator.start()) {
            std::cerr << "Failed to start trading system" << std::endl;
            return 1;
        }

        std::cout << std::endl;
        std::cout << "========================================" << std::endl;
        std::cout << "Trading System Status:" << std::endl;
        std::cout << "========================================" << std::endl;

        // Print component status
        std::vector<Component> components = {
            Component::ORDER_GATEWAY,
            Component::MARKET_MAKER,
            Component::ORDER_EXECUTION
        };

        for (auto comp : components) {
            const auto& info = orchestrator.get_process_info(comp);
            std::cout << info.name << ": ";

            switch (info.state) {
                case ComponentState::RUNNING:
                    std::cout << "RUNNING (PID: " << info.pid << ")";
                    break;
                case ComponentState::STOPPED:
                    std::cout << "STOPPED";
                    break;
                case ComponentState::FAILED:
                    std::cout << "FAILED";
                    break;
                default:
                    std::cout << "UNKNOWN";
            }
            std::cout << std::endl;
        }

        std::cout << "========================================" << std::endl;
        std::cout << std::endl;
        std::cout << "Trading system is running." << std::endl;
        std::cout << "Press Ctrl+C to stop." << std::endl;
        std::cout << std::endl;

        // Run monitoring loop
        orchestrator.run();

        std::cout << "Trading system stopped successfully" << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "Fatal error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
