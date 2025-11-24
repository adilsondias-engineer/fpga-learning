#pragma once

#include <atomic>
#include <thread>
#include <cstdint>

namespace disruptor {

class Sequencer {
public:
    explicit Sequencer(size_t buffer_size)
        : buffer_size_(buffer_size),
          cursor_(-1),
          consumer_cursor_(-1) {}

    int64_t next() {
        int64_t current = cursor_.load(std::memory_order_relaxed);
        int64_t next_seq = current + 1;
        int64_t wrap_point = next_seq - buffer_size_;
        int64_t consumer_seq = consumer_cursor_.load(std::memory_order_acquire);
        
        while (wrap_point > consumer_seq) {
            consumer_seq = consumer_cursor_.load(std::memory_order_acquire);
            std::this_thread::yield();
        }
        
        return next_seq;
    }

    void publish(int64_t sequence) {
        cursor_.store(sequence, std::memory_order_release);
    }

    int64_t get_cursor() const {
        return cursor_.load(std::memory_order_acquire);
    }

    void set_consumer_cursor(int64_t sequence) {
        consumer_cursor_.store(sequence, std::memory_order_release);
    }

    int64_t get_consumer_cursor() const {
        return consumer_cursor_.load(std::memory_order_acquire);
    }

private:
    const size_t buffer_size_;
    alignas(64) std::atomic<int64_t> cursor_;
    alignas(64) std::atomic<int64_t> consumer_cursor_;
};

}  // namespace disruptor
