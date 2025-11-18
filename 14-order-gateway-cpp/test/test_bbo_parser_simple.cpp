// Simple test for BBO parser (without Google Test framework)
// Compile and run manually to test parsing logic

#include "bbo_parser.h"
#include <iostream>
#include <cassert>
#include <vector>
#include <cstring>
#include <arpa/inet.h>

using namespace gateway;

void test_parse_valid_bbo()
{
    std::cout << "Test: Parse valid BBO... ";

    // Construct UDP payload: 256 bytes, BBO at offset 228, 28 bytes
    std::vector<uint8_t> buf(256, 0);
    const std::size_t BBO_OFFSET = 228;
    auto* p = buf.data() + BBO_OFFSET;

    // Values (big-endian), prices scaled by 1e4
    uint32_t spread_be     = htonl(25000);    // 2.5000
    uint32_t ask_sh_be     = htonl(300);
    uint32_t ask_px_be     = htonl(1520000);  // 152.0000
    uint32_t bid_sh_be     = htonl(300);
    uint32_t bid_px_be     = htonl(1495000);  // 149.5000
    std::memcpy(p + 0,  &spread_be, 4);
    std::memcpy(p + 4,  &ask_sh_be, 4);
    std::memcpy(p + 8,  &ask_px_be, 4);
    std::memcpy(p + 12, &bid_sh_be, 4);
    std::memcpy(p + 16, &bid_px_be, 4);
    char symbol[8] = {'A','A','P','L',' ',' ',' ',' '};
    std::memcpy(p + 20, symbol, 8);

    BBOData bbo = BBOParser::parseBBOData(buf.data(), buf.size());

    assert(bbo.valid == true);
    assert(bbo.symbol == "AAPL");
    assert(bbo.bid_price == 149.5000);
    assert(bbo.bid_shares == 300);
    assert(bbo.ask_price == 152.0000);
    assert(bbo.ask_shares == 300);
    assert(bbo.spread == 2.5000);

    std::cout << "PASSED" << std::endl;
}

void test_parse_nodata()
{
    std::cout << "Test: Parse NODATA... ";

    // Too-short buffer (len < 228+28) should yield invalid
    std::vector<uint8_t> short_buf(100, 0);
    BBOData bbo = BBOParser::parseBBOData(short_buf.data(), short_buf.size());

    assert(bbo.valid == false);

    std::cout << "PASSED" << std::endl;
}

void test_hex_to_price()
{
    std::cout << "Test: Hex to price conversion... ";

    double price1 = BBOParser::hex_to_price("0x0016E360");
    assert(price1 == 150.00); // 1500000 / 10000
    double price2 = BBOParser::hex_to_price("0x0016D99C");
    assert(price2 == 149.9484); // 1499484 / 10000

    std::cout << "PASSED" << std::endl;
}

void test_hex_to_uint()
{
    std::cout << "Test: Hex to uint conversion... ";

    uint32_t shares1 = BBOParser::hex_to_uint("0x00000064");
    assert(shares1 == 100);
    uint32_t shares2 = BBOParser::hex_to_uint("0x000000C8");
    assert(shares2 == 200);

    std::cout << "PASSED" << std::endl;
}

void test_bbo_to_json()
{
    std::cout << "Test: BBO to JSON conversion... ";

    BBOData bbo;
    bbo.symbol = "AAPL";
    bbo.bid_price = 150.00;
    bbo.bid_shares = 100;
    bbo.ask_price = 149.95;
    bbo.ask_shares = 200;
    bbo.spread = 0.50;
    bbo.timestamp_ns = 1699824000123456789;
    bbo.valid = true;

    std::string json = bbo_to_json(bbo);

    assert(json.find("\"type\":\"bbo\"") != std::string::npos);
    assert(json.find("\"symbol\":\"AAPL\"") != std::string::npos);
    assert(json.find("\"timestamp\":1699824000123456789") != std::string::npos);
    assert(json.find("\"bid\"") != std::string::npos);
    assert(json.find("\"price\":150.0000") != std::string::npos);
    assert(json.find("\"shares\":100") != std::string::npos);
    assert(json.find("\"ask\"") != std::string::npos);
    assert(json.find("\"spread\"") != std::string::npos);

    std::cout << "JSON: " << json << std::endl;
    std::cout << "PASSED" << std::endl;
}

int main()
{
    std::cout << "=== BBO Parser Tests ===" << std::endl;
    std::cout << std::endl;

    test_parse_valid_bbo();
    test_parse_nodata();
    test_hex_to_price();
    test_hex_to_uint();
    test_bbo_to_json();

    std::cout << std::endl;
    std::cout << "All tests completed!" << std::endl;
    std::cout << "Note: Most assertions are disabled until implementation is complete." << std::endl;

    return 0;
}
