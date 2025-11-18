#include "order_gateway.h"
#include <iostream>
#include <chrono>
#include <thread>

namespace gateway
{

    OrderGateway::OrderGateway(const Config &config)
        : config_(config), running_(false), stopped_(true)
    {
        // Initialize components
        try
        {
            uart_ = std::make_unique<UartReader>(config_.uart_port, config_.uart_baud);
            tcp_server_ = std::make_unique<TCPServer>(config_.tcp_port);

            // Initialize MQTT if broker URL is provided
            if (!config_.mqtt_broker_url.empty())
            {
                mqtt_ = std::make_unique<MQTT>(
                    config_.mqtt_broker_url,
                    config_.mqtt_client_id,
                    config_.mqtt_username,
                    config_.mqtt_password);
                mqtt_->connect();
            }

            // // Initialize Kafka if broker URL is provided
            // if (!config_.kafka_broker_url.empty())
            // {
            //     kafka_ = std::make_unique<KafkaProducer>(
            //         config_.kafka_broker_url,
            //         config_.kafka_client_id);
            // }

            // Initialize CSV logger if file is provided
            if (!config_.csv_file.empty())
            {
                csv_logger_ = std::make_unique<CSVLogger>(config_.csv_file);
            }

            // Start TCP server
            tcp_server_->start();
        }
        catch (const std::exception &e)
        {
            std::cerr << "Failed to initialize OrderGateway: " << e.what() << std::endl;
            throw;
        }
    }

    OrderGateway::~OrderGateway()
    {
        stop();
    }

    void OrderGateway::start()
    {
        if (running_)
        {
            return; // Already running
        }

        running_ = true;
        stopped_ = false;

        // Start UART reading thread
        uart_thread_ = std::thread(&OrderGateway::uartThreadFunc, this);

        // Start publishing thread
        publish_thread_ = std::thread(&OrderGateway::publishThreadFunc, this);

        std::cout << "Order Gateway started" << std::endl;
        std::cout << "  UART Port: " << config_.uart_port << " @ " << config_.uart_baud << " baud" << std::endl;
        std::cout << "  TCP Port: " << config_.tcp_port << std::endl;
        if (mqtt_)
        {
            std::cout << "  MQTT Broker: " << config_.mqtt_broker_url << std::endl;
            std::cout << "  MQTT Topic: " << config_.mqtt_topic << std::endl;
        }
        // if (kafka_)
        // {
        //     std::cout << "  Kafka Broker: " << config_.kafka_broker_url << std::endl;
        //     std::cout << "  Kafka Topic: " << config_.kafka_topic << std::endl;
        // }
        if (csv_logger_)
        {
            std::cout << "  CSV Log: " << config_.csv_file << std::endl;
        }
        std::cout << std::endl;
    }

    void OrderGateway::stop()
    {
        if (!running_)
        {
            return; // Already stopped
        }

        // Print performance statistics BEFORE joining threads
        if (parse_latency_.count() > 0) {
            parse_latency_.printSummary("Project 9 (UART)");
            parse_latency_.saveToFile("project9_latency.csv");
        }

        std::cout << "\nStopping Order Gateway..." << std::endl;
        running_ = false;

        // Notify threads to wake up
        queue_cv_.notify_all();

        // Wait for threads to finish
        if (uart_thread_.joinable())
        {
            uart_thread_.join();
        }

        if (publish_thread_.joinable())
        {
            publish_thread_.join();
        }

        // Cleanup connections
        if (mqtt_)
        {
            mqtt_->disconnect();
            std::cout << "MQTT disconnected" << std::endl;
        }

        // if (kafka_)
        // {
        //     kafka_->flush();
        //     std::cout << "Kafka flushed" << std::endl;
        // }
        stopped_ = true;
        std::cout << "Order Gateway stopped" << std::endl;
    }

    bool OrderGateway::isRunning() const
    {
        return running_;
    }

