cmake_minimum_required(VERSION 3.20)
project(marketMaker CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add vcpkg installed directory to CMAKE_PREFIX_PATH if it exists
if(EXISTS "${CMAKE_SOURCE_DIR}/vcpkg_installed/x64-linux/share")
    list(APPEND CMAKE_PREFIX_PATH "${CMAKE_SOURCE_DIR}/vcpkg_installed/x64-linux/share")
    message(STATUS "Added vcpkg_installed to CMAKE_PREFIX_PATH")
endif()

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
    src/udp_listener.cpp
    src/bbo_parser.cpp
    src/market_maker_fsm.cpp
    src/position_tracker.cpp
)

# Executable
add_executable(market_maker ${SOURCES})

find_package(spdlog REQUIRED)
target_link_libraries(market_maker PRIVATE spdlog::spdlog)
find_package(nlohmann_json REQUIRED)
target_link_libraries(market_maker PRIVATE nlohmann_json::nlohmann_json)
# Add spdlog include directory
target_include_directories(market_maker PRIVATE ${spdlog_INCLUDE_DIRS})

# Link pthread library (required for RT scheduling and CPU pinning)
find_package(Threads REQUIRED)
target_link_libraries(market_maker PRIVATE Threads::Threads)

# Boost.Asio integration
# Try to find Boost (works with vcpkg if vcpkg toolchain is set)
find_package(Boost REQUIRED COMPONENTS system thread)

if(Boost_FOUND)
    message(STATUS "Boost found: ${Boost_VERSION}")
    message(STATUS "Boost include dirs: ${Boost_INCLUDE_DIRS}")
    
    # Link Boost.System (required for Boost.Asio error codes)
    if(TARGET Boost::system AND TARGET Boost::thread)
        target_link_libraries(market_maker PRIVATE Boost::system Boost::thread)
    elseif(TARGET boost_system AND TARGET boost_thread)
        target_link_libraries(market_maker PRIVATE boost_system boost_thread)
    else()
        # Fallback: link the library directly
        find_library(BOOST_SYSTEM_LIB 
            NAMES boost_system
                  libboost_system
            PATHS ${Boost_LIBRARY_DIRS}
        )
        if(BOOST_SYSTEM_LIB AND BOOST_THREAD_LIB    )
            target_link_libraries(market_maker PRIVATE ${BOOST_SYSTEM_LIB} ${BOOST_THREAD_LIB})
        else()
            message(WARNING "Boost.System library not found, but headers should still work")
        endif()
    endif()
    
    # Add Boost include directory
    if(Boost_INCLUDE_DIRS)
        target_include_directories(market_maker PRIVATE ${Boost_INCLUDE_DIRS})
    endif()
    
    # Define preprocessor macro to indicate Boost.Asio is available
    target_compile_definitions(market_maker PRIVATE USE_BOOST_ASIO)
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
install(TARGETS market_maker DESTINATION bin)

# Linux-specific optimizations
if(UNIX AND NOT APPLE)
    target_compile_options(market_maker PRIVATE -march=native -O3)
endif()

# Print build information
message(STATUS "Build configuration:")
message(STATUS "  CMAKE_BUILD_TYPE: ${CMAKE_BUILD_TYPE}")
message(STATUS "  CMAKE_SYSTEM_NAME: ${CMAKE_SYSTEM_NAME}")
message(STATUS "  CMAKE_CXX_COMPILER: ${CMAKE_CXX_COMPILER}")
message(STATUS "  CMAKE_CXX_STANDARD: ${CMAKE_CXX_STANDARD}")
