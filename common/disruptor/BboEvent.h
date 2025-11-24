#pragma once

#include "../bbo_data.h"
#include <cstdint>

namespace disruptor {

constexpr size_t CACHE_LINE_SIZE = 64;

// BBOData is ~88 bytes, use 128 bytes (2 cache lines) for alignment
struct alignas(CACHE_LINE_SIZE) BboEvent {
    gateway::BBOData bbo;
    char padding[128 - sizeof(gateway::BBOData)];

    BboEvent() = default;

    void set(const gateway::BBOData& data) {
        bbo = data;
    }

    const gateway::BBOData& get() const {
        return bbo;
    }
};

static_assert(sizeof(BboEvent) == 128, "BboEvent must be 128 bytes");

}  // namespace disruptor
