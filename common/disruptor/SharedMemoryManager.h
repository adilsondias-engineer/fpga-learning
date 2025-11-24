#pragma once

#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdexcept>
#include <string>

namespace disruptor {

template<typename T>
class SharedMemoryManager {
public:
    static T* create(const std::string& name) {
        const std::string shm_name = "/bbo_ring_" + name;
        shm_unlink(shm_name.c_str());

        int fd = shm_open(shm_name.c_str(), O_CREAT | O_RDWR | O_EXCL, 0666);
        if (fd == -1) {
            throw std::runtime_error("Failed to create shared memory: " + shm_name);
        }

        if (ftruncate(fd, sizeof(T)) == -1) {
            ::close(fd);
            shm_unlink(shm_name.c_str());
            throw std::runtime_error("Failed to set shared memory size");
        }

        void* ptr = mmap(nullptr, sizeof(T), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        ::close(fd);

        if (ptr == MAP_FAILED) {
            shm_unlink(shm_name.c_str());
            throw std::runtime_error("Failed to map shared memory");
        }

        return new (ptr) T();
    }

    static T* open(const std::string& name) {
        const std::string shm_name = "/bbo_ring_" + name;
        int fd = shm_open(shm_name.c_str(), O_RDWR, 0666);
        if (fd == -1) {
            throw std::runtime_error("Failed to open shared memory: " + shm_name);
        }

        void* ptr = mmap(nullptr, sizeof(T), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        ::close(fd);

        if (ptr == MAP_FAILED) {
            throw std::runtime_error("Failed to map shared memory");
        }

        return static_cast<T*>(ptr);
    }

    static void destroy(const std::string& name, T* ptr) {
        if (ptr) {
            ptr->~T();
            munmap(ptr, sizeof(T));
        }
        const std::string shm_name = "/bbo_ring_" + name;
        shm_unlink(shm_name.c_str());
    }

    static void disconnect(T* ptr) {
        if (ptr) {
            munmap(ptr, sizeof(T));
        }
    }
};

}  // namespace disruptor
