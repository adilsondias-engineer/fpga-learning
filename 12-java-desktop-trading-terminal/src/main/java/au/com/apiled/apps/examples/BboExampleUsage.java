package au.com.apiled.apps.examples;

import com.google.gson.Gson;
import au.com.apiled.apps.data.BboDataStore;
import au.com.apiled.apps.dto.BboUpdate;
import au.com.apiled.apps.network.BboTcpClient;

/**
 * Example usage of BBO system components.
 * Demonstrates:
 * 1. Creating BBO objects from JSON
 * 2. Storing and querying BBO data
 * 3. Connecting to TCP gateway
 * 4. Processing events
 *
 * This is NOT the main application - see BboTradingTerminal.java for the UI.
 */
public class BboExampleUsage {

    /**
     * Example 1: Create BBO from JSON string
     */
    public static void example1_JsonParsing() {
        System.out.println("\n=== Example 1: JSON Parsing ===");

        String jsonBbo = "{\n" +
                "  \"type\": \"bbo\",\n" +
                "  \"symbol\": \"AAPL\",\n" +
                "  \"timestamp\": 1699824000123456789,\n" +
                "  \"bid\": {\"price\": 150.75, \"shares\": 100},\n" +
                "  \"ask\": {\"price\": 151.50, \"shares\": 150},\n" +
                "  \"spread\": {\"price\": 0.75, \"percent\": 0.4967}\n" +
                "}";

        Gson gson = new Gson();
        BboUpdate bbo = gson.fromJson(jsonBbo, BboUpdate.class);

        System.out.println("Parsed BBO: " + bbo);
        System.out.println("Mid Price: $" + String.format("%.2f", bbo.getMidPrice()));
        System.out.println("Spread %: " + String.format("%.2f%%", bbo.getSpreadPct()));
        System.out.println("Total Volume: " + bbo.getTotalVolume() + " shares");
    }

    /**
     * Example 2: Using BboDataStore
     */
    public static void example2_DataStore() {
        System.out.println("\n=== Example 2: Data Store ===");

        BboDataStore store = new BboDataStore();

        // Create and store BBO updates
        BboUpdate.PriceLevel bid = new BboUpdate.PriceLevel(150.75, 1000);
        BboUpdate.PriceLevel ask = new BboUpdate.PriceLevel(151.50, 2000);
        BboUpdate bbo1 = new BboUpdate("AAPL", bid, ask, 0.75, System.nanoTime());

        bid = new BboUpdate.PriceLevel(225.30, 500);
        ask = new BboUpdate.PriceLevel(226.10, 800);
        BboUpdate bbo2 = new BboUpdate("TSLA", bid, ask, 0.80, System.nanoTime());

        store.updateBbo(bbo1);
        store.updateBbo(bbo2);

        // Query data
        System.out.println("Available symbols: " + store.getAvailableSymbols());
        System.out.println("Total symbols: " + store.size());

        BboUpdate currentAapl = store.getCurrentBbo("AAPL");
        System.out.println("Current AAPL: " + currentAapl);

        // Get statistics
        BboDataStore.SpreadStatistics stats = store.getSpreadStatistics();
        System.out.println("Spread Statistics: " + stats);
    }

    /**
     * Example 3: Listening to data store events
     */
    public static void example3_DataStoreListening() {
        System.out.println("\n=== Example 3: Data Store Listening ===");

        BboDataStore store = new BboDataStore();

        // Register listener
        store.addListener(new BboDataStore.BboDataStoreListener() {
            @Override
            public void onBboUpdated(BboUpdate bbo) {
                System.out.println("  [Listener] BBO Updated: " + bbo.getSymbol() +
                        " Bid=" + String.format("%.2f", bbo.getBid().getPrice()) +
                        " Ask=" + String.format("%.2f", bbo.getAsk().getPrice()));
            }

            @Override
            public void onBboHistoryUpdated(String symbol, java.util.LinkedList<BboUpdate> history) {
                System.out.println("  [Listener] History updated for " + symbol +
                        ", size=" + history.size());
            }
        });

        // Trigger events
        BboUpdate.PriceLevel bid = new BboUpdate.PriceLevel(150.75, 100);
        BboUpdate.PriceLevel ask = new BboUpdate.PriceLevel(151.50, 150);
        BboUpdate bbo = new BboUpdate("AAPL", bid, ask, 0.75, System.nanoTime());
        store.updateBbo(bbo);
    }

