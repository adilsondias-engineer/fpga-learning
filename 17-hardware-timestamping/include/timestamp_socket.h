#pragma once

#include <cstdint>
#include <string>
#include <chrono>
#include <sys/socket.h>
#include <netinet/in.h>
#include <linux/net_tstamp.h>

namespace timestamp {

/**
 * Timestamped packet structure
 * Contains both kernel and application timestamps for latency measurement
 */
struct TimestampedPacket {
    // Kernel RX timestamp (captured at network stack)
    timespec kernel_rx_timestamp;

    // Application RX timestamp (captured at userspace)
    timespec app_rx_timestamp;

    // Packet data
    uint8_t data[2048];
    size_t data_len;

    // Source address
    sockaddr_in src_addr;

    // Computed latencies (nanoseconds)
    uint64_t kernel_to_app_ns;   // Time from kernel RX to app RX

    // Helper: Get kernel timestamp as nanoseconds since epoch
    uint64_t get_kernel_timestamp_ns() const {
        return static_cast<uint64_t>(kernel_rx_timestamp.tv_sec) * 1000000000ULL +
               kernel_rx_timestamp.tv_nsec;
    }

    // Helper: Get app timestamp as nanoseconds since epoch
    uint64_t get_app_timestamp_ns() const {
        return static_cast<uint64_t>(app_rx_timestamp.tv_sec) * 1000000000ULL +
               app_rx_timestamp.tv_nsec;
    }
};

/**
 * UDP socket with SO_TIMESTAMPING support
 * Captures kernel-level timestamps for accurate latency measurement
 */
class TimestampSocket {
public:
    /**
     * Create timestamping socket
     * @param port UDP port to bind to
     * @param interface Network interface name (e.g., "eth0", nullptr for any)
     */
    explicit TimestampSocket(uint16_t port, const char* interface = nullptr);

    ~TimestampSocket();

    // No copy
    TimestampSocket(const TimestampSocket&) = delete;
    TimestampSocket& operator=(const TimestampSocket&) = delete;

    /**
     * Receive packet with kernel timestamp
     * @return Timestamped packet with kernel and app timestamps
     */
    TimestampedPacket receive_with_timestamp();

    /**
     * Get socket file descriptor
     */
    int get_fd() const { return socket_fd_; }

    /**
     * Check if timestamping is enabled
     */
    bool is_timestamping_enabled() const { return timestamping_enabled_; }

private:
    int socket_fd_;
    bool timestamping_enabled_;
    uint16_t port_;

    // Enable SO_TIMESTAMPING socket option
    void enable_timestamping();

    // Extract kernel timestamp from ancillary data
    bool extract_kernel_timestamp(struct msghdr* msg, timespec* ts);

    // Get current time as timespec
    static timespec get_current_time();

    // Compute time difference in nanoseconds
    static uint64_t time_diff_ns(const timespec& start, const timespec& end);
};

} // namespace timestamp
