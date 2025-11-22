#pragma once
#include <string>
#include <map>

namespace mm {

struct Position {
    std::string symbol;
    int shares = 0;              // +100 = long, -50 = short
    double avg_entry_price = 0.0;
    double unrealized_pnl = 0.0;
    double realized_pnl = 0.0;
};

class PositionTracker {
public:
    void addFill(const std::string& symbol, int shares, double price);
    Position getPosition(const std::string& symbol) const;
    void updateMarketPrice(const std::string& symbol, double price);
    
    double getTotalPnL() const;
    double getTotalNotional() const;

private:
    std::map<std::string, Position> positions_;
};

} // namespace mm