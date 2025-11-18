#include "order_gateway.h"
#include "common/rt_config.h"
#include <iostream>
#include <chrono>
#include <thread>
#include <iomanip>
#include <cmath>

namespace gateway
{

    OrderGateway::OrderGateway(const Config &config)
        : config_(config), running_(false), stopped_(true)
    {
        // Initialize components
        try
        {
            udp_listener_ = std::make_unique<UDPListener>(config_.udp_ip, config_.udp_port);
            tcp_server_ = std::make_unique<TCPServer>(config_.tcp_port);

            // Initialize MQTT if broker URL is provided
            if (!config_.disable_mqtt && !config_.mqtt_broker_url.empty())
            {
                mqtt_ = std::make_unique<MQTT>(
                    config_.mqtt_broker_url,
                    config_.mqtt_client_id,
                    config_.mqtt_username,
                    config_.mqtt_password);
                mqtt_->connect();
            }

            // Initialize Kafka if broker URL is provided
            if (!config_.disable_kafka && !config_.kafka_broker_url.empty())
            {
                kafka_ = std::make_unique<KafkaProducer>(
                    config_.kafka_broker_url,
                    config_.kafka_client_id);
            }

            // Initialize CSV logger if file is provided
            if (!config_.disable_logger && !config_.csv_file.empty())
            {
                csv_logger_ = std::make_unique<CSVLogger>(config_.csv_file);
            }

            // Start TCP server
            if (!config_.disable_tcp)
            {
                tcp_server_->start();
            }
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

        // Verify RT capabilities if enabled
        if (config_.enable_rt)
        {
            std::cout << "[RT] Real-time optimizations enabled" << std::endl;
            if (!RTConfig::verifyRTCapabilities())
            {
                std::cerr << "[RT] Warning: RT capabilities verification failed" << std::endl;
            }
        }

        // Start UDP listener and reading thread
        if (udp_listener_ && !udp_listener_->isRunning())
        {
            udp_listener_->setPerfMonitor(&parse_latency_);
            udp_listener_->start();
        }
        udp_thread_ = std::thread(&OrderGateway::udpThreadFunc, this);

        // Start publishing thread
        publish_thread_ = std::thread(&OrderGateway::publishThreadFunc, this);

        // Apply RT optimizations if enabled
        if (config_.enable_rt)
        {
            std::cout << "[RT] Applying real-time optimizations..." << std::endl;

            // UDP thread: highest priority, pinned to core 2
            if (!RTConfig::applyRTOptimization(
                    udp_thread_.native_handle(),
                    ThreadConfig::UDP_LISTENER_PRIORITY,
                    ThreadConfig::UDP_LISTENER_CPU))
            {
                std::cerr << "[RT] Warning: Failed to optimize UDP thread" << std::endl;
            }

            // Publish thread: high priority, pinned to core 3
            if (!RTConfig::applyRTOptimization(
                    publish_thread_.native_handle(),
                    ThreadConfig::TCP_SERVER_PRIORITY,
                    ThreadConfig::TCP_SERVER_CPU))
            {
                std::cerr << "[RT] Warning: Failed to optimize publish thread" << std::endl;
            }

            std::cout << "[RT] Real-time optimizations applied" << std::endl;
        }

        std::cout << "Order Gateway started" << std::endl;
        std::cout << "  UDP IP: " << config_.udp_ip << " @ " << config_.udp_port << " port" << std::endl;
        std::cout << "  TCP Port: " << config_.tcp_port << std::endl;
        if (mqtt_)
        {
            std::cout << "  MQTT Broker: " << config_.mqtt_broker_url << std::endl;
            std::cout << "  MQTT Topic: " << config_.mqtt_topic << std::endl;
        }
        if (kafka_)
        {
            std::cout << "  Kafka Broker: " << config_.kafka_broker_url << std::endl;
            std::cout << "  Kafka Topic: " << config_.kafka_topic << std::endl;
        }
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
            parse_latency_.printSummary("Project 14 (UDP)");
            parse_latency_.saveToFile("project14_latency.csv");
        }

        std::cout << "\nStopping Order Gateway..." << std::endl;
        running_ = false;

        // Notify threads to wake up
        queue_cv_.notify_all();
        if (udp_listener_)
        {
            udp_listener_->stop();
        }

        // Wait for threads to finish
        if (udp_thread_.joinable())
        {
            udp_thread_.join();
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

        if (kafka_)
        {
            kafka_->flush();
            std::cout << "Kafka flushed" << std::endl;
        }

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

    void OrderGateway::udpThreadFunc()
    {
        std::cout << "UDP thread started" << std::endl;

        while (running_)
        {
            try
            {
                // Read BBO from UDP listener (blocking)
                BBOData bbo = udp_listener_->read_bbo();
                
                // Push to internal queue for publish thread to handle printing and fan-out
                {
                    std::unique_lock<std::mutex> qlock(queue_mutex_);
                    if (bbo_queue_.size() < MAX_QUEUE_SIZE)
                    {
                        bbo_queue_.push(bbo);
                        queue_cv_.notify_one();
                    }
                }
            }
            catch (const std::exception &e)
            {
                std::cerr << "UDP thread error: " << e.what() << std::endl;

                // Check if UDP listener is still running
                if (!udp_listener_->isRunning())
                {
                    std::cerr << "UDP listener stopped, stopping gateway" << std::endl;
                    running_ = false;
                    break;
                }

                // Small delay before retrying
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
            }
        }

        std::cout << "UDP thread stopped" << std::endl;
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
                // Suppress duplicate prints for the same symbol unless values changed
                auto changed = [](const BBOData& prev, const BBOData& curr) {
                    auto diff = [](double a, double b) { return std::fabs(a - b) > 0.00005; };
                    return diff(prev.bid_price, curr.bid_price) ||
                           diff(prev.ask_price, curr.ask_price) ||
                           diff(prev.spread,    curr.spread)    ||
                           prev.bid_shares != curr.bid_shares   ||
                           prev.ask_shares != curr.ask_shares;
                };
                bool should_print = true;
                auto it = last_printed_bbo_by_symbol_.find(bbo.symbol);
                if (it != last_printed_bbo_by_symbol_.end() && !changed(it->second, bbo))
                {
                    should_print = false;
                }
                last_printed_bbo_by_symbol_[bbo.symbol] = bbo;
                // Publish to all protocols
                publishBBO(bbo);

                // Log to CSV if enabled
                if (csv_logger_)
                {
                    logBBO(bbo);
                }

                if (should_print)
                {
                    // Print to console (format prices to 4 decimals)
                    std::cout << "[" << bbo.symbol << "] "
                              << "Bid: " << std::fixed << std::setprecision(4) << bbo.bid_price
                              << " (" << bbo.bid_shares << ") | ";
                    if (bbo.ask_price > 0.0 && bbo.ask_shares > 0)
                    {
                        std::cout << "Ask: " << std::fixed << std::setprecision(4) << bbo.ask_price
                                  << " (" << bbo.ask_shares << ") | ";
                    }
                    else
                    {
                        std::cout << "Ask: -" << " (-) | ";
                    }
                    std::cout << "Spread: " << std::fixed << std::setprecision(4) << bbo.spread
                              << std::endl;
                }
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
            if (!config_.disable_tcp)
            {
                tcp_server_->broadcast(json);
            }
            else
            {
                std::cout << "TCP disabled, skipping broadcast" << std::endl;
            }
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
        if (kafka_ && kafka_->isConnected())
        {
            try
            {
                kafka_->publish(config_.kafka_topic, json);
            }
            catch (const std::exception &e)
            {
                std::cerr << "Kafka publish error: " << e.what() << std::endl;
            }
        }
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
