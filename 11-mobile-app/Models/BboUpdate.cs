using System.Text.Json.Serialization;

namespace _11_mobile_app.Models
{
    /// <summary>
    /// BBO (Best Bid/Offer) update from FPGA trading system via Kafka
    /// Matches JSON format from C++ gateway
    /// </summary>
    public class BboUpdate
    {
        [JsonPropertyName("type")]
        public string Type { get; set; } = "bbo";

        [JsonPropertyName("symbol")]
        public string Symbol { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public long Timestamp { get; set; }

        [JsonPropertyName("bid")]
        public PriceLevel Bid { get; set; } = new();

        [JsonPropertyName("ask")]
        public PriceLevel Ask { get; set; } = new();

        [JsonPropertyName("spread")]
        public SpreadInfo Spread { get; set; } = new();

        /// <summary>
        /// Mid price (average of bid and ask)
        /// </summary>
        public double MidPrice => (Bid.Price + Ask.Price) / 2.0;

        /// <summary>
        /// Total volume (bid + ask shares)
        /// </summary>
        public int TotalVolume => Bid.Shares + Ask.Shares;

        /// <summary>
        /// Last update time (local)
        /// </summary>
        public DateTime LastUpdate { get; set; } = DateTime.Now;

        /// <summary>
        /// Formatted timestamp string
        /// </summary>
        public string TimestampString => LastUpdate.ToString("HH:mm:ss.fff");
    }

    public class PriceLevel
    {
        [JsonPropertyName("price")]
        public double Price { get; set; }

        [JsonPropertyName("shares")]
        public int Shares { get; set; }
    }

    public class SpreadInfo
    {
        [JsonPropertyName("price")]
        public double Price { get; set; }

        [JsonPropertyName("percent")]
        public double Percent { get; set; }
    }
}
