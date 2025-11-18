#ifndef MQTT_H
#define MQTT_H

#include <MQTTClient.h>

#include <string>
#include <vector>
#include <map>
#include <mutex>
#include <thread>
#include <atomic>
#include <condition_variable>
#include <chrono>
#include <iostream>
#include <iomanip>
#include <sstream>
#include <fstream>
#include <chrono>
#include <ctime>
#include <stdexcept>
#include <algorithm>
#include <functional>

class MQTT
{
public:
    MQTT(const std::string &broker_url, const std::string &client_id, const std::string &username, const std::string &password);
    ~MQTT();
    void connect();
    void disconnect();
    void publish(const std::string &topic, const std::string &message);
    void subscribe(const std::string &topic);
    void unsubscribe(const std::string &topic);
    void loop();
    bool isConnected() const;

private:
    // Static callback functions for Paho MQTT C library
    static int messageArrived(void *context, char *topicName, int topicLen, MQTTClient_message *message);
    static void connectionLost(void *context, char *cause);
    static void deliveryComplete(void *context, MQTTClient_deliveryToken dt);

    std::string broker_url_;
    std::string client_id_;
    std::string username_;
    std::string password_;
    MQTTClient mqtt_client_;
    std::mutex mqtt_mutex_;
    std::atomic<bool> mqtt_connected_;
};

#endif