    void OrderGateway::wait()
    {
        while (running_)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
    }

    void OrderGateway::uartThreadFunc()
    {
        std::cout << "UART thread started" << std::endl;

        while (running_)
        {
            try
            {
                // Read line from UART (blocking)
                std::string line = uart_->read_line();

                // Measure parse latency
                {
                    gateway::LatencyMeasurement measure(parse_latency_);
                    BBOData bbo = BBOParser::parse(line);

                    if (bbo.valid)
                    {
                        // Add to queue (thread-safe)
                        {
                            std::unique_lock<std::mutex> lock(queue_mutex_);

                            if (bbo_queue_.size() >= MAX_QUEUE_SIZE)
                            {
                                std::cerr << "Warning: BBO queue full, dropping oldest message" << std::endl;
                                bbo_queue_.pop();
                            }

                            bbo_queue_.push(bbo);
                        }

                        // Notify publish thread
                        queue_cv_.notify_one();
                    }
                }
            }
            catch (const std::exception &e)
            {
                std::cerr << "UART thread error: " << e.what() << std::endl;

                // Check if UART is still open
                if (!uart_->is_open())
                {
                    std::cerr << "UART port closed, stopping gateway" << std::endl;
                    running_ = false;
                    break;
                }

                // Small delay before retrying
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
        }

        std::cout << "UART thread stopped" << std::endl;
    }

    void OrderGateway::publishThreadFunc()
    {
        std::cout << "Publish thread started" << std::endl;

        while (running_ || !bbo_queue_.empty())
        {
            BBOData bbo;
            bool has_data = false;

            // Wait for data or timeout
            {
                std::unique_lock<std::mutex> lock(queue_mutex_);

                // Wait for data or shutdown
                queue_cv_.wait_for(lock, std::chrono::milliseconds(100), [this]
                                   { return !bbo_queue_.empty() || !running_; });

                if (!bbo_queue_.empty())
                {
                    bbo = bbo_queue_.front();
                    bbo_queue_.pop();
                    has_data = true;
                }
            }

            if (has_data)
            {
                // Publish to all protocols
                publishBBO(bbo);

                // Log to CSV if enabled
                if (csv_logger_)
                {
                    logBBO(bbo);
                }

                // Print to console
                std::cout << "[" << bbo.symbol << "] Bid: " << bbo.bid_price
                          << " (" << bbo.bid_shares << ") | Ask: " << bbo.ask_price
                          << " (" << bbo.ask_shares << ") | Spread: " << bbo.spread << std::endl;
            }
        }

        std::cout << "Publish thread stopped" << std::endl;
    }

    void OrderGateway::publishBBO(const BBOData &bbo)
    {
        // Convert to JSON
        std::string json = bbo_to_json(bbo);

        // Publish to TCP (broadcast to all connected clients)
        try
        {
            tcp_server_->broadcast(json);
        }
        catch (const std::exception &e)
        {
            std::cerr << "TCP broadcast error: " << e.what() << std::endl;
        }

        // Publish to MQTT
        if (mqtt_ && mqtt_->isConnected())
        {
            try
            {
                mqtt_->publish(config_.mqtt_topic, json);
            }
            catch (const std::exception &e)
            {
                std::cerr << "MQTT publish error: " << e.what() << std::endl;
            }
        }

        // Publish to Kafka
        // if (kafka_ && kafka_->isConnected())
        // {
        //     try
        //     {
        //         kafka_->publish(config_.kafka_topic, json);
        //     }
        //     catch (const std::exception &e)
        //     {
        //         std::cerr << "Kafka publish error: " << e.what() << std::endl;
        //     }
        // }
    }

    void OrderGateway::logBBO(const BBOData &bbo)
    {
        if (csv_logger_)
        {
            try
            {
                csv_logger_->log(bbo);
            }
            catch (const std::exception &e)
            {
                std::cerr << "CSV log error: " << e.what() << std::endl;
            }
        }
    }

} // namespace gateway
