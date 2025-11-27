#include "../include/order_producer.h"
#include <spdlog/spdlog.h>
#include <sstream>
#include <iomanip>
#include <stdexcept>

OrderProducer::OrderProducer(const std::string& order_ring_path, const std::string& fill_ring_path)
    : order_shm_fd_(-1)
    , fill_shm_fd_(-1)
    , order_ring_(nullptr)
    , fill_ring_(nullptr)
    , order_id_counter_(1)
    , orders_sent_(0) {

    // Create shared memory for orders (producer)
    order_shm_fd_ = shm_open(order_ring_path.c_str(), O_CREAT | O_RDWR, 0666);
    if (order_shm_fd_ == -1) {
        throw std::runtime_error("Failed to create order shared memory: " + order_ring_path);
    }

    ftruncate(order_shm_fd_, sizeof(disruptor::OrderRingBuffer));

    void* order_addr = mmap(nullptr, sizeof(disruptor::OrderRingBuffer),
                           PROT_READ | PROT_WRITE, MAP_SHARED, order_shm_fd_, 0);
    if (order_addr == MAP_FAILED) {
        close(order_shm_fd_);
        throw std::runtime_error("Failed to mmap order shared memory");
    }

    // Placement new to initialize the ring buffer
    order_ring_ = new (order_addr) disruptor::OrderRingBuffer();

    // Open shared memory for fills (consumer)
    fill_shm_fd_ = shm_open(fill_ring_path.c_str(), O_RDWR, 0666);
    if (fill_shm_fd_ == -1) {
        spdlog::warn("Fill shared memory not available yet: {}", fill_ring_path);
        fill_ring_ = nullptr;
    } else {
        void* fill_addr = mmap(nullptr, sizeof(disruptor::FillRingBuffer),
                              PROT_READ | PROT_WRITE, MAP_SHARED, fill_shm_fd_, 0);
        if (fill_addr == MAP_FAILED) {
            spdlog::error("Failed to mmap fill shared memory");
            close(fill_shm_fd_);
            fill_shm_fd_ = -1;
            fill_ring_ = nullptr;
        } else {
            fill_ring_ = static_cast<disruptor::FillRingBuffer*>(fill_addr);
            spdlog::info("Connected to fill ring buffer");
        }
    }

    spdlog::info("Order Producer initialized (orders: {})", order_ring_path);
}

OrderProducer::~OrderProducer() {
    if (order_ring_) {
        munmap(order_ring_, sizeof(disruptor::OrderRingBuffer));
    }
    if (fill_ring_) {
        munmap(fill_ring_, sizeof(disruptor::FillRingBuffer));
    }
    if (order_shm_fd_ != -1) close(order_shm_fd_);
    if (fill_shm_fd_ != -1) close(fill_shm_fd_);
}

void OrderProducer::send_order(const trading::OrderRequest& order) {
    if (!order_ring_) {
        spdlog::error("Order ring buffer not initialized");
        return;
    }

    order_ring_->publish(order);
    orders_sent_++;

    spdlog::info("Sent order: {} {} {} @{}",
                order.get_order_id(), order.get_symbol(),
                order.quantity, order.price);
}

bool OrderProducer::try_read_fill(trading::FillNotification& fill) {
    if (!fill_ring_) {
        return false;
    }

    return fill_ring_->try_read(fill);
}

std::string OrderProducer::generate_order_id() {
    uint64_t id = order_id_counter_++;
    std::ostringstream oss;
    oss << "MM" << std::setfill('0') << std::setw(10) << id;
    return oss.str();
}
