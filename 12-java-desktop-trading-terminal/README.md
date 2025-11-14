# BBO Trading Terminal - Java Implementation

## Overview

A real-time Best Bid Offer (BBO) market data visualization and management system written in **Java 21** with **JavaFX**. This application connects to a TCP gateway (default: `localhost:9999`) to receive JSON-formatted BBO updates and displays them in an interactive UI with real-time charting.

**Architecture Alignment:** Project 10 of the FPGA Trading System

- Receives JSON BBO streams from the C++ Order Gateway (Project 9)
- Parses market data into Java DTOs
- Visualizes bid-ask spreads with JavaFX charts and tables

---

## Project Structure

```
src/main/java/au/com/apiled/apps/
├── dto/
│   └── BboUpdate.java              # Data Transfer Object for BBO updates
├── network/
│   └── BboTcpClient.java           # TCP client for gateway connection
├── data/
│   └── BboDataStore.java           # Thread-safe data management
└── ui/
    └── BboTradingTerminal.java     # Main JavaFX application

tests/main/java/au/com/apiled/apps/
└── dto/
    └── BboUpdateTest.java          # Unit tests for DTO parsing

pom.xml                              # Maven build configuration (Java 21)
```

---

## Classes & Components

### 1. **BboUpdate.java** (DTO)

Data Transfer Object representing a single BBO market snapshot.

**JSON Format (TCP Input):**

```json
{
  "symbol": "AAPL",
  "bid": {
    "price": 150.75,
    "shares": 100
  },
  "ask": {
    "price": 151.5,
    "shares": 150
  },
  "spread": 0.75,
  "timestamp": 1699824000123456789
}
```

**Key Methods:**

- `getMidPrice()` - Average of bid and ask prices
- `getSpreadPct()` - Spread as percentage of mid-price
- `getTotalVolume()` - Combined bid + ask shares

**Nested Class:**

- `PriceLevel` - Holds price and shares for bid/ask levels

---

### 2. **BboTcpClient.java** (Network)

Connects to TCP gateway on configurable port (default 9999) and listens for JSON BBO updates.

**Constructor:**

```java
// Default: localhost:9999
BboTcpClient client = new BboTcpClient();

// Custom host/port
BboTcpClient client = new BboTcpClient("192.168.0.100", 9999);
```

**Key Methods:**

- `connect()` - Establish TCP connection (starts listener thread)
- `disconnect()` - Gracefully close connection
- `addListener(BboUpdateListener)` - Register for BBO events
- `isConnected()` - Check connection status

**BboUpdateListener Events:**

```java
interface BboUpdateListener {
    void onBboUpdate(BboUpdate bbo);              // New BBO received
    void onConnectionStateChanged(boolean connected);
    void onError(String errorMessage);
}
```

**Threading:**

- Listener runs in background daemon thread
- Thread-safe: uses CopyOnWriteArrayList for listeners
- Non-blocking: doesn't freeze UI during network operations

---

### 3. **BboDataStore.java** (Data Management)

Central thread-safe store for current and historical BBO data.

**Key Methods:**

- `updateBbo(BboUpdate)` - Store current BBO and add to history
- `getCurrentBbo(String symbol)` - Get latest for symbol
- `getAllCurrentBbos()` - Get all current BBOs
- `getHistory(String symbol)` - Get historical data (for charting)
- `getAvailableSymbols()` - Get all symbols with data
- `getSpreadStatistics()` - Aggregate spread metrics

**Features:**

- Automatic history trimming (max 1000 points per symbol)
- ConcurrentHashMap for thread safety
- Observable listener pattern for UI updates

**SpreadStatistics Record:**

```java
record SpreadStatistics(
    double minSpread,
    double maxSpread,
    double avgSpreadPct,
    int symbolCount
)
```

---

### 4. **BboTradingTerminal.java** (JavaFX UI)

Main application with real-time BBO table, spread chart, and connection controls.

**UI Components:**

**Control Panel:**

