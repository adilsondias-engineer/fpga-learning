#pragma once

#include "order_types.h"
#include "../../common/disruptor/BboRingBuffer.h"
#include "../../common/disruptor/SharedMemoryManager.h"
#include <memory>
#include <string>
#include <chrono>
#include <thread>

namespace gateway {

/**
 * Disruptor Client - Consumer side for Project 15
 * Reads BBO data from shared memory ring buffer created by Project 14
 */
class DisruptorClient {
public:
    explicit DisruptorClient(const std::string& shm_name = "gateway")
        : shm_name_(shm_name), ring_buffer_(nullptr) {}

    ~DisruptorClient() {
        disconnect();
    }

    // Connect to shared memory (open existing)
    void connect() {
        if (ring_buffer_) {
            return;  // Already connected
        }

        try {
            ring_buffer_ = disruptor::SharedMemoryManager<
                disruptor::BboRingBuffer>::open(shm_name_);
        } catch (const std::exception& e) {
            throw std::runtime_error("Failed to connect to Disruptor shared memory: " +
                                   std::string(e.what()));
        }
    }

    // Disconnect from shared memory
    void disconnect() {
        if (ring_buffer_) {
            disruptor::SharedMemoryManager<disruptor::BboRingBuffer>::disconnect(ring_buffer_);
            ring_buffer_ = nullptr;
        }
    }

    // Check if connected
    bool isConnected() const {
        return ring_buffer_ != nullptr;
    }

    // Read BBO (blocking with timeout)
    BBOData read_bbo(int timeout_us = 1000) {
        if (!isConnected()) {
            throw std::runtime_error("Disruptor client not connected");
        }

        BBOData bbo;
        auto start = std::chrono::steady_clock::now();

        while (true) {
            if (ring_buffer_->poll(bbo)) {
                return bbo;
            }

            // Check timeout
            auto elapsed = std::chrono::steady_clock::now() - start;
            if (elapsed > std::chrono::microseconds(timeout_us)) {
                throw std::runtime_error("Disruptor read timeout");
            }

            // Yield CPU (low-latency busy-wait)
            std::this_thread::yield();
        }
    }

    // Try to read BBO (non-blocking)
    bool try_read_bbo(BBOData& bbo) {
        if (!isConnected()) {
            return false;
        }
        return ring_buffer_->poll(bbo);
    }

private:
    std::string shm_name_;
    disruptor::BboRingBuffer* ring_buffer_;
};

}  // namespace gateway
