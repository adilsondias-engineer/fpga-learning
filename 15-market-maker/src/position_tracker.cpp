#include "position_tracker.h"
#include <cmath>

namespace mm {

void PositionTracker::addFill(const std::string& symbol, int shares, double price) {
    auto& pos = positions_[symbol];
    pos.symbol = symbol;

    // Calculate realized PnL for reducing positions
    if ((pos.shares > 0 && shares < 0) || (pos.shares < 0 && shares > 0)) {
        // Position reduction - calculate realized PnL
        int reducing_shares = std::min(std::abs(shares), std::abs(pos.shares));
        double pnl_per_share = (pos.shares > 0) ? (price - pos.avg_entry_price) : (pos.avg_entry_price - price);
        pos.realized_pnl += pnl_per_share * reducing_shares;
    }

    // Update position and average entry price
    int new_shares = pos.shares + shares;

    if (new_shares == 0) {
        // Position closed
        pos.shares = 0;
        pos.avg_entry_price = 0.0;
        pos.unrealized_pnl = 0.0;
    } else if ((pos.shares >= 0 && new_shares >= 0) || (pos.shares <= 0 && new_shares <= 0)) {
        // Position increase - update average entry price
        if (pos.shares == 0) {
            pos.avg_entry_price = price;
        } else {
            // Weighted average entry price
            double total_cost = (pos.avg_entry_price * std::abs(pos.shares)) + (price * std::abs(shares));
            pos.avg_entry_price = total_cost / std::abs(new_shares);
        }
        pos.shares = new_shares;
    } else {
        // Position flip (long to short or vice versa)
        pos.shares = new_shares;
        pos.avg_entry_price = price;
        pos.unrealized_pnl = 0.0;
    }
}

Position PositionTracker::getPosition(const std::string& symbol) const {
    auto it = positions_.find(symbol);
    if (it != positions_.end()) {
        return it->second;
    }

    // Return empty position if not found
    Position pos;
    pos.symbol = symbol;
    return pos;
}

void PositionTracker::updateMarketPrice(const std::string& symbol, double price) {
    auto it = positions_.find(symbol);
    if (it != positions_.end() && it->second.shares != 0) {
        // Calculate unrealized PnL
        Position& pos = it->second;
        if (pos.shares > 0) {
            // Long position: PnL = (current_price - entry_price) * shares
            pos.unrealized_pnl = (price - pos.avg_entry_price) * pos.shares;
        } else {
            // Short position: PnL = (entry_price - current_price) * abs(shares)
            pos.unrealized_pnl = (pos.avg_entry_price - price) * std::abs(pos.shares);
        }
    }
}

double PositionTracker::getTotalPnL() const {
    double total = 0.0;
    for (const auto& pair : positions_) {
        total += pair.second.realized_pnl + pair.second.unrealized_pnl;
    }
    return total;
}

double PositionTracker::getTotalNotional() const {
    double total = 0.0;
    for (const auto& pair : positions_) {
        const Position& pos = pair.second;
        total += std::abs(pos.shares) * pos.avg_entry_price;
    }
    return total;
}

} // namespace mm
