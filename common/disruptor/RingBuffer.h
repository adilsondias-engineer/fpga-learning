#pragma once

#include <stdexcept>
#include <cstdint>
#include <array>

namespace disruptor {

template<typename T, size_t N>
class RingBuffer {
public:
    static_assert((N & (N - 1)) == 0, "Ring buffer size must be power of 2");

    RingBuffer() : buffer_size_(N), buffer_mask_(N - 1) {
        // Initialize array elements
        for (size_t i = 0; i < N; ++i) {
            new (&buffer_[i]) T();
        }
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
    T buffer_[N];  // Fixed-size array for shared memory compatibility
};

}  // namespace disruptor
