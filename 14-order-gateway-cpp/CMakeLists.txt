cmake_minimum_required(VERSION 3.20)
project(OrderGateway CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add vcpkg installed directory to CMAKE_PREFIX_PATH if it exists
if(EXISTS "${CMAKE_SOURCE_DIR}/vcpkg_installed/x64-linux/share")
    list(APPEND CMAKE_PREFIX_PATH "${CMAKE_SOURCE_DIR}/vcpkg_installed/x64-linux/share")
    message(STATUS "Added vcpkg_installed to CMAKE_PREFIX_PATH")
endif()

find_package(eclipse-paho-mqtt-c CONFIG REQUIRED)
find_package(RdKafka CONFIG REQUIRED)

# Define _WIN32_WINNT for Windows
if(WIN32)
    add_definitions(-D_WIN32_WINNT=0x0601)
endif()

# Set default build type to Debug if not specified
# This is required for single-config generators (like Ninja) to work properly with IntelliSense
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
    message(STATUS "CMAKE_BUILD_TYPE not set, defaulting to Debug")
endif()

# Generate compile_commands.json for IntelliSense
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Include directories
include_directories(${CMAKE_SOURCE_DIR}/include)

# Source files
set(SOURCES
    src/main.cpp
    src/order_gateway.cpp
    src/udp_listener.cpp
    src/bbo_parser.cpp
    src/tcp_server.cpp
    src/csv_logger.cpp
    src/mqtt.cpp
    src/kafka_producer.cpp
)

# Executable
add_executable(order_gateway ${SOURCES})

# Link Paho MQTT C library (synchronous client)
target_link_libraries(order_gateway PRIVATE eclipse-paho-mqtt-c::paho-mqtt3a-static eclipse-paho-mqtt-c::paho-mqtt3c-static eclipse-paho-mqtt-c::paho-mqtt3as-static eclipse-paho-mqtt-c::paho-mqtt3cs-static)

# Link Kafka libraries (using librdkafka C++ API)
# rdkafka::rdkafka++ target links C++ API and pulls C core transitively
target_link_libraries(order_gateway PRIVATE RdKafka::rdkafka++)

# Link pthread library (required for RT scheduling and CPU pinning)
find_package(Threads REQUIRED)
target_link_libraries(order_gateway PRIVATE Threads::Threads)

# Boost.Asio integration
# Try to find Boost (works with vcpkg if vcpkg toolchain is set)
find_package(Boost REQUIRED COMPONENTS system thread)

if(Boost_FOUND)
    message(STATUS "Boost found: ${Boost_VERSION}")
    message(STATUS "Boost include dirs: ${Boost_INCLUDE_DIRS}")
    
    # Link Boost.System (required for Boost.Asio error codes)
    if(TARGET Boost::system AND TARGET Boost::thread)
        target_link_libraries(order_gateway PRIVATE Boost::system Boost::thread)
    elseif(TARGET boost_system AND TARGET boost_thread)
        target_link_libraries(order_gateway PRIVATE boost_system boost_thread)
    else()
        # Fallback: link the library directly
        find_library(BOOST_SYSTEM_LIB 
            NAMES boost_system
                  libboost_system
            PATHS ${Boost_LIBRARY_DIRS}
        )
        if(BOOST_SYSTEM_LIB AND BOOST_THREAD_LIB    )
            target_link_libraries(order_gateway PRIVATE ${BOOST_SYSTEM_LIB} ${BOOST_THREAD_LIB})
        else()
            message(WARNING "Boost.System library not found, but headers should still work")
        endif()
    endif()
    
    # Add Boost include directory
    if(Boost_INCLUDE_DIRS)
        target_include_directories(order_gateway PRIVATE ${Boost_INCLUDE_DIRS})
    endif()
    
    # Define preprocessor macro to indicate Boost.Asio is available
    target_compile_definitions(order_gateway PRIVATE USE_BOOST_ASIO)
    message(STATUS "Boost.Asio configured successfully")
else()
    message(FATAL_ERROR 
        "Boost not found!\n"
        "Install Boost using one of these methods:\n"
        "  1. vcpkg: vcpkg install boost-system\n"
        "  2. Download from: https://www.boost.org/\n"
        "  3. Set Boost_ROOT to your Boost installation directory"
    )
endif()

# Installation
install(TARGETS order_gateway DESTINATION bin)
# Linux-specific optimizations
if(UNIX AND NOT APPLE)
    target_compile_options(order_gateway PRIVATE -march=native -O3)
endif()
# Print build information
message(STATUS "Build configuration:")
message(STATUS "  CMAKE_BUILD_TYPE: ${CMAKE_BUILD_TYPE}")
message(STATUS "  CMAKE_SYSTEM_NAME: ${CMAKE_SYSTEM_NAME}")
message(STATUS "  CMAKE_CXX_COMPILER: ${CMAKE_CXX_COMPILER}")
message(STATUS "  CMAKE_CXX_STANDARD: ${CMAKE_CXX_STANDARD}")
