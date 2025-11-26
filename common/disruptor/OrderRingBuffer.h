#pragma once

#include "RingBuffer.h"
#include "Sequencer.h"
#include "../order_data.h"

namespace disruptor {

/**
 * Order Event wrapper for Disruptor ring buffer
 * Wraps OrderRequest in cache-line aligned structure
 */
class OrderEvent {
public:
    alignas(64) trading::OrderRequest order;

    OrderEvent() = default;

    void set(const trading::OrderRequest& o) {
        order = o;
    }

    trading::OrderRequest get() const {
        return order;
    }
};

/**
 * Order Ring Buffer for Project 15 → Project 16 IPC
 * Shared memory: /dev/shm/order_ring_mm
 */
class OrderRingBuffer {
public:
    static constexpr size_t SIZE = 8192;   // Increased from 1024 for better order throughput

    OrderRingBuffer() : sequencer_(SIZE) {}

    // Producer (Project 15): publish order
    void publish(const trading::OrderRequest& order) {
        int64_t seq = sequencer_.next();
        ring_buffer_[seq].set(order);
        sequencer_.publish(seq);
    }

    // Consumer (Project 16): try read order
    bool try_read(trading::OrderRequest& order) {
        int64_t consumer_cursor = sequencer_.get_consumer_cursor();
        int64_t next_seq = consumer_cursor + 1;

        if (sequencer_.is_available(next_seq)) {
            order = ring_buffer_[next_seq].get();
            sequencer_.set_consumer_cursor(next_seq);
            return true;
        }
        return false;
    }

private:
    RingBuffer<OrderEvent, SIZE> ring_buffer_;
    Sequencer sequencer_;
};

}  // namespace disruptor
