#pragma once

#include <string>
#include <vector>
#include <memory>
#include <thread>
#include <mutex>
#include <boost/asio.hpp>

namespace gateway {

/**
 * TCP Server
 * Simple TCP server for broadcasting JSON BBO updates to multiple clients
 * Uses Boost.Asio for cross-platform networking
 */
class TCPServer {
public:
    /**
     * Constructor
     * @param port TCP port to listen on (default: 9999)
     */
    explicit TCPServer(int port = 9999);

    /**
     * Destructor - closes all connections
     */
    ~TCPServer();

    // Disable copy/move
    TCPServer(const TCPServer&) = delete;
    TCPServer& operator=(const TCPServer&) = delete;

    /**
     * Start listening for connections
     * Creates listening socket and binds to port
     * @throws std::runtime_error if bind/listen fails
     */
    void start();

    /**
     * Accept new client connections (non-blocking)
     * Call this periodically to accept new clients
     * Note: With Boost.Asio async operations, this is handled automatically
     */
    void accept_clients();

    /**
     * Broadcast message to all connected clients
     * @param message Message to send (JSON string)
     */
    void broadcast(const std::string& message);

    /**
     * Get number of connected clients
     * @return Number of active client connections
     */
    size_t client_count() const;

private:
    int port_;
    boost::asio::io_context io_context_;
    boost::asio::ip::tcp::acceptor acceptor_;
    std::vector<std::shared_ptr<boost::asio::ip::tcp::socket>> client_sockets_;
    mutable std::mutex clients_mutex_;
    std::thread io_thread_;
    boost::asio::executor_work_guard<boost::asio::io_context::executor_type> work_guard_;

    /**
     * Start accepting new connections asynchronously
     */
    void start_accept();
};

} // namespace gateway
