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
    std::cout << "Usage: " << program_name << " <udp-ip> <udp-port> [options]" << std::endl;
    std::cout << std::endl;
    std::cout << "Arguments:" << std::endl;
    std::cout << "  udp-ip IP  - UDP IP address (default: 0.0.0.0)" << std::endl;
    std::cout << "  udp-port PORT - UDP port name (e.g., 5000)" << std::endl;
    std::cout << std::endl;
    std::cout << "Options:" << std::endl;
    std::cout << "  --tcp-port PORT     - TCP port for JSON output (default: 9999)" << std::endl;
    std::cout << "  --csv-file FILE     - CSV log file (optional)" << std::endl;
    std::cout << "  --mqtt-broker URL   - MQTT broker URL (default: " << DEFAULT_MQTT_BROKER_URL << ")" << std::endl;
    std::cout << "  --mqtt-topic TOPIC  - MQTT topic (default: " << DEFAULT_MQTT_TOPIC << ")" << std::endl;
    std::cout << "  --kafka-broker URL  - Kafka broker URL (default: " << DEFAULT_KAFKA_BROKER_URL << ")" << std::endl;
    std::cout << "  --kafka-topic TOPIC - Kafka topic (default: " << DEFAULT_KAFKA_TOPIC << ")" << std::endl;
    std::cout << "  --disable-kafka     - Disable Kafka (default: false)" << std::endl;
    std::cout << "  --disable-mqtt     - Disable MQTT (default: false)" << std::endl;
    std::cout << "  --disable-tcp      - Disable TCP (default: false)" << std::endl;
    std::cout << "  --disable-logger   - Disable logger (default: false)" << std::endl;
    std::cout << std::endl;
    std::cout << "Examples:" << std::endl;
    std::cout << "  " << program_name << " 0.0.0.0 5000" << std::endl;
    std::cout << "  " << program_name << " 0.0.0.0 5000 --tcp-port 9999" << std::endl;
    std::cout << "  " << program_name << " 0.0.0.0 5000 --csv-file bbo_log.csv" << std::endl;
    std::cout << "  " << program_name << " 0.0.0.0 5000 --mqtt-broker mqtt://localhost:1883" << std::endl;
    std::cout << "  " << program_name << " 0.0.0.0 5000 --kafka-broker localhost:9092" << std::endl;
    std::cout << "  " << program_name << " 0.0.0.0 5000 --disable-kafka" << std::endl;
    std::cout << "  " << program_name << " 0.0.0.0 5000 --disable-mqtt" << std::endl;
    std::cout << "  " << program_name << " 0.0.0.0 5000 --disable-tcp" << std::endl;
    std::cout << "  " << program_name << " 0.0.0.0 5000 --disable-logger" << std::endl;
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
    std::string udp_ip = argv[1];
    int udp_port = 5000;
    int tcp_port = 9999;
    bool disable_kafka = false;
    bool disable_mqtt = false;
    bool disable_tcp = false;
    bool disable_logger = false;
    std::string csv_file;
    std::string mqtt_broker;
    std::string mqtt_topic;
    std::string kafka_broker;
    std::string kafka_topic;
    // Optional positional UDP port as second argument
    if (argc >= 3 && argv[2][0] != '-')
    {
        try { udp_port = std::stoi(argv[2]); } catch (...) {}
    }

    // Simple argument parsing
    for (int i = 2; i < argc; i++)
    { 
        std::string arg = argv[i];
        if (arg == "--udp-ip" && i + 1 < argc)
        {
            udp_ip = argv[++i];
        }
        else if (arg == "--udp-port" && i + 1 < argc)
        {
            udp_port = std::stoi(argv[++i]);
        }
        else if (arg == "--tcp-port" && i + 1 < argc)
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
        else if (arg == "--disable-kafka")
        {
            disable_kafka = true;
        }
        else if (arg == "--disable-mqtt")
        {
            disable_mqtt = true;
        }
        else if (arg == "--disable-tcp")  
        {
            disable_tcp = true;
        }
        else if (arg == "--disable-logger")
        {
            disable_logger = true;
        }
    }

    // Install signal handler for graceful shutdown
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    try
    {
        // Create gateway configuration
        OrderGateway::Config config;
        config.udp_ip = udp_ip;
        config.udp_port = udp_port;
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
        config.disable_kafka = disable_kafka;
        config.disable_mqtt = disable_mqtt;
        config.disable_tcp = disable_tcp;
        config.disable_logger = disable_logger;
        
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
