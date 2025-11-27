#include "prometheus_exporter.h"
#include <stdexcept>
#include <cstring>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sstream>

namespace timestamp {

PrometheusExporter::PrometheusExporter(uint16_t port)
    : port_(port)
    , running_(false)
    , server_socket_(-1)
{
}

PrometheusExporter::~PrometheusExporter() {
    stop();
}

void PrometheusExporter::register_tracker(const LatencyTracker* tracker) {
    trackers_.push_back(tracker);
}

void PrometheusExporter::start() {
    if (running_.load()) {
        return;  // Already running
    }

    // Create TCP socket
    server_socket_ = socket(AF_INET, SOCK_STREAM, 0);
    if (server_socket_ < 0) {
        throw std::runtime_error("Failed to create server socket: " + std::string(strerror(errno)));
    }

    // Set SO_REUSEADDR
    int reuse = 1;
    if (setsockopt(server_socket_, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
        close(server_socket_);
        throw std::runtime_error("Failed to set SO_REUSEADDR: " + std::string(strerror(errno)));
    }

    // Bind to port
    sockaddr_in addr = {};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port_);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(server_socket_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(server_socket_);
        throw std::runtime_error("Failed to bind to port " + std::to_string(port_) +
                                 ": " + std::string(strerror(errno)));
    }

    // Listen for connections
    if (listen(server_socket_, 5) < 0) {
        close(server_socket_);
        throw std::runtime_error("Failed to listen: " + std::string(strerror(errno)));
    }

    // Start server thread
    running_.store(true);
    server_thread_ = std::thread(&PrometheusExporter::server_loop, this);
}

void PrometheusExporter::stop() {
    if (!running_.load()) {
        return;  // Already stopped
    }

    running_.store(false);

    // Close server socket to unblock accept()
    if (server_socket_ >= 0) {
        shutdown(server_socket_, SHUT_RDWR);
        close(server_socket_);
        server_socket_ = -1;
    }

    // Wait for server thread
    if (server_thread_.joinable()) {
        server_thread_.join();
    }
}

std::string PrometheusExporter::get_metrics_url() const {
    return "http://localhost:" + std::to_string(port_) + "/metrics";
}

void PrometheusExporter::server_loop() {
    while (running_.load()) {
        // Accept client connection
        sockaddr_in client_addr = {};
        socklen_t client_len = sizeof(client_addr);

        int client_socket = accept(server_socket_, (struct sockaddr*)&client_addr, &client_len);
        if (client_socket < 0) {
            if (!running_.load()) {
                break;  // Shutting down
            }
            continue;  // Accept error, retry
        }

        // Handle request
        handle_request(client_socket);

        // Close client connection
        close(client_socket);
    }
}

void PrometheusExporter::handle_request(int client_socket) {
    // Read HTTP request (we don't parse it, just check for GET /metrics)
    char buffer[1024];
    ssize_t len = recv(client_socket, buffer, sizeof(buffer) - 1, 0);
    if (len <= 0) {
        return;
    }

    buffer[len] = '\0';

    // Check if request is for /metrics
    if (strstr(buffer, "GET /metrics") != nullptr) {
        // Generate metrics
        std::string metrics = generate_metrics();

        // Send HTTP response
        send_response(client_socket, metrics);
    } else {
        // 404 Not Found
        std::string response = "HTTP/1.1 404 Not Found\r\n"
                               "Content-Length: 0\r\n"
                               "\r\n";
        send(client_socket, response.c_str(), response.size(), 0);
    }
}

std::string PrometheusExporter::generate_metrics() const {
    std::ostringstream oss;

    // Export metrics from all registered trackers
    for (const auto* tracker : trackers_) {
        oss << tracker->export_prometheus() << "\n";
    }

    return oss.str();
}

void PrometheusExporter::send_response(int client_socket, const std::string& content) {
    std::ostringstream oss;

    // HTTP headers
    oss << "HTTP/1.1 200 OK\r\n";
    oss << "Content-Type: text/plain; version=0.0.4\r\n";
    oss << "Content-Length: " << content.size() << "\r\n";
    oss << "Connection: close\r\n";
    oss << "\r\n";

    // HTTP body (metrics)
    oss << content;

    std::string response = oss.str();
    send(client_socket, response.c_str(), response.size(), 0);
}

} // namespace timestamp
