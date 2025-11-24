#pragma once

#include "RingBuffer.h"
#include "Sequencer.h"
#include "BboEvent.h"

namespace disruptor {

class BboRingBuffer {
public:
    static constexpr size_t SIZE = 1024;

    BboRingBuffer() : ring_buffer_(SIZE), sequencer_(SIZE) {}

    // Producer: publish BBO
    void publish(const gateway::BBOData& bbo) {
        int64_t seq = sequencer_.next();
        ring_buffer_[seq].set(bbo);
        sequencer_.publish(seq);
    }

    // Consumer: poll for BBO
    bool poll(gateway::BBOData& bbo) {
        int64_t consumer_seq = sequencer_.get_consumer_cursor();
        int64_t next_seq = consumer_seq + 1;
        int64_t available_seq = sequencer_.get_cursor();

        if (next_seq <= available_seq) {
            bbo = ring_buffer_[next_seq].get();
            sequencer_.set_consumer_cursor(next_seq);
            return true;
        }
        return false;
    }

private:
    RingBuffer<BboEvent> ring_buffer_;
    Sequencer sequencer_;
};

}  // namespace disruptor
