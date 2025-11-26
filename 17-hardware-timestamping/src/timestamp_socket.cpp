#include "timestamp_socket.h"
#include <stdexcept>
#include <cstring>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <sys/ioctl.h>
#include <linux/sockios.h>
#include <linux/errqueue.h>

namespace timestamp {

TimestampSocket::TimestampSocket(uint16_t port, const char* interface)
    : socket_fd_(-1)
    , timestamping_enabled_(false)
    , port_(port)
{
    // Create UDP socket
    socket_fd_ = socket(AF_INET, SOCK_DGRAM, 0);
    if (socket_fd_ < 0) {
        throw std::runtime_error("Failed to create socket: " + std::string(strerror(errno)));
    }

    // Set SO_REUSEADDR
    int reuse = 1;
    if (setsockopt(socket_fd_, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
        close(socket_fd_);
        throw std::runtime_error("Failed to set SO_REUSEADDR: " + std::string(strerror(errno)));
    }

    // Bind to interface if specified
    if (interface != nullptr) {
        if (setsockopt(socket_fd_, SOL_SOCKET, SO_BINDTODEVICE, interface, strlen(interface)) < 0) {
            close(socket_fd_);
            throw std::runtime_error("Failed to bind to interface " + std::string(interface) +
                                     ": " + std::string(strerror(errno)));
        }
    }

    // Bind to port
    sockaddr_in addr = {};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port_);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(socket_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(socket_fd_);
        throw std::runtime_error("Failed to bind to port " + std::to_string(port_) +
                                 ": " + std::string(strerror(errno)));
    }

    // Enable timestamping
    enable_timestamping();
}

TimestampSocket::~TimestampSocket() {
    if (socket_fd_ >= 0) {
        close(socket_fd_);
    }
}

void TimestampSocket::enable_timestamping() {
    // Enable software RX timestamps (kernel-level)
    // SOF_TIMESTAMPING_RX_SOFTWARE: Capture RX timestamp at kernel level
    // SOF_TIMESTAMPING_SOFTWARE: Enable software timestamping
    // SOF_TIMESTAMPING_OPT_CMSG: Return timestamp as ancillary data
    int flags = SOF_TIMESTAMPING_RX_SOFTWARE |
                SOF_TIMESTAMPING_SOFTWARE |
                SOF_TIMESTAMPING_OPT_CMSG;

    if (setsockopt(socket_fd_, SOL_SOCKET, SO_TIMESTAMPING, &flags, sizeof(flags)) < 0) {
        // Timestamping not supported - continue without it
        timestamping_enabled_ = false;
        return;
    }

    timestamping_enabled_ = true;
}

TimestampedPacket TimestampSocket::receive_with_timestamp() {
    TimestampedPacket packet = {};

    // Setup iovec for data reception
    struct iovec iov = {};
    iov.iov_base = packet.data;
    iov.iov_len = sizeof(packet.data);

    // Setup control buffer for ancillary data (timestamps)
    char control[256];
    struct msghdr msg = {};
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = control;
    msg.msg_controllen = sizeof(control);
    msg.msg_name = &packet.src_addr;
    msg.msg_namelen = sizeof(packet.src_addr);

    // Capture application RX timestamp BEFORE recvmsg
    // (This minimizes delay between kernel RX and app RX)
    packet.app_rx_timestamp = get_current_time();

    // Receive message with ancillary data
    ssize_t len = recvmsg(socket_fd_, &msg, 0);
    if (len < 0) {
        throw std::runtime_error("recvmsg failed: " + std::string(strerror(errno)));
    }

    packet.data_len = len;

    // Extract kernel timestamp from ancillary data
    if (timestamping_enabled_) {
        if (!extract_kernel_timestamp(&msg, &packet.kernel_rx_timestamp)) {
            // If kernel timestamp not available, use app timestamp as fallback
            packet.kernel_rx_timestamp = packet.app_rx_timestamp;
        }
    } else {
        // No timestamping support - use app timestamp
        packet.kernel_rx_timestamp = packet.app_rx_timestamp;
    }

    // Compute latency (kernel RX -> app RX)
    packet.kernel_to_app_ns = time_diff_ns(packet.kernel_rx_timestamp, packet.app_rx_timestamp);

    return packet;
}

bool TimestampSocket::extract_kernel_timestamp(struct msghdr* msg, timespec* ts) {
    for (struct cmsghdr* cmsg = CMSG_FIRSTHDR(msg); cmsg != nullptr; cmsg = CMSG_NXTHDR(msg, cmsg)) {
        if (cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_TIMESTAMPING) {
            // SCM_TIMESTAMPING contains 3 timestamps:
            // [0] = software timestamp (what we want for kernel-level)
            // [1] = deprecated
            // [2] = hardware timestamp (if available)
            struct scm_timestamping* tss = (struct scm_timestamping*)CMSG_DATA(cmsg);

            // Use software timestamp (index 0)
            *ts = tss->ts[0];
            return true;
        }
    }
    return false;
}

timespec TimestampSocket::get_current_time() {
    timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return ts;
}

uint64_t TimestampSocket::time_diff_ns(const timespec& start, const timespec& end) {
    int64_t sec_diff = end.tv_sec - start.tv_sec;
    int64_t nsec_diff = end.tv_nsec - start.tv_nsec;

    return sec_diff * 1000000000LL + nsec_diff;
}

} // namespace timestamp
