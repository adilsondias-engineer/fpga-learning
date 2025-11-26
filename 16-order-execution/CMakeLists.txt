cmake_minimum_required(VERSION 3.15)
project(OrderExecutionEngine VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Find required packages
find_package(Boost REQUIRED COMPONENTS system thread)
find_package(spdlog REQUIRED)
find_package(nlohmann_json REQUIRED)

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../common
    ${Boost_INCLUDE_DIRS}
)

# Common source files
set(COMMON_SOURCES
    src/fix_encoder.cpp
    src/fix_decoder.cpp
)

# Order Execution Engine executable
add_executable(order_execution_engine
    ${COMMON_SOURCES}
    src/order_execution_engine.cpp
)

target_link_libraries(order_execution_engine
    ${Boost_LIBRARIES}
    spdlog::spdlog
    nlohmann_json::nlohmann_json
    pthread
    rt
)

# Simulated Exchange executable
add_executable(simulated_exchange
    ${COMMON_SOURCES}
    src/simulated_exchange_main.cpp
)

target_link_libraries(simulated_exchange
    ${Boost_LIBRARIES}
    spdlog::spdlog
    nlohmann_json::nlohmann_json
    pthread
)

# Install targets
install(TARGETS order_execution_engine simulated_exchange
    RUNTIME DESTINATION bin
)

# Copy config file
install(FILES config.json DESTINATION bin)
