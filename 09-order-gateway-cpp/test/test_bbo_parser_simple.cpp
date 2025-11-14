// Simple test for BBO parser (without Google Test framework)
// Compile and run manually to test parsing logic

#include "bbo_parser.h"
#include <iostream>
#include <cassert>

using namespace gateway;

void test_parse_valid_bbo()
{
    std::cout << "Test: Parse valid BBO... ";

    std::string line = "[BBO:AAPL    ]Bid:0x0016E360 (0x00000064) | Ask:0x0016D99C (0x000000C8) | Spr:0x00001388";
    BBOData bbo = BBOParser::parse(line);

    assert(bbo.valid == true);
    assert(bbo.symbol == "AAPL");
    assert(bbo.bid_price == 150.00); // 0x0016E360 = 1500000 / 10000
    assert(bbo.bid_shares == 100);   // 0x00000064 = 100
    assert(bbo.ask_price == 149.95); // 0x0016D99C = 1499484 / 10000
    assert(bbo.ask_shares == 200);   // 0x000000C8 = 200
    assert(bbo.spread == 0.50);      // 0x00001388 = 5000 / 10000

    std::cout << "PASSED" << std::endl;
}

void test_parse_nodata()
{
    std::cout << "Test: Parse NODATA... ";

    std::string line = "[BBO:NODATA  ]";
    BBOData bbo = BBOParser::parse(line);

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
