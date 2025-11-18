#pragma once

#include <string>
#include <boost/asio.hpp>
#include "common/perf_monitor.h"

namespace gateway {

/**
 * UART Reader
 * Cross-platform serial port reader using Boost.Asio
 */
class UartReader {
public:
    /**
     * Constructor - opens serial port
     * @param port_name Port name (e.g., "COM3" on Windows, "/dev/ttyUSB0" on Linux)
     * @param baud_rate Baud rate (default: 115200)
     * @throws std::runtime_error if port cannot be opened
     */
    UartReader(const std::string& port_name, int baud_rate = 115200);

    /**
     * Destructor - closes serial port
     */
    ~UartReader();

    // Disable copy/move
    UartReader(const UartReader&) = delete;
    UartReader& operator=(const UartReader&) = delete;

    /**
     * Read one line from serial port (blocking)
     * Reads until newline character (\n)
     * @return Line string (without \n)
     */
    std::string read_line();

    /**
     * Check if port is open
     * @return true if port is open and ready
     */
    bool is_open() const;

private:
    boost::asio::io_context io_context_;
    std::string port_name_;
    int baud_rate_;
    boost::asio::serial_port serial_port_;
};

} // namespace gateway
