#include "order_gateway.h"

#include <iostream>
#include <stdexcept>
#include <csignal>
#include <memory>

// Default configuration
#define DEFAULT_MQTT_BROKER_URL "mqtt://192.168.0.2:1883"
#define DEFAULT_MQTT_CLIENT_ID "order_gateway"
#define DEFAULT_MQTT_USERNAME "trading"
#define DEFAULT_MQTT_PASSWORD "trading123"
#define DEFAULT_MQTT_TOPIC "bbo_messages"

#define DEFAULT_KAFKA_BROKER_URL "192.168.0.203:9092"
#define DEFAULT_KAFKA_CLIENT_ID "order_gateway"
#define DEFAULT_KAFKA_TOPIC "bbo_messages"

using namespace gateway;

// Global gateway instance for signal handler
std::unique_ptr<OrderGateway> g_gateway;

void signal_handler(int signal)
{
    std::cout << "\nShutdown signal received (" << signal << ")" << std::endl;
    if (g_gateway)
    {
        g_gateway->stop();
    }
}

void print_usage(const char *program_name)
{
    std::cout << "Usage: " << program_name << " <uart_port> [options]" << std::endl;
    std::cout << std::endl;
    std::cout << "Arguments:" << std::endl;
    std::cout << "  uart_port     - Serial port name (e.g., COM3 or /dev/ttyUSB0)" << std::endl;
    std::cout << std::endl;
    std::cout << "Options:" << std::endl;
    std::cout << "  --tcp-port PORT     - TCP port for JSON output (default: 9999)" << std::endl;
    std::cout << "  --csv-file FILE     - CSV log file (optional)" << std::endl;
    std::cout << "  --mqtt-broker URL   - MQTT broker URL (default: " << DEFAULT_MQTT_BROKER_URL << ")" << std::endl;
    std::cout << "  --mqtt-topic TOPIC  - MQTT topic (default: " << DEFAULT_MQTT_TOPIC << ")" << std::endl;
    std::cout << "  --kafka-broker URL  - Kafka broker URL (default: " << DEFAULT_KAFKA_BROKER_URL << ")" << std::endl;
    std::cout << "  --kafka-topic TOPIC - Kafka topic (default: " << DEFAULT_KAFKA_TOPIC << ")" << std::endl;
    std::cout << std::endl;
    std::cout << "Examples:" << std::endl;
    std::cout << "  " << program_name << " COM3" << std::endl;
    std::cout << "  " << program_name << " /dev/ttyUSB0 --tcp-port 9999" << std::endl;
    std::cout << "  " << program_name << " COM3 --csv-file bbo_log.csv" << std::endl;
    std::cout << "  " << program_name << " COM3 --mqtt-broker mqtt://localhost:1883" << std::endl;
}

int main(int argc, char **argv)
{
    // Parse command-line arguments
    if (argc < 2)
    {
        print_usage(argv[0]);
        return 1;
    }

    // Parse arguments (simple parser - can be enhanced)
    std::string uart_port = argv[1];
    int tcp_port = 9999;
    std::string csv_file;
    std::string mqtt_broker = DEFAULT_MQTT_BROKER_URL;
    std::string mqtt_topic = DEFAULT_MQTT_TOPIC;
    std::string kafka_broker = DEFAULT_KAFKA_BROKER_URL;
    std::string kafka_topic = DEFAULT_KAFKA_TOPIC;

    // Simple argument parsing
    for (int i = 2; i < argc; i++)
    {
        std::string arg = argv[i];
        if (arg == "--tcp-port" && i + 1 < argc)
        {
            tcp_port = std::stoi(argv[++i]);
        }
        else if (arg == "--csv-file" && i + 1 < argc)
        {
            csv_file = argv[++i];
        }
        else if (arg == "--mqtt-broker" && i + 1 < argc)
        {
            mqtt_broker = argv[++i];
        }
        else if (arg == "--mqtt-topic" && i + 1 < argc)
        {
            mqtt_topic = argv[++i];
        }
        else if (arg == "--kafka-broker" && i + 1 < argc)
        {
            kafka_broker = argv[++i];
        }
        else if (arg == "--kafka-topic" && i + 1 < argc)
        {
            kafka_topic = argv[++i];
        }
    }

    // Install signal handler for graceful shutdown
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    try
    {
        // Create gateway configuration
        OrderGateway::Config config;
        config.uart_port = uart_port;
        config.uart_baud = 115200;
        config.tcp_port = tcp_port;
        config.csv_file = csv_file;
        config.mqtt_broker_url = mqtt_broker;
        config.mqtt_client_id = DEFAULT_MQTT_CLIENT_ID;
        config.mqtt_username = DEFAULT_MQTT_USERNAME;
        config.mqtt_password = DEFAULT_MQTT_PASSWORD;
        config.mqtt_topic = mqtt_topic;
        config.kafka_broker_url = kafka_broker;
        config.kafka_client_id = DEFAULT_KAFKA_CLIENT_ID;
        config.kafka_topic = kafka_topic;

        // Create and start gateway
        g_gateway = std::make_unique<OrderGateway>(config);
        g_gateway->start();

        std::cout << "Gateway running. Press Ctrl+C to stop." << std::endl;
        std::cout << std::endl;

        // Wait for gateway to stop
        g_gateway->wait();

        std::cout << std::endl;
        std::cout << "Gateway stopped." << std::endl;
    }
    catch (const std::exception &e)
    {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
