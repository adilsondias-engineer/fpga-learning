#include "uart_reader.h"
#include "bbo_parser.h"
#include "tcp_server.h"
#include "csv_logger.h"
#include <iostream>
#include <stdexcept>
#include <csignal>
#include <atomic>

using namespace gateway;

// Global flag for graceful shutdown
std::atomic<bool> running(true);

void signal_handler(int signal) {
    std::cout << "\nShutdown signal received (" << signal << ")" << std::endl;
    running = false;
}

void print_usage(const char* program_name) {
    std::cout << "Usage: " << program_name << " <uart_port> [tcp_port] [csv_file]" << std::endl;
    std::cout << std::endl;
    std::cout << "Arguments:" << std::endl;
    std::cout << "  uart_port  - Serial port name (e.g., COM3 or /dev/ttyUSB0)" << std::endl;
    std::cout << "  tcp_port   - TCP port for JSON output (default: 9999)" << std::endl;
    std::cout << "  csv_file   - CSV log file (optional)" << std::endl;
    std::cout << std::endl;
    std::cout << "Examples:" << std::endl;
    std::cout << "  " << program_name << " COM3" << std::endl;
    std::cout << "  " << program_name << " /dev/ttyUSB0 9999" << std::endl;
    std::cout << "  " << program_name << " COM3 9999 bbo_log.csv" << std::endl;
}

int main(int argc, char** argv) {
    // Parse command-line arguments
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    std::string uart_port = argv[1];
    int tcp_port = (argc >= 3) ? std::stoi(argv[2]) : 9999;
    std::string csv_file = (argc >= 4) ? argv[3] : "";

    // Install signal handler for graceful shutdown
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    try {
        // TODO: Create components
        //
        // Steps:
        // 1. Create UartReader with uart_port and 115200 baud
        // 2. Create TCPServer with tcp_port
        // 3. Create CSVLogger if csv_file is provided
        // 4. Start TCP server
        //
        // Example:
        //   UartReader uart(uart_port, 115200);
        //   TCPServer server(tcp_port);
        //   CSVLogger* logger = csv_file.empty() ? nullptr : new CSVLogger(csv_file);
        //   server.start();

        std::cout << "C++ Order Gateway - Starting..." << std::endl;
        std::cout << "UART Port: " << uart_port << std::endl;
        std::cout << "TCP Port: " << tcp_port << std::endl;
        if (!csv_file.empty()) {
            std::cout << "CSV Log: " << csv_file << std::endl;
        }
        std::cout << std::endl;

        // TODO: Initialize components here

        std::cout << "Gateway running. Press Ctrl+C to stop." << std::endl;
        std::cout << std::endl;

        // Main processing loop
        while (running) {
            // TODO: Implement main processing loop
            //
            // Steps:
            // 1. Accept new TCP clients (server.accept_clients())
            // 2. Read line from UART (uart.read_line())
            // 3. Parse BBO (BBOParser::parse(line))
            // 4. If BBO is valid:
            //    a. Convert to JSON (bbo_to_json(bbo))
            //    b. Broadcast to TCP clients (server.broadcast(json))
            //    c. Log to CSV if logger exists (logger->log(bbo))
            //    d. Print to console (optional, for debugging)
            // 5. If BBO is invalid (NODATA), skip or print status
            //
            // Example:
            //   server.accept_clients();
            //   std::string line = uart.read_line();
            //   BBOData bbo = BBOParser::parse(line);
            //   if (bbo.valid) {
            //       std::string json = bbo_to_json(bbo);
            //       server.broadcast(json);
            //       if (logger) logger->log(bbo);
            //       std::cout << "[" << bbo.symbol << "] Bid: " << bbo.bid_price
            //                 << " (" << bbo.bid_shares << ") | Ask: " << bbo.ask_price
            //                 << " (" << bbo.ask_shares << ") | Spread: " << bbo.spread << std::endl;
            //   }
            //
            // Note: read_line() is blocking, so this loop will wait for UART data
        }

        std::cout << std::endl;
        std::cout << "Gateway stopped." << std::endl;

        // TODO: Cleanup (if using raw pointers)
        // delete logger;

    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
