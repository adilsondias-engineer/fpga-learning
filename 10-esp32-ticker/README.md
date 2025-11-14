# Project 10: ESP32 TFT Ticker Display

**IoT Market Data Display for FPGA Trading System**

Real-time BBO ticker display on ESP32 with TFT LCD, consuming market data from MQTT broker.

---

## Overview

This project demonstrates the **IoT tier** of the FPGA trading system architecture. The ESP32 subscribes to the MQTT broker and displays live Best Bid/Offer (BBO) data on a color TFT display.

**Data Flow:**
```
FPGA Order Book → C++ Gateway → MQTT Broker → ESP32 Display
                              → MQTT Broker → Mobile App (.NET MAUI)
                              → Kafka → (Future Analytics)
```

**Why MQTT for IoT?**

✅ **Perfect Protocol for ESP32:**
- Lightweight (minimal RAM/flash usage)
- Low power consumption (critical for battery operation)
- Handles unreliable WiFi gracefully
- Native ESP32 library support (PubSubClient)
- QoS levels for reliability/performance tradeoff

❌ **Kafka NOT Suitable for IoT:**
- Heavy protocol overhead (requires persistent TCP)
- High memory footprint (incompatible with ESP32's 520KB RAM)
- No native ESP32 libraries
- Designed for backend services, not edge devices

---

**Development Environment: Arduino IDE vs ESP-IDF**

This project uses **Arduino IDE** instead of VSCode with Espressif IDF (C/C++) for the following reasons:

✅ **Arduino IDE - Perfect for This Simple Project:**
- **Simplicity:** Simple ticker display doesn't require ESP-IDF advanced features
- **Library Ecosystem:** TFT_eSPI, PubSubClient, ArduinoJson work out-of-the-box
- **Quick Setup:** Install IDE + boards + libraries in < 10 minutes
- **Demonstration Focus:** Project demonstrates MQTT protocol usage, not ESP-IDF capabilities
- **Lower Barrier:** Easier for others to reproduce and learn from

❌ **ESP-IDF Would Be Overkill:**
- **Complexity:** CMake build system, FreeRTOS task management not needed here
- **Setup Time:** VSCode + ESP-IDF extension + toolchain > 1 hour setup
- **No Advanced Features Used:** Not using BLE, WiFi mesh, OTA updates, or custom partitions
- **Library Compatibility:** Arduino libraries simpler than ESP-IDF components

**When to Use ESP-IDF Instead:**
- Production firmware requiring OTA updates
- Custom partition schemes or flash management
- Advanced WiFi features (mesh networking, WiFi provisioning)
- Multi-core FreeRTOS task coordination
- Bluetooth Low Energy (BLE) integration
- Custom hardware drivers (not available in Arduino)

For this demonstration project, Arduino IDE provides the perfect balance of simplicity and functionality.

---

## Hardware Requirements

### Components

1. **ESP32 Development Board**
   - ESP32-WROOM or ESP32-Wrover
   - USB-C or Micro-USB for programming

2. **1.8" TFT LCD Display**
   - Driver: ST7735 or ILI9341
   - Resolution: 128x160 pixels
   - Interface: SPI
   - Voltage: 3.3V

3. **Breadboard and Jumper Wires**
   - For prototyping connections

### Wiring Diagram

```
ESP32 Pin    →    TFT Display Pin
---------         ---------------
3.3V        →     VCC
GND         →     GND
GPIO18      →     SCK/SCL (SPI Clock)
GPIO23      →     MOSI/SDA (SPI Data)
GPIO15      →     CS (Chip Select)
GPIO2       →     DC/RS (Data/Command)
GPIO4       →     RST (Reset)
```

**Optional:**
- Connect TFT `BL` (Backlight) to 3.3V for always-on, or to a GPIO for PWM brightness control

---

## Software Requirements

### Arduino IDE Setup

1. **Install Arduino IDE** (version 2.x recommended)
   - Download from: https://www.arduino.cc/en/software

2. **Add ESP32 Board Support**
   - File → Preferences → Additional Board Manager URLs
   - Add: `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   - Tools → Board → Boards Manager → Search "ESP32" → Install

3. **Install Libraries** (via Library Manager: Tools → Manage Libraries)
   - **TFT_eSPI** by Bodmer (for TFT display control)
   - **PubSubClient** by Nick O'Leary (for MQTT)
   - **ArduinoJson** by Benoit Blanchon (for JSON parsing)

### TFT_eSPI Configuration

**Important:** Configure the TFT_eSPI library for your hardware.

1. Locate library folder:
   - Windows: `Documents\Arduino\libraries\TFT_eSPI\`
   - Mac: `~/Documents/Arduino/libraries/TFT_eSPI/`
   - Linux: `~/Arduino/libraries/TFT_eSPI/`

2. Edit `User_Setup.h`:

```cpp
// Driver selection
#define ST7735_DRIVER      // For ST7735 displays
// OR
// #define ILI9341_DRIVER  // For ILI9341 displays

// Display size
#define TFT_WIDTH  128
#define TFT_HEIGHT 160

// Pin definitions (match wiring above)
#define TFT_CS     15
#define TFT_DC     2
#define TFT_RST    4
#define TFT_MOSI   23
#define TFT_SCLK   18

// SPI frequency
#define SPI_FREQUENCY  27000000  // 27MHz
```

3. Save and restart Arduino IDE

---

## Configuration

Edit `esp32_ticker.ino` with your network settings:

```cpp
// WiFi credentials
const char* WIFI_SSID = "YOUR_SSID";
const char* WIFI_PASSWORD = "YOUR_PASSWORD";

// MQTT broker (Mosquitto)
const char* MQTT_SERVER = "192.168.0.2";    // MQTT broker IP
const char* MQTT_USER = "trading";          // MQTT username
const char* MQTT_PASS = "trading123";       // MQTT password
const int MQTT_PORT = 1883;
const char* MQTT_TOPIC = "bbo_messages";    // Topic from C++ gateway
```

**MQTT Broker Configuration:**
- **Broker:** Mosquitto @ 192.168.0.2:1883
- **Authentication:** trading / trading123
- **Topic:** `bbo_messages` (single topic with all symbols)
- **Protocol:** MQTT v3.1.1 (ESP32 compatible)
```

---

## Building and Uploading

1. **Open Project**
   - File → Open → Select `esp32_ticker.ino`

2. **Select Board**
   - Tools → Board → ESP32 Arduino → ESP32 Dev Module (or your specific board)

3. **Configure Upload Settings**
   - Tools → Upload Speed → 921600
   - Tools → Flash Frequency → 80MHz
   - Tools → Partition Scheme → Default 4MB

4. **Connect ESP32**
   - Connect via USB cable
   - Tools → Port → Select COM port (Windows) or /dev/ttyUSB0 (Linux)

5. **Upload**
   - Click Upload button (→)
   - Wait for compilation and upload (~30 seconds)

6. **Monitor Serial Output**
   - Tools → Serial Monitor
   - Set baud rate to 115200
   - Watch for WiFi and MQTT connection status

---

## Display Layout

```
┌────────────────────────┐
│   AAPL                 │  ← Symbol (large, white)
├────────────────────────┤
│ BID:                   │  ← Label (green)
│ $150.25    (100)       │  ← Price + Shares
│                        │
│ ASK:                   │  ← Label (red)
│ $150.75    (150)       │  ← Price + Shares
├────────────────────────┤
│ SPREAD: $0.50 (0.33%)  │  ← Spread (yellow)
│ Updated: 5s ago        │  ← Timestamp (gray)
└────────────────────────┘
```

**Color Coding:**
- **White**: Symbol name
- **Green**: Bid price/shares
- **Red**: Ask price/shares
- **Yellow**: Spread
- **Gray**: Status/timestamp

---

## Testing

### 1. Test WiFi Connection

After upload, check Serial Monitor:
```
Connecting to WiFi: YOUR_SSID
.....
WiFi connected!
IP address: 192.168.1.123
```

### 2. Test MQTT Connection

Serial Monitor should show:
```
Connecting to MQTT broker: 192.168.1.100
MQTT connected!
Subscribed to: fpga/bbo/#
```

### 3. Test Data Display

With the FPGA system running and sending orders:
```
[AAPL] Bid: $150.25 (100) | Ask: $150.75 (150) | Spread: $0.50
```

TFT display should update in real-time showing current BBO.

---

## Troubleshooting

### WiFi Connection Fails

**Symptom:** "WiFi FAILED!" on display

**Solutions:**
- Check SSID and password in code
- Verify 2.4GHz WiFi (ESP32 doesn't support 5GHz)
- Check WiFi signal strength
- Try static IP instead of DHCP

### MQTT Connection Fails

**Symptom:** "MQTT FAILED!" on display, error code in Serial Monitor

**Error Codes:**
- `-2`: Network connection failed (check IP address)
- `-3`: Network connection broken
- `-4`: MQTT connection refused (check broker is running)

**Solutions:**
```bash
# Check if MQTT broker is running on Raspberry Pi:
sudo systemctl status mosquitto

# Start if not running:
sudo systemctl start mosquitto

# Test with mosquitto_sub:
mosquitto_sub -h localhost -t "fpga/bbo/#" -v
```

### Display Not Working

**Symptom:** Blank screen or garbled output

**Solutions:**
1. Verify wiring matches configuration
2. Check TFT_eSPI `User_Setup.h` driver selection
3. Try different SPI frequency (lower = more stable)
4. Test with TFT_eSPI example sketches first
5. Measure 3.3V on VCC pin with multimeter

### Display Flickers

**Symptom:** Screen updates cause visible flashing

**Solution:** Enable double-buffering (requires more RAM):
```cpp
// In TFT_eSPI User_Setup.h:
#define SMOOTH_FONT
```

### No Data Received

**Symptom:** Display shows "Waiting for data..." forever

**Solutions:**
1. Check FPGA system is running and sending orders
2. Verify C++ gateway is publishing to MQTT
3. Test MQTT subscription on PC:
   ```bash
   mosquitto_sub -h 192.168.1.100 -t "fpga/bbo/#" -v
   ```
4. Check Serial Monitor for incoming messages
5. Verify topic name matches gateway configuration

---

## Performance Characteristics

| Metric | Value |
|--------|-------|
| WiFi Latency | ~5-20 ms |
| MQTT Subscribe Latency | ~10-50 ms |
| JSON Parse Time | ~2-5 ms |
| Display Update Time | ~15-30 ms |
| **Total End-to-End** | **~50-100 ms** |

**Display Refresh Rate:** Limited by BBO update rate from FPGA (~10-20 updates/sec for 8 symbols)

---

## Power Consumption

| Mode | Current | Voltage | Power |
|------|---------|---------|-------|
| Active (WiFi TX) | ~160-240 mA | 3.3V | ~0.5-0.8 W |
| Active (WiFi RX) | ~80-120 mA | 3.3V | ~0.3-0.4 W |
| Display On | ~30-50 mA | 3.3V | ~0.1-0.2 W |
| **Total** | **~200-350 mA** | **3.3V** | **~0.7-1.2 W** |

**Power Supply:** USB provides 5V @ 500mA, onboard regulator converts to 3.3V

---

## Future Enhancements

### Display Modes

**Multi-Symbol Rotation:**
```cpp
// Cycle through all 8 symbols every 5 seconds
const char* symbols[] = {"AAPL", "TSLA", "SPY", "QQQ", "GOOGL", "MSFT", "AMZN", "NVDA"};
int currentSymbol = 0;

void loop() {
  if (millis() - lastRotation > 5000) {
    // Request specific symbol from MQTT
    char topic[32];
    sprintf(topic, "fpga/bbo/%s", symbols[currentSymbol]);
    currentSymbol = (currentSymbol + 1) % 8;
  }
}
```

**Alert Mode:**
```cpp
// Flash display when spread exceeds threshold
if (currentBbo.spreadPercent > 1.0) {
  tft.fillScreen(TFT_RED);
  delay(100);
  tft.fillScreen(TFT_BLACK);
  delay(100);
}
```

**Mini Chart:**
```cpp
// Track last 50 bid prices and draw sparkline
float bidHistory[50];
int historyIndex = 0;

void drawSparkline() {
  for (int i = 0; i < 49; i++) {
    int y1 = map(bidHistory[i], minPrice, maxPrice, 100, 120);
    int y2 = map(bidHistory[i+1], minPrice, maxPrice, 100, 120);
    tft.drawLine(i*3, y1, (i+1)*3, y2, TFT_GREEN);
  }
}
```

### Hardware Upgrades

**Battery Operation:**
- Add 18650 Li-ion battery + TP4056 charging module
- Deep sleep between updates for extended battery life
- Wake on MQTT message using ESP32 ULP coprocessor

**Touch Screen:**
- Upgrade to resistive or capacitive touch TFT
- Add symbol selection, zoom, settings UI

**Enclosure:**
- 3D print custom case
- Desk stand or wall mount
- Protection for breadboard connections

---

## Integration with Complete System

This ESP32 display is **one endpoint** in the complete FPGA trading system:

```
┌──────────────┐
│ FPGA (Arty)  │ Hardware order book @ 100 MHz
└──────┬───────┘
       │ UART 115200
       ↓
┌──────────────┐
│ C++ Gateway  │ Multi-protocol publisher
└──┬───┬───┬───┘
   │   │   │
   │   │   └─→ Kafka (Kubernetes) → Mobile App
   │   │
   │   └─────→ TCP :9999 → Java Desktop
   │
   └─────────→ MQTT (Raspberry Pi)
              └─→ ESP32 TFT Display  ← You are here
              └─→ Other IoT devices
```

---

## Files

- `esp32_ticker.ino` - Main Arduino sketch
- `README.md` - This file
- `schematic.png` - Wiring diagram (optional)
- `photos/` - Project photos (optional)

---

## Resources

**Libraries:**
- TFT_eSPI: https://github.com/Bodmer/TFT_eSPI
- PubSubClient: https://github.com/knolleary/pubsubclient
- ArduinoJson: https://arduinojson.org/

**ESP32 Documentation:**
- Official Guide: https://docs.espressif.com/projects/esp-idf/
- Arduino Core: https://github.com/espressif/arduino-esp32

**Display Datasheets:**
- ST7735: https://www.displayfuture.com/Display/datasheet/controller/ST7735.pdf
- ILI9341: https://cdn-shop.adafruit.com/datasheets/ILI9341.pdf

---

## Project Status

**Status:** Functional - Basic BBO display working

**Created:** November 2025

**Last Updated:** November 2025

---

This project demonstrates **end-to-end system integration** from FPGA hardware to IoT display, showcasing polyglot architecture across VHDL, C++, and Arduino C++.
