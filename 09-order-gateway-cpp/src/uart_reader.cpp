#include "uart_reader.h"
#include <stdexcept>
#include <boost/asio.hpp>
#include <iostream>

namespace gateway
{

    UartReader::UartReader(const std::string &port_name, int baud_rate)
        : io_context_(), port_name_(port_name), baud_rate_(baud_rate),
          serial_port_(io_context_)
    {
        try
        {
            // Open the serial port
            serial_port_.open(port_name_);

            // Configure serial port settings
            serial_port_.set_option(boost::asio::serial_port_base::baud_rate(baud_rate_));
            serial_port_.set_option(boost::asio::serial_port_base::character_size(8));
            serial_port_.set_option(boost::asio::serial_port_base::parity(boost::asio::serial_port_base::parity::none));
            serial_port_.set_option(boost::asio::serial_port_base::stop_bits(boost::asio::serial_port_base::stop_bits::one));
            serial_port_.set_option(boost::asio::serial_port_base::flow_control(boost::asio::serial_port_base::flow_control::none));
        }
        catch (const boost::system::system_error &e)
        {
            throw std::runtime_error("Failed to open serial port " + port_name_ + ": " + e.what());
        }
    }

    UartReader::~UartReader()
    {
        if (serial_port_.is_open())
        {
            try
            {
                serial_port_.close();
            }
            catch (...)
            {
                // Ignore errors during cleanup
            }
        }
    }

    std::string UartReader::read_line()
    {
        std::string line;
        char byte;

        // Read characters until newline
        while (true)
        {
            try
            {
                // Read one byte
                boost::asio::read(serial_port_, boost::asio::buffer(&byte, 1));

                // If newline, break
                /* if (byte == '\n')
                 {
                     break;
                 }*/

                // Append to line (skip carriage return)
                if (byte != '\r')
                {
                    line += byte;
                }
            }
            catch (const boost::system::system_error &e)
            {
                // If error occurs, return what we have so far or throw
                if (line.empty())
                {
                    throw std::runtime_error(std::string("Failed to read from serial port: ") + e.what());
                }
                break;
            }

            // If newline, break
            if (byte == '\n')
            {
                // std::cout << "Read line: " << line << std::endl;
                return line;
            }
        }
        return "";
    }

    bool UartReader::is_open() const
    {
        return serial_port_.is_open();
    }

} // namespace gateway
