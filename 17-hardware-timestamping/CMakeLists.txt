cmake_minimum_required(VERSION 3.20)
project(HardwareTimestamping VERSION 1.0.0 LANGUAGES CXX)

# C++20 standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Compiler flags
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Wpedantic")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -O3 -DNDEBUG")
set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -g -O0 -DDEBUG")

# Default to Release build
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")

# Find dependencies
find_package(Threads REQUIRED)

# Check for nlohmann/json (for config parsing)
find_package(nlohmann_json 3.2.0 QUIET)
if(NOT nlohmann_json_FOUND)
    message(STATUS "nlohmann/json not found via CMake, checking vcpkg...")
    if(DEFINED ENV{VCPKG_ROOT})
        set(CMAKE_PREFIX_PATH "$ENV{VCPKG_ROOT}/installed/x64-linux/share")
        find_package(nlohmann_json 3.2.0 REQUIRED)
    else()
        message(FATAL_ERROR "nlohmann/json not found. Install via: sudo apt install nlohmann-json3-dev or vcpkg install nlohmann-json")
    endif()
endif()

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
)

# Source files
set(TIMESTAMP_SOURCES
    src/timestamp_socket.cpp
    src/latency_tracker.cpp
    src/prometheus_exporter.cpp
)

# Create static library
add_library(timestamp_lib STATIC ${TIMESTAMP_SOURCES})
target_link_libraries(timestamp_lib
    PUBLIC
        Threads::Threads
    PRIVATE
        nlohmann_json::nlohmann_json
)

# Main executable
add_executable(timestamp_demo src/main.cpp)
target_link_libraries(timestamp_demo
    PRIVATE
        timestamp_lib
        nlohmann_json::nlohmann_json
)

# Installation rules
install(TARGETS timestamp_demo
    RUNTIME DESTINATION bin
)

install(DIRECTORY include/
    DESTINATION include/timestamp
    FILES_MATCHING PATTERN "*.h"
)

install(TARGETS timestamp_lib
    ARCHIVE DESTINATION lib
)

# Copy config.json to build directory
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/config.json
    ${CMAKE_CURRENT_BINARY_DIR}/config.json
    COPYONLY
)

# Print configuration summary
message(STATUS "========================================")
message(STATUS "Hardware Timestamping Configuration")
message(STATUS "========================================")
message(STATUS "C++ Standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "Compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "Install prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS "========================================")
