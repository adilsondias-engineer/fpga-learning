#include "csv_logger.h"
#include <stdexcept>
#include <iomanip>

namespace gateway
{

    CSVLogger::CSVLogger(const std::string &filename)
        : filename_(filename)
    {

        // open CSV file for writing
        file_.open(filename_, std::ios::app);
        if (!file_.is_open())
        {
            throw std::runtime_error("Failed to open CSV file: " + filename_);
        }
        // Check if file is empty (new file) to write header
        file_.seekp(0, std::ios::end);
        if (file_.tellp() == 0)
        {
            write_header();
        }
    }

    CSVLogger::~CSVLogger()
    {
        // close file
        if (file_.is_open())
        {
            file_.close();
        }
    }

    void CSVLogger::log(const BBOData &bbo)
    {
        // write BBO data to CSV
        // check if BBO is valid (bbo.valid == true)
        // write CSV row: timestamp,symbol,bid,bid_shares,ask,ask_shares,spread
        // flush file to ensure data is written
        // use std::fixed and std::setprecision(2) for prices

        if (!bbo.valid)
        {
            return; // skip invalid BBO
        }

        file_ << bbo.timestamp_ns << ","
              << bbo.symbol << ","
              << std::fixed << std::setprecision(2) << bbo.bid_price << ","
              << bbo.bid_shares << ","
              << bbo.ask_price << ","
              << bbo.ask_shares << ","
              << bbo.spread << std::endl;
        file_.flush(); // Ensure data is written immediately
    }

    bool CSVLogger::is_open() const
    {
        return file_.is_open();
    }

    void CSVLogger::write_header()
    {
        // write CSV header row
        // header: timestamp,symbol,bid,bid_shares,ask,ask_shares,spread
        file_ << "timestamp,symbol,bid,bid_shares,ask,ask_shares,spread" << std::endl;
    }

} // namespace gateway
