#pragma once

#include "uart_reader.h"
#include "bbo_parser.h"
#include "tcp_server.h"
#include "csv_logger.h"
#include "mqtt.h"
#include "kafka_producer.h"

#include <string>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <thread>
#include <atomic>
#include <memory>
#include <chrono>

namespace gateway
{

    /**
     * Order Gateway
     * Multi-protocol publisher for FPGA BBO data
     *
     * Architecture:
     * - UART Thread: Continuously reads from FPGA UART
     * - Publish Thread: Fan-out to TCP/MQTT/Kafka
     * - Thread-safe Queue: Decouples UART reading from publishing
     */
    class OrderGateway
    {
    public:
        /**
         * Configuration structure
         */
        struct Config
        {
            std::string uart_port;
            int uart_baud = 115200;
            int tcp_port = 9999;
            std::string csv_file;

            // MQTT configuration
            std::string mqtt_broker_url;
            std::string mqtt_client_id;
            std::string mqtt_username;
            std::string mqtt_password;
            std::string mqtt_topic;

            // Kafka configuration
            std::string kafka_broker_url;
            std::string kafka_client_id;
            std::string kafka_topic;
        };

        /**
         * Constructor
         * @param config Configuration parameters
         */
        explicit OrderGateway(const Config &config);

        /**
         * Destructor - stops threads and cleans up
         */
        ~OrderGateway();

        /**
         * Start the gateway (starts threads)
         */
        void start();

        /**
         * Stop the gateway (graceful shutdown)
         */
        void stop();

        /**
         * Check if gateway is running
         */
        bool isRunning() const;

        /**
         * Wait for gateway to stop
         */
        void wait();

    private:
        // Configuration
        Config config_;

        // Components
        std::unique_ptr<UartReader> uart_;
        std::unique_ptr<TCPServer> tcp_server_;
        std::unique_ptr<MQTT> mqtt_;
        std::unique_ptr<KafkaProducer> kafka_;
        std::unique_ptr<CSVLogger> csv_logger_;

        // Thread-safe queue for BBO updates
        std::queue<BBOData> bbo_queue_;
        std::mutex queue_mutex_;
        std::condition_variable queue_cv_;
        static constexpr size_t MAX_QUEUE_SIZE = 10000; // 10k messages

        // Threading
        std::thread uart_thread_;
        std::thread publish_thread_;
        std::atomic<bool> running_;
        std::atomic<bool> stopped_;

        // Thread functions
        void uartThreadFunc();
        void publishThreadFunc();

        // Helper functions
        void publishBBO(const BBOData &bbo);
        void logBBO(const BBOData &bbo);
    };

} // namespace gateway
