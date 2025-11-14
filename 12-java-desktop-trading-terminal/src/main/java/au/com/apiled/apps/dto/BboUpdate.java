package au.com.apiled.apps.dto;

import com.google.gson.annotations.SerializedName;

/**
 * Data Transfer Object (DTO) for Best Bid Offer (BBO) updates.
 * Represents a single market data snapshot from the FPGA trading system.
 *
 * JSON structure expected from TCP socket on port 9999:
 * 
 * {"type":"bbo","symbol":"AAPL","timestamp":1763021597086443600,"bid":{"price":150.7500,"shares":150},"ask":{"price":152.0000,"shares":300},"spread":{"price":1.2500,"percent":0.826}}
 * 
 */
public class BboUpdate {

    @SerializedName("symbol")
    private String symbol;

    @SerializedName("bid")
    private PriceLevel bid;

    @SerializedName("ask")
    private PriceLevel ask;

    @SerializedName("spread")
    private Spread spread;

    @SerializedName("type")
    private String type;

    @SerializedName("timestamp")
    private long timestamp;

    // Calculated field (not from JSON)
    private double spreadPct;

    /**
     * Nested class for bid/ask price levels containing price and shares.
     */
    public static class PriceLevel {
        @SerializedName("price")
        private double price;

        @SerializedName("shares")
        private long shares;

        public PriceLevel() {
        }

        public PriceLevel(double price, long shares) {
            this.price = price;
            this.shares = shares;
        }

        public double getPrice() {
            return price;
        }

        public void setPrice(double price) {
            this.price = price;
        }

        public long getShares() {
            return shares;
        }

        public void setShares(long shares) {
            this.shares = shares;
        }

        @Override
        public String toString() {
            return String.format("PriceLevel{price=%.2f, shares=%d}", price, shares);
        }
    }

    /**
     * Nested class for spread object in the new JSON format.
     * Example: "spread": { "price": 1.2500, "percent": 0.826 }
     */
    public static class Spread {
        @SerializedName("price")
        private double price;

        @SerializedName("percent")
        private double percent; // percentage value, e.g. 0.826 => 0.826%

        public Spread() {
        }

        public Spread(double price, double percent) {
            this.price = price;
            this.percent = percent;
        }

        public double getPrice() {
            return price;
        }

        public void setPrice(double price) {
            this.price = price;
        }

        public double getPercent() {
            return percent;
        }

        public void setPercent(double percent) {
            this.percent = percent;
        }

        @Override
        public String toString() {
            return String.format("Spread{price=%.4f, percent=%.4f}", price, percent);
        }
    }

    // Constructors
    public BboUpdate() {
    }

    public BboUpdate(String symbol, PriceLevel bid, PriceLevel ask, double spread, long timestamp) {
        this.symbol = symbol;
        this.bid = bid;
        this.ask = ask;
        // Backwards-compatible constructor: create Spread object and compute percent
        this.spread = new Spread(spread, computeSpreadPercent(spread, bid, ask));
        this.timestamp = timestamp;
        calculateSpreadPct();
    }

    public BboUpdate(String symbol, PriceLevel bid, PriceLevel ask, Spread spreadObj, long timestamp) {
        this.symbol = symbol;
        this.bid = bid;
        this.ask = ask;
        this.spread = spreadObj;
        this.timestamp = timestamp;
        calculateSpreadPct();
    }

    // Getters and Setters
    public String getSymbol() {
        return symbol;
    }

    public void setSymbol(String symbol) {
        this.symbol = symbol;
    }

    public PriceLevel getBid() {
        return bid;
    }

    public void setBid(PriceLevel bid) {
        this.bid = bid;
    }

    public PriceLevel getAsk() {
        return ask;
    }

    public void setAsk(PriceLevel ask) {
        this.ask = ask;
    }

    /**
     * Returns spread price (dollars).
     */
    public double getSpread() {
        return spread != null ? spread.getPrice() : 0.0;
    }

    public void setSpread(double spreadPrice) {
        if (this.spread == null)
            this.spread = new Spread();
        this.spread.setPrice(spreadPrice);
        // attempt to compute percent if bid/ask present
        this.spread.setPercent(computeSpreadPercent(spreadPrice, bid, ask));
        calculateSpreadPct();
    }

    public Spread getSpreadObject() {
        return spread;
    }

    public void setSpreadObject(Spread spread) {
        this.spread = spread;
        calculateSpreadPct();
    }

    public long getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(long timestamp) {
        this.timestamp = timestamp;
    }

    public double getSpreadPct() {
        return spreadPct;
    }

    /**
     * Calculate spread percentage based on mid-price.
     * SpreadPct = (Spread / Mid Price) * 100
     */
    private void calculateSpreadPct() {
        // Prefer provided percent from spread object if available
        if (spread != null && Double.compare(spread.getPercent(), 0.0) != 0) {
            this.spreadPct = spread.getPercent();
            return;
        }

        if (bid != null && ask != null && bid.getPrice() > 0 && spread != null) {
            double midPrice = (bid.getPrice() + ask.getPrice()) / 2.0;
            this.spreadPct = (spread.getPrice() / midPrice) * 100.0;
        } else {
            this.spreadPct = 0.0;
        }
    }

    private double computeSpreadPercent(double spreadPrice, PriceLevel bid, PriceLevel ask) {
        if (bid != null && ask != null) {
            double mid = (bid.getPrice() + ask.getPrice()) / 2.0;
            if (mid > 0)
                return (spreadPrice / mid) * 100.0;
        }
        return 0.0;
    }

    /**
     * Get the mid price (average of bid and ask).
     */
    public double getMidPrice() {
        if (bid != null && ask != null) {
            return (bid.getPrice() + ask.getPrice()) / 2.0;
        }
        return 0.0;
    }

    /**
     * Get the total volume (bid shares + ask shares).
     */
    public long getTotalVolume() {
        long total = 0;
        if (bid != null) {
            total += bid.getShares();
        }
        if (ask != null) {
            total += ask.getShares();
        }
        return total;
    }

    @Override
    public String toString() {
        return String.format(
                "BboUpdate{symbol='%s', bid=%s, ask=%s, spread=%s, spreadPct=%.2f%%, timestamp=%d}",
                symbol, bid, ask, spread != null ? spread.toString() : "null", spreadPct, timestamp);
    }

}
