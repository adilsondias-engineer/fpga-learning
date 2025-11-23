/*
 * Cleanup tool for XSK map entries
 * Uses the same syscalls as the application to ensure compatibility
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <bpf/bpf.h>
#include <bpf/libbpf.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <interface> [queue_id]\n", argv[0]);
        fprintf(stderr, "  If queue_id not specified, cleans queues 0-7\n");
        return 1;
    }
    
    const char *iface = argv[1];
    int target_queue = -1;
    
    if (argc >= 3) {
        target_queue = atoi(argv[2]);
    }
    
    printf("Cleaning up XSK map entries for interface %s\n", iface);
    
    // Find the xsks_map by iterating through all maps
    uint32_t map_id = 0;
    int map_fd = -1;
    bool found_map = false;
    
    while (bpf_map_get_next_id(map_id, &map_id) == 0) {
        int fd = bpf_map_get_fd_by_id(map_id);
        if (fd < 0) continue;
        
        struct bpf_map_info info = {};
        __u32 info_len = sizeof(info);
        
        if (bpf_obj_get_info_by_fd(fd, &info, &info_len) == 0) {
            if (strcmp(info.name, "xsks_map") == 0 && info.type == BPF_MAP_TYPE_XSKMAP) {
                map_fd = fd;
                found_map = true;
                printf("Found XSK map (ID: %u, fd: %d)\n", map_id, fd);
                break;
            }
        }
        close(fd);
    }
    
    if (!found_map || map_fd < 0) {
        fprintf(stderr, "ERROR: Could not find xsks_map. Is XDP program loaded?\n");
        return 1;
    }
    
    int cleaned = 0;
    
    if (target_queue >= 0) {
        // Clean specific queue
        int key = target_queue;
        if (bpf_map_delete_elem(map_fd, &key) == 0) {
            printf("Successfully deleted entry for queue %d\n", target_queue);
            cleaned++;
        } else {
            printf("No entry found for queue %d (errno: %d - %s)\n", 
                   target_queue, errno, strerror(errno));
        }
        
        // Also try queue 0 if cleaning a different queue
        if (target_queue != 0) {
            int queue0_key = 0;
            if (bpf_map_delete_elem(map_fd, &queue0_key) == 0) {
                printf("Also deleted entry for queue 0\n");
                cleaned++;
            }
        }
    } else {
        // Clean all queues 0-7
        printf("Cleaning queues 0-7...\n");
        for (int q = 0; q < 8; q++) {
            int key = q;
            if (bpf_map_delete_elem(map_fd, &key) == 0) {
                printf("  Deleted entry for queue %d\n", q);
                cleaned++;
            }
        }
    }
    
    close(map_fd);
    
    if (cleaned > 0) {
        printf("Cleanup complete: removed %d entries\n", cleaned);
    } else {
        printf("No entries found to clean (map was already empty)\n");
    }
    
    return 0;
}

