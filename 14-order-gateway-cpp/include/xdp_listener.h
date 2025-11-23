/*
XDP Listener (AF_XDP)
High-performance packet reception using eXpress Data Path (XDP)
Zero-copy packet reception from kernel to userspace
*/

#pragma once

#include <string>
#include <memory>
#include "bbo_parser.h"

namespace gateway {

    class PerfMonitor;  // Forward declaration

    class XDPListener {
    public:
        /**
         * Create XDP listener for high-performance packet reception
         * 
         * @param iface Network interface name (e.g., "eno2")
         * @param port UDP port to filter (e.g., 5000)
         * @param queue_id RX queue ID (default: 0)
         * @param enable_debug Enable debug logging (default: false)
         */
        explicit XDPListener(const std::string& iface, int port, int queue_id = 0, bool enable_debug = false);
        ~XDPListener();

        // Start receiving packets (non-blocking)
        void start();
        
        // Stop receiving packets
        void stop();
        
        // Read next BBO packet (blocking)
        BBOData read_bbo();
        
        // Check if listener is running
        bool isRunning() const;

        // Set performance monitor (optional)
        void setPerfMonitor(PerfMonitor* monitor) { perf_monitor_ = monitor; }

    private:
        // XDP socket file descriptor
        int xdp_socket_fd_{-1};
        
        // XSK map file descriptor (keep open for map access)
        int xsk_map_fd_{-1};
        
        // Network interface index
        int ifindex_{-1};
        
        // UDP port to filter
        int port_;
        
        // RX queue ID
        int queue_id_;
        
        // Interface name
        std::string iface_;
        
        // Running state
        bool running_{false};
        
        // Debug logging enabled
        bool enable_debug_{false};
        
        // Ring buffer sizes (must be power of 2)
        static constexpr size_t RING_SIZE = 2048;
        static constexpr size_t FRAME_SIZE = 2048;  // Frame size in bytes
        static constexpr size_t NUM_FRAMES = 4096;  // Total frames in UMEM

        // UMEM (user memory) for packet buffers
        void* umem_area_{nullptr};
        size_t umem_size_{0};

        // Memory-mapped ring structures (from kernel)
        struct xdp_ring_offset {
            uint64_t producer;
            uint64_t consumer;
            uint64_t desc;
            uint64_t flags;
        };

        // Ring pointers (memory-mapped from kernel)
        struct XDPRing {
            uint32_t* producer;
            uint32_t* consumer;
            uint32_t* flags;
            uint64_t* descriptors;  // RX/TX: 64-bit addr + 32-bit len + 32-bit options
            uint32_t mask;
            uint32_t size;

            XDPRing() : producer(nullptr), consumer(nullptr), flags(nullptr),
                       descriptors(nullptr), mask(0), size(0) {}
        };

        XDPRing rx_ring_;
        XDPRing fill_ring_;
        XDPRing completion_ring_;

        // Free frame stack for UMEM management
        uint64_t* free_frames_{nullptr};
        uint32_t free_frames_count_{0};
        uint32_t free_frames_capacity_{NUM_FRAMES};
        
        // Initialize XDP socket and load eBPF program
        void init_xdp();
        
        // Setup UMEM (user memory) for zero-copy
        void setup_umem();
        
        // Load XDP program to kernel
        void load_xdp_program();
        
        // Setup AF_XDP socket
        void setup_xdp_socket();
        
        // Poll for packets (non-blocking)
        bool poll_packet(uint8_t* buffer, size_t& len);

        // Ring buffer management
        void fill_fill_ring();
        void map_rings();
        uint64_t allocate_frame();
        void free_frame(uint64_t addr);
        void recycle_frame_to_fill_ring(uint64_t frame_addr);  // Immediately recycle frame to FILL ring (per kernel docs)

        // Ring helpers
        inline uint32_t ring_available(const XDPRing& ring, uint32_t cached_prod) {
            return *ring.producer - cached_prod;
        }

        inline uint32_t ring_free(const XDPRing& ring, uint32_t cached_cons) {
            // Calculate used slots: producer - consumer
            // For power-of-2 rings, this works correctly even with wrap-around
            // because we use unsigned arithmetic and the ring size is a power of 2
            uint32_t producer = *ring.producer;
            uint32_t used = producer - cached_cons;
            
            // If used >= ring.size, the ring is full (or indices have wrapped multiple times)
            // Cap it at ring.size
            if (used >= ring.size) {
                used = ring.size;
            }
            
            return ring.size - used;
        }

        // Performance monitoring
        PerfMonitor* perf_monitor_ = nullptr;
    };

} // namespace gateway

