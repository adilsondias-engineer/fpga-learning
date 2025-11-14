package au.com.apiled.apps.dto;

import com.google.gson.Gson;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

/**
 * Unit tests for BboUpdate DTO class.
 */
public class BboUpdateTest {
    private Gson gson;

    @BeforeEach
    public void setUp() {
        gson = new Gson();
    }

    /**
     * Test parsing a valid JSON BBO string.
     */
    @Test
    public void testJsonDeserialization() {
        String json = "{\n" +
                "  \"type\": \"bbo\",\n" +
                "  \"symbol\": \"AAPL\",\n" +
                "  \"timestamp\": 1699824000123456789,\n" +
                "  \"bid\": {\n" +
                "    \"price\": 150.75,\n" +
                "    \"shares\": 100\n" +
                "  },\n" +
                "  \"ask\": {\n" +
                "    \"price\": 151.50,\n" +
                "    \"shares\": 150\n" +
                "  },\n" +
                "  \"spread\": {\"price\": 0.75, \"percent\": 0.4967}\n" +
                "}";

        BboUpdate bbo = gson.fromJson(json, BboUpdate.class);

        assertNotNull(bbo);
        assertEquals("AAPL", bbo.getSymbol());
        assertEquals(150.75, bbo.getBid().getPrice());
        assertEquals(100, bbo.getBid().getShares());
        assertEquals(151.50, bbo.getAsk().getPrice());
        assertEquals(150, bbo.getAsk().getShares());
        assertEquals(0.75, bbo.getSpread());
        assertEquals(1699824000123456789L, bbo.getTimestamp());
    }

    /**
     * Test mid-price calculation.
     */
    @Test
    public void testMidPriceCalculation() {
        BboUpdate.PriceLevel bid = new BboUpdate.PriceLevel(150.75, 100);
        BboUpdate.PriceLevel ask = new BboUpdate.PriceLevel(151.50, 150);
        BboUpdate bbo = new BboUpdate("AAPL", bid, ask, 0.75, System.currentTimeMillis());

        double expectedMidPrice = (150.75 + 151.50) / 2.0;
        assertEquals(expectedMidPrice, bbo.getMidPrice(), 0.0001);
    }

    /**
     * Test spread percentage calculation.
     */
    @Test
    public void testSpreadPercentageCalculation() {
        BboUpdate.PriceLevel bid = new BboUpdate.PriceLevel(100.0, 100);
        BboUpdate.PriceLevel ask = new BboUpdate.PriceLevel(102.0, 150);
        BboUpdate bbo = new BboUpdate("TEST", bid, ask, 2.0, System.currentTimeMillis());

        // SpreadPct = (Spread / MidPrice) * 100 = (2.0 / 101.0) * 100 ≈ 1.98%
        double expectedSpreadPct = (2.0 / 101.0) * 100;
        assertEquals(expectedSpreadPct, bbo.getSpreadPct(), 0.01);
    }

    /**
     * Test total volume calculation.
     */
    @Test
    public void testTotalVolumeCalculation() {
        BboUpdate.PriceLevel bid = new BboUpdate.PriceLevel(150.75, 1000);
        BboUpdate.PriceLevel ask = new BboUpdate.PriceLevel(151.50, 2000);
        BboUpdate bbo = new BboUpdate("AAPL", bid, ask, 0.75, System.currentTimeMillis());

        assertEquals(3000, bbo.getTotalVolume());
    }

    /**
     * Test JSON serialization (convert back to JSON).
     */
    @Test
    public void testJsonSerialization() {
        BboUpdate.PriceLevel bid = new BboUpdate.PriceLevel(150.75, 100);
        BboUpdate.PriceLevel ask = new BboUpdate.PriceLevel(151.50, 150);
        BboUpdate bbo = new BboUpdate("AAPL", bid, ask, 0.75, 1699824000123456789L);

        String json = gson.toJson(bbo);
        assertNotNull(json);
        assertTrue(json.contains("AAPL"));
        assertTrue(json.contains("150.75") || json.contains("150.75"));
        assertTrue(json.contains("151.5"));
    }

    /**
     * Test toString output.
     */
    @Test
    public void testToString() {
        BboUpdate.PriceLevel bid = new BboUpdate.PriceLevel(150.75, 100);
        BboUpdate.PriceLevel ask = new BboUpdate.PriceLevel(151.50, 150);
        BboUpdate bbo = new BboUpdate("AAPL", bid, ask, 0.75, System.currentTimeMillis());

        String str = bbo.toString();
        assertTrue(str.contains("AAPL"));
        assertTrue(str.contains("spread"));
    }
}
