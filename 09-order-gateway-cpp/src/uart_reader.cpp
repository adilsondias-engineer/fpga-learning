#include "uart_reader.h"
#include <stdexcept>

#ifdef _WIN32
    #include <windows.h>
#else
    #include <fcntl.h>
    #include <unistd.h>
    #include <termios.h>
#endif

namespace gateway {

UartReader::UartReader(const std::string& port_name, int baud_rate)
    : handle_(nullptr), port_name_(port_name), baud_rate_(baud_rate) {

    // TODO: Implement platform-specific serial port opening
    //
    // Windows:
    //   1. Use CreateFileA() to open COM port
    //   2. Use DCB structure to configure baud rate, 8N1 format
    //   3. Use SetCommState() to apply settings
    //   4. Use SetCommTimeouts() for blocking reads
    //
    // Linux:
    //   1. Use open() to open /dev/ttyUSB device
    //   2. Use termios structure to configure baud rate, 8N1 format
    //   3. Use tcsetattr() to apply settings
    //
    // Hint: Store file descriptor/HANDLE in handle_ member
    // Hint: Throw std::runtime_error if open fails

    init_platform();
}

UartReader::~UartReader() {
    // TODO: Close serial port
    //
    // Windows: Use CloseHandle()
    // Linux:   Use close()

#ifdef _WIN32
    if (handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE) {
        // TODO: CloseHandle((HANDLE)handle_);
    }
#else
    if (handle_ != nullptr) {
        // TODO: close((intptr_t)handle_);
    }
#endif
}

std::string UartReader::read_line() {
    // TODO: Implement line reading
    //
    // Steps:
    // 1. Create std::string to accumulate characters
    // 2. Loop:
    //    a. Read one byte using read_byte()
    //    b. If byte is '\n', break
    //    c. Append byte to string
    // 3. Return accumulated string
    //
    // Hint: Handle errors (return empty string or throw exception)

    std::string line;
    char byte;

    // TODO: Implement reading loop

    return line;
}

bool UartReader::is_open() const {
    // TODO: Check if port is open
    //
    // Windows: Return (handle_ != nullptr && handle_ != INVALID_HANDLE_VALUE)
    // Linux:   Return (handle_ != nullptr && (intptr_t)handle_ >= 0)

    return false;
}

void UartReader::init_platform() {
    // TODO: Platform-specific initialization
    //
    // See constructor TODO for details

#ifdef _WIN32
    // Windows implementation
    // TODO: CreateFileA(), SetCommState(), SetCommTimeouts()

#else
    // Linux implementation
    // TODO: open(), tcgetattr(), cfsetispeed(), cfsetospeed(), tcsetattr()

#endif
}

bool UartReader::read_byte(char* byte) {
    // TODO: Read single byte from serial port
    //
    // Windows:
    //   Use ReadFile(handle_, byte, 1, &bytes_read, nullptr)
    //   Return (bytes_read == 1)
    //
    // Linux:
    //   Use read((intptr_t)handle_, byte, 1)
    //   Return (result == 1)

#ifdef _WIN32
    // TODO: Implement Windows ReadFile()
    return false;
#else
    // TODO: Implement Linux read()
    return false;
#endif
}

} // namespace gateway
