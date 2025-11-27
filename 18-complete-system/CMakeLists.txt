cmake_minimum_required(VERSION 3.20)
project(CompleteTradingSystem VERSION 1.0.0 LANGUAGES CXX)

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

# Check for nlohmann/json
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
set(ORCHESTRATOR_SOURCES
    src/system_orchestrator.cpp
    src/metrics_aggregator.cpp
    src/prometheus_server.cpp
    src/main.cpp
)

# Main executable
add_executable(trading_system_orchestrator ${ORCHESTRATOR_SOURCES})
target_link_libraries(trading_system_orchestrator
    PRIVATE
        Threads::Threads
        nlohmann_json::nlohmann_json
)

# Installation rules
install(TARGETS trading_system_orchestrator
    RUNTIME DESTINATION bin
)

install(DIRECTORY config/
    DESTINATION etc/trading-system
    FILES_MATCHING PATTERN "*.json"
)

install(DIRECTORY scripts/
    DESTINATION bin
    FILES_MATCHING PATTERN "*.sh"
    PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ GROUP_EXECUTE GROUP_READ
)

# Copy config to build directory
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/config/system_config.json
    ${CMAKE_CURRENT_BINARY_DIR}/config/system_config.json
    COPYONLY
)

# Print configuration summary
message(STATUS "========================================")
message(STATUS "Complete Trading System Configuration")
message(STATUS "========================================")
message(STATUS "C++ Standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")
message(STATUS "Compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "Install prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS "========================================")
