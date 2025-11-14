#include "tcp_server.h"
#include <stdexcept>
#include <algorithm>
#include <boost/asio.hpp>

namespace gateway
{

    TCPServer::TCPServer(int port)
        : port_(port), io_context_(), acceptor_(io_context_),
          work_guard_(boost::asio::make_work_guard(io_context_))
    {
        // Start the IO context thread
        io_thread_ = std::thread([this]()
                                 { io_context_.run(); });
    }

    TCPServer::~TCPServer()
    {
        // Stop accepting new connections
        if (acceptor_.is_open())
        {
            boost::system::error_code ec;
            acceptor_.close(ec);
        }

        // Close all client connections
        {
            std::lock_guard<std::mutex> lock(clients_mutex_);
            for (auto &client : client_sockets_)
            {
                if (client && client->is_open())
                {
                    boost::system::error_code ec;
                    client->close(ec);
                }
            }
            client_sockets_.clear();
        }

        // Stop the IO context
        work_guard_.reset();
        io_context_.stop();

        // Wait for IO thread to finish
        if (io_thread_.joinable())
        {
            io_thread_.join();
        }
    }

    void TCPServer::start()
    {
        try
        {
            // Create endpoint for listening
            boost::asio::ip::tcp::endpoint endpoint(boost::asio::ip::tcp::v4(), port_);

            // Open and bind the acceptor
            acceptor_.open(endpoint.protocol());
            acceptor_.set_option(boost::asio::ip::tcp::acceptor::reuse_address(true));
            acceptor_.bind(endpoint);
            acceptor_.listen();

            // Start accepting connections
            start_accept();
        }
        catch (const boost::system::system_error &e)
        {
            throw std::runtime_error("Failed to start TCP server on port " +
                                     std::to_string(port_) + ": " + e.what());
        }
    }

    void TCPServer::start_accept()
    {
        // Create a new socket for the next connection
        auto new_socket = std::make_shared<boost::asio::ip::tcp::socket>(io_context_);

        acceptor_.async_accept(*new_socket,
                               [this, new_socket](boost::system::error_code ec)
                               {
                                   if (!ec)
                                   {
                                       // Add client to list
                                       {
                                           std::lock_guard<std::mutex> lock(clients_mutex_);
                                           client_sockets_.push_back(new_socket);
                                       }

                                       // Continue accepting more connections
                                       start_accept();
                                   }
                                   else if (ec != boost::asio::error::operation_aborted)
                                   {
                                       // Error accepting connection, but continue
                                       start_accept();
                                   }
                               });
    }

    void TCPServer::accept_clients()
    {
        // With async accept, this is handled automatically
        // This method is kept for API compatibility
    }

    void TCPServer::broadcast(const std::string &message)
    {
        std::string message_with_newline = message;
        if (!message_with_newline.empty() && message_with_newline.back() != '\n')
        {
            message_with_newline += '\n';
        }

        // Create a shared copy of the message for async operations
        auto message_ptr = std::make_shared<std::string>(message_with_newline);

        // Copy client list to avoid holding lock during async operations
        std::vector<std::shared_ptr<boost::asio::ip::tcp::socket>> clients_copy;
        {
            std::lock_guard<std::mutex> lock(clients_mutex_);
            // Remove closed sockets first
            auto it = client_sockets_.begin();
            while (it != client_sockets_.end())
            {
                if (*it && (*it)->is_open())
                {
                    clients_copy.push_back(*it);
                    ++it;
                }
                else
                {
                    it = client_sockets_.erase(it);
                }
            }
        }

        // Post write operations to the IO context thread for thread safety
        for (auto socket : clients_copy)
        {
            boost::asio::post(io_context_, [this, socket, message_ptr]()
                              {
                boost::system::error_code ec;
                boost::asio::write(*socket, boost::asio::buffer(*message_ptr), ec);
                
                if (ec)
                {
                    // Connection error, remove client
                    std::lock_guard<std::mutex> lock(clients_mutex_);
                    socket->close(ec);
                    auto it = std::find(client_sockets_.begin(), client_sockets_.end(), socket);
                    if (it != client_sockets_.end())
                    {
                        client_sockets_.erase(it);
                    }
                } });
        }
    }

    size_t TCPServer::client_count() const
    {
        std::lock_guard<std::mutex> lock(clients_mutex_);
        return client_sockets_.size();
    }

} // namespace gateway
