/*
eBPF/XDP Program for UDP Packet Filtering
Filters UDP packets on port 5000 and redirects to AF_XDP socket
*/

#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

// Use UAPI headers only (user-space API, safe for eBPF)
#include <linux/types.h>

// Define minimal structures (avoid pulling in kernel internals)
struct ethhdr {
    unsigned char h_dest[6];
    unsigned char h_source[6];
    __be16 h_proto;
} __attribute__((packed));

struct iphdr {
    __u8 ihl:4;
    __u8 version:4;
    __u8 tos;
    __be16 tot_len;
    __be16 id;
    __be16 frag_off;
    __u8 ttl;
    __u8 protocol;
    __sum16 check;
    __be32 saddr;
    __be32 daddr;
} __attribute__((packed));

struct udphdr {
    __be16 source;
    __be16 dest;
    __be16 len;
    __sum16 check;
} __attribute__((packed));

// Constants
#define ETH_P_IP 0x0800
#define IPPROTO_UDP 17

// Map to store XDP socket file descriptor
struct {
    __uint(type, BPF_MAP_TYPE_XSKMAP);
    __uint(max_entries, 64); //1 64
    __uint(key_size, sizeof(int));
    __uint(value_size, sizeof(int));
} xsks_map SEC(".maps");

// Map to store UDP port (configurable)
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 1);
    __type(key, int);
    __type(value, int);
} udp_port_map SEC(".maps");

SEC("xdp")
int xdp_prog(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;
    
    // Parse Ethernet header
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) {
        return XDP_PASS;  // Invalid packet
    }
    
    // Only process IPv4 packets
    if (eth->h_proto != bpf_htons(ETH_P_IP)) {
        return XDP_PASS;
    }
    
    // Parse IP header
    struct iphdr *ip = (struct iphdr *)(eth + 1);
    if ((void *)(ip + 1) > data_end) {
        return XDP_PASS;
    }
    
    // Only process UDP packets
    if (ip->protocol != IPPROTO_UDP) {
        return XDP_PASS;
    }
    
    // Parse UDP header
    struct udphdr *udp = (struct udphdr *)(ip + 1);
    if ((void *)(udp + 1) > data_end) {
        return XDP_PASS;
    }
    
    // Target UDP port (hardcoded to 5000)
    // Note: udp_port_map can be used to make this configurable if needed
    const int port = 5000;

    // Check if destination port matches
    __u16 dest_port = bpf_ntohs(udp->dest);
    
    // Debug: Log UDP packets (limited to avoid flooding)
    static __u64 packet_count = 0;
    static __u64 match_count = 0;
    static __u64 last_log_packet = 0;
    packet_count++;
    
    // Log first 10 packets and every 1000th after that
   /* if (packet_count <= 10 || packet_count - last_log_packet >= 1000) {
        bpf_printk("XDP: UDP packet #%llu, dest_port=%d, target_port=%d", packet_count, dest_port, port);
        last_log_packet = packet_count;
    }*/
    
    if (dest_port == port) {
        match_count++;

        // Debug: Log every matching packet (first 10, then every 100th)
        if (match_count <= 10 || match_count % 100 == 0) {
            bpf_printk("XDP: UDP port %d MATCHED (packet %llu, match %llu)", dest_port, packet_count, match_count);
        }

        // Redirect to AF_XDP socket
        // The queue_id parameter to bpf_redirect_map is the INDEX in the XSK map, not the RX queue
        //as per documentation, always use the rx_queue_index
        int map_index = ctx->rx_queue_index;
        bpf_printk("XDP: rx_queue_index=%d", map_index);
        // int map_index = 0;
        int *xsks_fd = bpf_map_lookup_elem(&xsks_map, &map_index);

        // Debug: Always log first few lookups to see what's happening
        if (match_count <= 10) {
            if (xsks_fd) {
                bpf_printk("XDP: XSK map lookup OK: map_index=%d, *xsks_fd=%d (value at pointer)",
                          map_index, *xsks_fd);
            } else {
                bpf_printk("XDP: XSK map lookup returned NULL (map_index=%d)", map_index);
            }
        }

        if (xsks_fd && *xsks_fd > 0) {  // FD must be > 0 (0 is stdin)
            // Debug: Log redirect attempt
            if (match_count <= 10 || match_count % 100 == 0) {
                bpf_printk("XDP: Redirecting to XSK map[%d]=%d", map_index, *xsks_fd);
            }

            // bpf_redirect_map for XSK maps redirects packets from ANY RX queue
            // to the socket bound to the specified queue (queue 0 in our case)
            // Returns XDP_REDIRECT (4) on success, or error code on failure
            // For XSK maps, success means packet will be sent to the AF_XDP socket
            long redirect_ret = bpf_redirect_map(&xsks_map, map_index, 0);
            if (match_count <= 10 || match_count % 100 == 0) {
                bpf_printk("XDP: bpf_redirect_map returned %ld (4=XDP_REDIRECT)", redirect_ret);
            }
            return redirect_ret;
        } else {
            // Debug: Log XSK map lookup failure with details
            if (match_count <= 10 || match_count % 100 == 0) {
                if (xsks_fd) {
                    bpf_printk("XDP: XSK map lookup failed: map_index=%d, *xsks_fd=%d (must be > 0)",
                              map_index, *xsks_fd);
                } else {
                    bpf_printk("XDP: XSK map lookup returned NULL (map not populated?)");
                }
            }
            // If XSK map lookup failed or redirect failed, pass to kernel
            return XDP_PASS;
        }
    }
    
    // Debug: Log non-matching UDP packets occasionally
  /*  if (packet_count % 10000 == 0) {
        bpf_printk("XDP: UDP packet port %d != %d (total packets: %llu)", dest_port, port, packet_count);
    }*/
    
    // Pass other packets to kernel stack
    return XDP_PASS;
}

char _license[] SEC("license") = "GPL";

