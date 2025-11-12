#include "csv_logger.h"
#include <stdexcept>

namespace gateway {

CSVLogger::CSVLogger(const std::string& filename)
    : filename_(filename) {

    // TODO: Open CSV file for writing
    //
    // Steps:
    // 1. Open file using std::ofstream in append mode (std::ios::app)
    // 2. Check if file opened successfully
    // 3. If file is new (or empty), write header row
    // 4. Throw std::runtime_error if open fails
    //
    // Hint: Use file_.is_open() to check success
    // Hint: Use file_.tellp() to check if file is empty

    // TODO: file_.open(filename_, std::ios::app);
    // TODO: Check file_.is_open()
    // TODO: Write header if needed
}

CSVLogger::~CSVLogger() {
    // TODO: Close file
    //
    // std::ofstream automatically closes in destructor,
    // but explicit close is good practice

    if (file_.is_open()) {
        file_.close();
    }
}

void CSVLogger::log(const BBOData& bbo) {
    // TODO: Write BBO data to CSV
    //
    // Steps:
    // 1. Check if BBO is valid (bbo.valid == true)
    // 2. Write CSV row: timestamp,symbol,bid,bid_shares,ask,ask_shares,spread
    // 3. Flush file to ensure data is written
    //
    // Example output:
    //   2025-11-12T10:30:45.123Z,AAPL,150.00,100,149.95,200,0.50
    //
    // Hint: Use std::fixed and std::setprecision(2) for prices

    if (!bbo.valid) {
        return;  // Skip invalid BBO
    }

    // TODO: Write CSV row
    // file_ << bbo.timestamp << ","
    //       << bbo.symbol << ","
    //       << std::fixed << std::setprecision(2) << bbo.bid_price << ","
    //       << ...
    //       << std::endl;
}

bool CSVLogger::is_open() const {
    return file_.is_open();
}

void CSVLogger::write_header() {
    // TODO: Write CSV header row
    //
    // Header: timestamp,symbol,bid,bid_shares,ask,ask_shares,spread

    // file_ << "timestamp,symbol,bid,bid_shares,ask,ask_shares,spread" << std::endl;
}

} // namespace gateway
