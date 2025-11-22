#include "market_maker_fsm.h"
#include <cmath>
#include <chrono>

namespace mm {

MarketMakerFSM::MarketMakerFSM(const Config& config)
    : state_(State::IDLE), config_(config) {
    logger_ = spdlog::get("market_maker");
    if (!logger_) {
        logger_ = spdlog::stdout_color_mt("market_maker");
    }
    logger_->info("MarketMakerFSM initialized with config: spread={} bps, edge={} bps, max_pos={}, skew={} bps",
                  config_.min_spread_bps, config_.edge_bps, config_.max_position, config_.position_skew_bps);
}

void MarketMakerFSM::onBboUpdate(const BBO& bbo) {
    if (!bbo.valid) {
        return;
    }

    switch (state_) {
        case State::IDLE:
            state_ = State::CALCULATE;
            handleCalculate(bbo);
            break;

        case State::CALCULATE:
            handleCalculate(bbo);
            break;

        case State::QUOTE:
            handleQuote(bbo);
            break;

        case State::RISK_CHECK:
            handleRiskCheck();
            break;

        case State::ORDER_GEN:
            handleOrderGen();
            break;

        case State::WAIT_FILL:
            handleWaitFill();
            state_ = State::CALCULATE;
            handleCalculate(bbo);
            break;
    }
}

void MarketMakerFSM::handleCalculate(const BBO& bbo) {
    double fair_value = calculateFairValue(bbo);

    logger_->debug("CALCULATE: symbol={}, fair_value={:.4f}, spread={:.4f}",
                   bbo.symbol, fair_value, bbo.spread);

    state_ = State::QUOTE;
    handleQuote(bbo);
}

void MarketMakerFSM::handleQuote(const BBO& bbo) {
    double fair_value = calculateFairValue(bbo);
    current_quote_ = generateQuote(fair_value, bbo);

    if (!current_quote_.valid) {
        logger_->warn("QUOTE: Invalid quote generated, returning to IDLE");
        state_ = State::IDLE;
        return;
    }

    logger_->debug("QUOTE: symbol={}, bid={:.4f}x{}, ask={:.4f}x{}, fair={:.4f}",
                   current_quote_.symbol, current_quote_.bid_price, current_quote_.bid_size,
                   current_quote_.ask_price, current_quote_.ask_size, current_quote_.fair_value);

    state_ = State::RISK_CHECK;
    handleRiskCheck();
}

void MarketMakerFSM::handleRiskCheck() {
    bool risk_ok = checkRiskLimits(current_quote_);

    if (!risk_ok) {
        logger_->warn("RISK_CHECK: Risk limits exceeded, skipping quote");
        state_ = State::IDLE;
        return;
    }

    logger_->debug("RISK_CHECK: Passed");
    state_ = State::ORDER_GEN;
    handleOrderGen();
}

void MarketMakerFSM::handleOrderGen() {
    logger_->info("ORDER_GEN: Sending quote: {}@{:.4f} / {:.4f}@{}",
                  current_quote_.bid_size, current_quote_.bid_price,
                  current_quote_.ask_price, current_quote_.ask_size);

    state_ = State::WAIT_FILL;
}

void MarketMakerFSM::handleWaitFill() {
    logger_->debug("WAIT_FILL: Simulating fill");
}

double MarketMakerFSM::calculateFairValue(const BBO& bbo) {
    if (bbo.bid_price <= 0.0 || bbo.ask_price <= 0.0) {
        return 0.0;
    }

    double mid_price = (bbo.bid_price + bbo.ask_price) / 2.0;

    uint32_t total_size = bbo.bid_shares + bbo.ask_shares;
    if (total_size == 0) {
        return mid_price;
    }

    double weighted_price = (bbo.bid_price * bbo.bid_shares + bbo.ask_price * bbo.ask_shares) / total_size;

    return (mid_price + weighted_price) / 2.0;
}

Quote MarketMakerFSM::generateQuote(double fair_value, const BBO& bbo) {
    Quote quote;
    quote.symbol = bbo.symbol;
    quote.fair_value = fair_value;
    quote.timestamp_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::high_resolution_clock::now().time_since_epoch()
    ).count();