    /**
     * Example 4: TCP Client setup (non-blocking)
     */
    public static void example4_TcpClientSetup() {
        System.out.println("\n=== Example 4: TCP Client Setup ===");

        // Create client (doesn't connect yet)
        BboTcpClient client = new BboTcpClient("localhost", 9999);

        // Register listener before connecting
        client.addListener(new BboTcpClient.BboUpdateListener() {
            @Override
            public void onBboUpdate(BboUpdate bbo) {
                System.out.println("  [TCP Listener] Received BBO: " + bbo.getSymbol() +
                        " | Bid=" + String.format("%.2f", bbo.getBid().getPrice()) +
                        " | Ask=" + String.format("%.2f", bbo.getAsk().getPrice()));
            }

            @Override
            public void onConnectionStateChanged(boolean connected) {
                System.out.println("  [TCP Listener] Connection: " + (connected ? "CONNECTED" : "DISCONNECTED"));
            }

            @Override
            public void onError(String errorMessage) {
                System.out.println("  [TCP Listener] Error: " + errorMessage);
            }
        });

        System.out.println("Client configured for: " + client.getHost() + ":" + client.getPort());
        System.out.println("Ready to call client.connect()");

        // Note: Don't actually connect in this example to avoid blocking
        // In real usage: client.connect();
        // Thread.sleep(10000); // Let it receive data
        // client.disconnect();
    }

    /**
     * Example 5: Data flow integration
     */
    public static void example5_IntegratedFlow() {
        System.out.println("\n=== Example 5: Integrated Flow (Data Store + Events) ===");

        BboDataStore dataStore = new BboDataStore();

        // Simulate TCP client behavior
        BboTcpClient.BboUpdateListener tcpListener = new BboTcpClient.BboUpdateListener() {
            @Override
            public void onBboUpdate(BboUpdate bbo) {
                // Store received BBO in data store
                dataStore.updateBbo(bbo);
            }

            @Override
            public void onConnectionStateChanged(boolean connected) {
                System.out.println("Connection state: " + connected);
            }

            @Override
            public void onError(String errorMessage) {
                System.err.println("Error: " + errorMessage);
            }
        };

        // Listen to data store updates (would update UI in real app)
        dataStore.addListener(new BboDataStore.BboDataStoreListener() {
            @Override
            public void onBboUpdated(BboUpdate bbo) {
                System.out.println("  [UI Update] Table: " + bbo.getSymbol() +
                        " | Spread: " + String.format("%.4f", bbo.getSpread()));
            }

            @Override
            public void onBboHistoryUpdated(String symbol, java.util.LinkedList<BboUpdate> history) {
                System.out.println("  [UI Update] Chart: " + symbol + " | Points: " + history.size());
            }
        });

        // Simulate receiving BBO from gateway
        System.out.println("Simulating BBO reception from gateway:");
        BboUpdate.PriceLevel bid = new BboUpdate.PriceLevel(100.00, 500);
        BboUpdate.PriceLevel ask = new BboUpdate.PriceLevel(102.00, 800);
        BboUpdate bbo = new BboUpdate("TEST", bid, ask, 2.00, System.nanoTime());

        // This triggers the chain: TCP → DataStore → Listeners → UI
        tcpListener.onBboUpdate(bbo);
    }

    /**
     * Main - run all examples
     */
    public static void main(String[] args) {
        System.out.println("╔════════════════════════════════════════════════════════════╗");
        System.out.println("║         BBO System - Usage Examples                        ║");
        System.out.println("║         Java 21 + JavaFX Trading Terminal                  ║");
        System.out.println("╚════════════════════════════════════════════════════════════╝");

        example1_JsonParsing();
        example2_DataStore();
        example3_DataStoreListening();
        example4_TcpClientSetup();
        example5_IntegratedFlow();

        System.out.println("\n" +
                "╔════════════════════════════════════════════════════════════╗\n" +
                "║  To run the full JavaFX application:                       ║\n" +
                "║                                                            ║\n" +
                "║  mvn exec:java -Dexec.mainClass=                          ║\n" +
                "║    \"au.com.apiled.apps.ui.BboTradingTerminal\"  ║\n" +
                "║                                                            ║\n" +
                "╚════════════════════════════════════════════════════════════╝\n");

        // mvn exec:java
        // -Dexec.mainClass="au.com.apiled.apps.ui.BboTradingTerminal"
    }
}
