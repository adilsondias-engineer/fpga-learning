#pragma once

#include <string>
#include <atomic>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include "../../common/disruptor/OrderRingBuffer.h"
#include "../../common/disruptor/FillRingBuffer.h"
#include "../../common/order_data.h"

/**
 * Order Producer - Sends orders to Project 16 via Disruptor
 * Also consumes fill notifications from Project 16
 */
class OrderProducer {
public:
    OrderProducer(const std::string& order_ring_path, const std::string& fill_ring_path);
    ~OrderProducer();

    // Send order to Project 16
    void send_order(const trading::OrderRequest& order);

    // Try to read fill notification from Project 16
    bool try_read_fill(trading::FillNotification& fill);

    uint64_t get_orders_sent() const { return orders_sent_; }

private:
    std::string generate_order_id();

    int order_shm_fd_;
    int fill_shm_fd_;
    disruptor::OrderRingBuffer* order_ring_;
    disruptor::FillRingBuffer* fill_ring_;

    std::atomic<uint64_t> order_id_counter_;
    std::atomic<uint64_t> orders_sent_;
};
