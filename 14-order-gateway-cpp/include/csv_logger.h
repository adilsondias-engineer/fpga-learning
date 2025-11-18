#pragma once

#include "bbo_parser.h"
#include <fstream>
#include <string>

namespace gateway {

/**
 * CSV Logger
 * Logs BBO updates to CSV file for historical analysis
 *
 * CSV format:
 *   timestamp,symbol,bid,bid_shares,ask,ask_shares,spread
 */
class CSVLogger {
public:
    /**
     * Constructor - opens CSV file
     * @param filename CSV file path
     * @throws std::runtime_error if file cannot be opened
     */
    explicit CSVLogger(const std::string& filename);

    /**
     * Destructor - closes CSV file
     */
    ~CSVLogger();

    // Disable copy/move
    CSVLogger(const CSVLogger&) = delete;
    CSVLogger& operator=(const CSVLogger&) = delete;

    /**
     * Log BBO update to CSV
     * @param bbo BBO data structure
     */
    void log(const BBOData& bbo);

    /**
     * Check if file is open
     * @return true if file is open and ready
     */
    bool is_open() const;

private:
    std::ofstream file_;
    std::string filename_;

    /**
     * Write CSV header row
     */
    void write_header();
};

} // namespace gateway
