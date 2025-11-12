#include "tcp_server.h"
#include <stdexcept>
#include <algorithm>

#ifdef _WIN32
    #include <winsock2.h>
    #include <ws2tcpip.h>
    #pragma comment(lib, "ws2_32.lib")
#else
    #include <sys/socket.h>
    #include <netinet/in.h>
    #include <arpa/inet.h>
    #include <unistd.h>
    #include <fcntl.h>
#endif

namespace gateway {

TCPServer::TCPServer(int port)
    : port_(port), listen_socket_(nullptr) {
    init_platform();
}

TCPServer::~TCPServer() {
    // TODO: Close all client connections
    for (auto* socket : client_sockets_) {
        close_socket(socket);
    }

    // TODO: Close listening socket
    if (listen_socket_ != nullptr) {
        close_socket(listen_socket_);
    }

#ifdef _WIN32
    // TODO: WSACleanup();
#endif
}

void TCPServer::start() {
    // TODO: Create TCP listening socket
    //
    // Steps:
    // 1. Create socket: socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    // 2. Set socket options: SO_REUSEADDR
    // 3. Bind to localhost:port
    // 4. Listen with backlog of 10
    // 5. Set non-blocking mode (optional, for accept_clients())
    //
    // Windows: Use Winsock2 API (socket, bind, listen, ioctlsocket)
    // Linux:   Use POSIX sockets (socket, bind, listen, fcntl)
    //
    // Hint: Store socket handle in listen_socket_
    // Hint: Throw std::runtime_error if bind/listen fails

#ifdef _WIN32
    // TODO: Windows socket implementation
#else
    // TODO: Linux socket implementation
#endif
}

void TCPServer::accept_clients() {
    // TODO: Accept new client connections (non-blocking)
    //
    // Steps:
    // 1. Call accept() on listen_socket_
    // 2. If no pending connection (EWOULDBLOCK), return
    // 3. If new client connected, add to client_sockets_ vector
    //
    // Hint: Set accepted socket to non-blocking mode for broadcast()

#ifdef _WIN32
    // TODO: Windows accept() implementation
#else
    // TODO: Linux accept() implementation
#endif
}

void TCPServer::broadcast(const std::string& message) {
    // TODO: Send message to all connected clients
    //
    // Steps:
    // 1. Add newline to message (if not already present)
    // 2. Loop through client_sockets_
    // 3. Send message using send() or write()
    // 4. If send fails (client disconnected), remove from list
    //
    // Hint: Use remove_client() for disconnected clients

#ifdef _WIN32
    // TODO: Windows send() implementation
#else
    // TODO: Linux write() implementation
#endif
}

size_t TCPServer::client_count() const {
    return client_sockets_.size();
}

void TCPServer::init_platform() {
#ifdef _WIN32
    // TODO: Initialize Winsock
    //
    // Steps:
    // 1. Call WSAStartup()
    // 2. Check return value
    // 3. Throw std::runtime_error if fails
    //
    // WSADATA wsaData;
    // if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
    //     throw std::runtime_error("WSAStartup failed");
    // }
#endif
}

void TCPServer::remove_client(void* socket) {
    // TODO: Remove client from list and close socket
    //
    // Steps:
    // 1. Find socket in client_sockets_ vector
    // 2. Close socket
    // 3. Remove from vector
    //
    // Hint: Use std::remove() or erase-remove idiom

    close_socket(socket);
    // TODO: Remove from client_sockets_
}

void TCPServer::close_socket(void* socket) {
    // TODO: Close socket handle
    //
    // Windows: closesocket((SOCKET)(intptr_t)socket)
    // Linux:   close((int)(intptr_t)socket)

#ifdef _WIN32
    // TODO: closesocket()
#else
    // TODO: close()
#endif
}

} // namespace gateway