    if (fair_value <= 0.0) {
        quote.valid = false;
        return quote;
    }

    double edge = fair_value * (config_.edge_bps / 10000.0);

    Position pos = position_.getPosition(bbo.symbol);
    double skew = 0.0;
    if (pos.shares != 0 && config_.max_position > 0) {
        double inventory_ratio = static_cast<double>(pos.shares) / config_.max_position;
        skew = fair_value * (config_.position_skew_bps / 10000.0) * inventory_ratio;
    }

    quote.bid_price = fair_value - edge + skew;
    quote.ask_price = fair_value + edge + skew;
    quote.bid_size = config_.quote_size;
    quote.ask_size = config_.quote_size;

    double min_spread = fair_value * (config_.min_spread_bps / 10000.0);
    if (quote.ask_price - quote.bid_price < min_spread) {
        quote.bid_price = fair_value - min_spread / 2.0;
        quote.ask_price = fair_value + min_spread / 2.0;
    }

    quote.bid_price = std::max(quote.bid_price, 0.01);
    quote.ask_price = std::max(quote.ask_price, quote.bid_price + 0.01);

    quote.valid = true;
    return quote;
}

bool MarketMakerFSM::checkRiskLimits(const Quote& quote) {
    Position pos = position_.getPosition(quote.symbol);

    int bid_new_shares = pos.shares + quote.bid_size;
    int ask_new_shares = pos.shares - quote.ask_size;

    if (std::abs(bid_new_shares) > config_.max_position) {
        logger_->warn("Risk check failed: bid would exceed max position ({} > {})",
                      std::abs(bid_new_shares), config_.max_position);
        return false;
    }

    if (std::abs(ask_new_shares) > config_.max_position) {
        logger_->warn("Risk check failed: ask would exceed max position ({} > {})",
                      std::abs(ask_new_shares), config_.max_position);
        return false;
    }

    double bid_notional = std::abs(bid_new_shares) * quote.bid_price;
    double ask_notional = std::abs(ask_new_shares) * quote.ask_price;

    if (bid_notional > config_.max_notional) {
        logger_->warn("Risk check failed: bid notional exceeds limit ({:.2f} > {:.2f})",
                      bid_notional, config_.max_notional);
        return false;
    }

    if (ask_notional > config_.max_notional) {
        logger_->warn("Risk check failed: ask notional exceeds limit ({:.2f} > {:.2f})",
                      ask_notional, config_.max_notional);
        return false;
    }

    return true;
}

void MarketMakerFSM::simulateFill(const BBO& bbo) {
    if (std::rand() % 2 == 0) {
        Fill fill;
        fill.symbol = current_quote_.symbol;
        fill.side = Side::BUY;
        fill.price = current_quote_.bid_price;
        fill.shares = current_quote_.bid_size;
        fill.timestamp_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::high_resolution_clock::now().time_since_epoch()
        ).count();

        position_.addFill(fill.symbol, fill.shares, fill.price);
        logger_->info("FILL: BUY {} shares of {} @ {:.4f}",
                      fill.shares, fill.symbol, fill.price);
    } else {
        Fill fill;
        fill.symbol = current_quote_.symbol;
        fill.side = Side::SELL;
        fill.price = current_quote_.ask_price;
        fill.shares = -current_quote_.ask_size;
        fill.timestamp_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::high_resolution_clock::now().time_since_epoch()
        ).count();

        position_.addFill(fill.symbol, fill.shares, fill.price);
        logger_->info("FILL: SELL {} shares of {} @ {:.4f}",
                      std::abs(fill.shares), fill.symbol, fill.price);
    }

    Position pos = position_.getPosition(current_quote_.symbol);
    logger_->info("POSITION: {} shares, realized_pnl={:.2f}, unrealized_pnl={:.2f}",
                  pos.shares, pos.realized_pnl, pos.unrealized_pnl);
}

} // namespace mm