- Host/Port input fields (default: localhost:9999)
- Connect/Disconnect buttons
- Connection status indicator (● Connected/Disconnected)

**BBO Table:**
Shows all symbols with current prices:

- Symbol
- Bid Price / Bid Shares
- Ask Price / Ask Shares
- Spread ($)
- Spread (%)

**Spread Chart:**

- Line chart showing spread over time
- One series per symbol
- Auto-scales, non-animated for performance

**Status Bar:**

- Active symbol count
- Spread statistics (min, max, average %)

**Key Methods:**

- `start(Stage)` - Launch application
- `createControlPanel()` - Build connection controls
- `createBboTable()` - Build market data table
- `createSpreadChart()` - Build time-series chart
- `handleConnect()` - Validate and connect to gateway
- `updateChart(symbol, history)` - Refresh chart with data

---

## Building & Running

### Prerequisites

- **Java 21 LTS** (Oracle JDK or equivalent)
- **Maven 3.9.x**
- **Linux/macOS/Windows**

### Build from Source

```bash
# Compile project
mvn clean compile

# Run unit tests (6 tests included)
mvn test

# Build executable JAR
mvn clean package

# Run with dependencies
java -jar target/desktoptradingterminal-1.0.0-SNAPSHOT-jar-with-dependencies.jar
```

### Run Directly

```bash
# Compile and run
mvn clean compile exec:java -Dexec.mainClass="au.com.apiled.apps.ui.BboTradingTerminal"
```

---

## Dependencies

| Dependency     | Version  | Purpose                               |
| -------------- | -------- | ------------------------------------- |
| JavaFX         | 21       | UI framework (controls, charts, fxml) |
| Gson           | 2.10.1   | JSON parsing                          |
| JUnit Jupiter  | 5.9.2    | Unit testing framework                |
| Mockito        | 5.2.0    | Test mocking                          |
| Maven Surefire | 3.0.0-M9 | Test runner                           |

**Java Version:** 21 (configured in pom.xml)

- `<java.version>21</java.version>`
- maven-compiler-plugin 3.11.0 with `<release>21</release>`

---

## Usage Guide

### 1. Start the Application

```bash
mvn exec:java -Dexec.mainClass="au.com.apiled.apps.ui.BboTradingTerminal"
```

A JavaFX window will open with the BBO Trading Terminal.

### 2. Configure Gateway Connection

Default values:

- **Host:** localhost
- **Port:** 9999

To connect to a remote gateway:

1. Enter hostname/IP in "Host" field
2. Enter port number in "Port" field
3. Click "Connect"

### 3. Monitor BBO Updates

Once connected:

- **Table** updates in real-time with bid/ask prices
- **Chart** displays spread history (last 50 data points per symbol)
- **Status bar** shows symbol count and spread statistics
- Color-coded by bid (green), ask (red), spread (yellow)

### 4. Disconnect

Click "Disconnect" to gracefully close the TCP connection.

---

## Testing

All tests pass with Java 21:

```bash
mvn test
```

**Test Coverage:**

1. `testJsonDeserialization()` - Parse JSON BBO
2. `testMidPriceCalculation()` - Verify mid-price computation
3. `testSpreadPercentageCalculation()` - Verify spread %
4. `testTotalVolumeCalculation()` - Aggregate bid+ask shares
5. `testJsonSerialization()` - Convert BBO to JSON
6. `testToString()` - String representation

---

## Data Flow

```
TCP Gateway (9999)
         ↓
  BboTcpClient (listener thread)
         ↓
  JSON → Gson.fromJson()
         ↓
   BboUpdate DTO
         ↓
  BboDataStore (thread-safe)
         ↓
  JavaFX UI (Platform.runLater)
         ├→ BboTable (refresh)
         └→ LineChart (update series)
```

---

## Architecture Notes

### Thread Safety

- **Network I/O:** Background daemon thread (non-blocking)
- **Data Store:** ConcurrentHashMap for thread-safe access
- **UI Updates:** Platform.runLater() for thread confinement
- **Event Listeners:** CopyOnWriteArrayList for concurrent modification safety

