#pragma once

#include <vector>
#include <stdexcept>
#include <cstdint>

namespace disruptor {

template<typename T>
class RingBuffer {
public:
    explicit RingBuffer(size_t size) : buffer_size_(size), buffer_mask_(size - 1) {
        if (size == 0 || (size & (size - 1)) != 0) {
            throw std::invalid_argument("Ring buffer size must be power of 2");
        }
        buffer_.resize(size);
    }

    T& operator[](int64_t sequence) {
        return buffer_[sequence & buffer_mask_];
    }

    const T& operator[](int64_t sequence) const {
        return buffer_[sequence & buffer_mask_];
    }

    size_t size() const { return buffer_size_; }

private:
    const size_t buffer_size_;
    const size_t buffer_mask_;
    std::vector<T> buffer_;
};

}  // namespace disruptor
