#ifndef KAFKA_PRODUCER_H
#define KAFKA_PRODUCER_H

#include <librdkafka/rdkafkacpp.h>

#include <string>
#include <memory>
#include <mutex>
#include <atomic>
#include <stdexcept>

class KafkaProducer
{
public:
    KafkaProducer(const std::string &broker_url, const std::string &client_id);
    ~KafkaProducer();

    void publish(const std::string &topic, const std::string &message);
    void flush();
    bool isConnected() const;

private:
    std::string broker_url_;
    std::string client_id_;
    std::unique_ptr<RdKafka::Producer> producer_;
    std::mutex producer_mutex_;
    std::atomic<bool> connected_;
};

#endif