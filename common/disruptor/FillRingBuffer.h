#pragma once

#include "RingBuffer.h"
#include "Sequencer.h"
#include "../order_data.h"

namespace disruptor {

/**
 * Fill Event wrapper for Disruptor ring buffer
 * Wraps FillNotification in cache-line aligned structure
 */
class FillEvent {
public:
    alignas(64) trading::FillNotification fill;

    FillEvent() = default;

    void set(const trading::FillNotification& f) {
        fill = f;
    }

    trading::FillNotification get() const {
        return fill;
    }
};

/**
 * Fill Ring Buffer for Project 16 → Project 15 IPC
 * Shared memory: /dev/shm/fill_ring_oe
 */
class FillRingBuffer {
public:
    static constexpr size_t SIZE = 8192;   // Increased from 1024 for better fill throughput

    FillRingBuffer() : sequencer_(SIZE) {}

    // Producer (Project 16): publish fill
    void publish(const trading::FillNotification& fill) {
        int64_t seq = sequencer_.next();
        ring_buffer_[seq].set(fill);
        sequencer_.publish(seq);
    }

    // Consumer (Project 15): try read fill
    bool try_read(trading::FillNotification& fill) {
        int64_t consumer_cursor = sequencer_.get_consumer_cursor();
        int64_t next_seq = consumer_cursor + 1;

        if (sequencer_.is_available(next_seq)) {
            fill = ring_buffer_[next_seq].get();
            sequencer_.set_consumer_cursor(next_seq);
            return true;
        }
        return false;
    }

private:
    RingBuffer<FillEvent, SIZE> ring_buffer_;
    Sequencer sequencer_;
};

}  // namespace disruptor