### Performance Considerations

- **History Buffer:** Automatic trimming at 1000 points per symbol
- **Chart Rendering:** Non-animated for low CPU overhead
- **TCP Read:** Non-blocking with buffered streams
- **Event Processing:** ~1-5 µs per BBO update (from gateway spec)

### Error Handling

- Invalid JSON logged with warning (doesn't crash app)
- Connection errors trigger UI alerts
- Graceful shutdown on application close
- Configurable reconnection via manual "Connect" button

---

## Integration with C++ Gateway (Project 9)

### Multi-Protocol Architecture

The C++ Gateway (Project 9) distributes BBO data via **three protocols simultaneously**:

```
FPGA Order Book → C++ Gateway ─┬→ TCP (localhost:9999) → Java Desktop (This App)
                               ├→ MQTT (192.168.0.2:1883) → ESP32 IoT + Mobile App
                               └→ Kafka (192.168.0.203:9092) → (Future Analytics)
```

**Why TCP for Desktop?**

**TCP Advantages for Desktop Applications:**
- Low latency (< 10ms localhost)
- Simple request/response model
- Direct connection (no broker overhead)
- Persistent connection for streaming data
- Native Java socket support

❌ **MQTT/Kafka NOT Ideal for Desktop:**
- MQTT: Designed for IoT/mobile (handles unreliable networks, QoS overhead)
- Kafka: Designed for backend data pipelines (consumer groups, offset management)
- Both add unnecessary broker latency for localhost desktop apps

### JSON Format

This Java application expects JSON formatted as:

```json
{
  "symbol": "SYMBOL_NAME",
  "bid": {"price": BID_PRICE, "shares": BID_SHARES},
  "ask": {"price": ASK_PRICE, "shares": ASK_SHARES},
  "spread": SPREAD_DOLLARS,
  "timestamp": TIMESTAMP_NS
}
```

**One JSON object per line** (newline-delimited).

---

## Future Enhancements

1. **Order Entry** - Add form to submit orders back to gateway
2. **Risk Checks** - Fat finger prevention, position limits
3. **Persistence** - Chronicle Queue for tick-by-tick replay
4. **MQTT Support** - Subscribe to MQTT feed as alternative to TCP
5. **Export Data** - CSV export for backtesting
6. **Alerts** - Sound/visual alerts for spread thresholds
7. **Multi-Gateway** - Support multiple gateways simultaneously

---

## Troubleshooting

### Connection Failed

```
TCP Error: Connection refused: connect
```

**Solution:** Ensure C++ gateway is running on the configured host:port.

### Invalid JSON Errors

```
[WARNING] Invalid JSON received: ...
```

**Cause:** Malformed JSON from gateway.
**Solution:** Verify gateway output format matches spec above.

### Memory Usage

Chart history buffers can grow. Monitor with:

```java
BboDataStore.SpreadStatistics stats = dataStore.getSpreadStatistics();
System.out.println(stats);
```

---

## Build Information

- **Build Tool:** Maven 3.9.x
- **Java Target:** 21 LTS
- **Execution:** `maven-compiler-plugin` 3.11.0 with release flag
- **Testing:** Maven Surefire 3.0.0-M9
- **Source Layout:** `src/main/java`, `tests/main/java` (non-standard but configured in pom.xml)

---

## License & Credits

**Project:** FPGA Trading System - Java Desktop Terminal (Project 10)
**Architecture:** See `SYSTEM_ARCHITECTURE.md` for full system design
**Date:** November 2025
**Status:** Functional (Build SUCCESS, All Tests PASS)

---

## Contact & Support

For issues or questions about the Java implementation, refer to the system architecture documentation or the inline code comments in each class.

**Key Files for Reference:**

- `SYSTEM_ARCHITECTURE.md` - Full system design
- `pom.xml` - Build configuration and dependencies
- `src/main/java/**/*.java` - Source code with inline documentation
