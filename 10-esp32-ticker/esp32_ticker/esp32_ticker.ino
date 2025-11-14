/*
 * Project 10: ESP32 TFT Ticker Display
 *
 * FPGA Trading System - IoT Market Data Display
 * Subscribes to MQTT broker on Raspberry Pi and displays real-time BBO data
 *
 * Hardware:
 * - ESP32-WROOM or ESP32-Wrover
 * - 1.8" TFT LCD (ST7735 driver)
 *
 * Connections:
 * ESP32        TFT Display
 * -----        -----------
 * 3.3V    →    VCC
 * GND     →    GND
 * GPIO18  →    SCK/SCL
 * GPIO23  →    MOSI/SDA
 * GPIO15  →    CS
 * GPIO2   →    DC/RS
 * GPIO4   →    RST
 *
 * Libraries Required (install via Arduino Library Manager):
 * 1. TFT_eSPI by Bodmer
 * 2. PubSubClient by Nick O'Leary
 * 3. ArduinoJson by Benoit Blanchon
 *
 * Configuration:
 * Edit TFT_eSPI library User_Setup.h:
 *   #define ST7735_DRIVER
 *   #define TFT_WIDTH  128
 *   #define TFT_HEIGHT 160
 *   #define TFT_CS     15
 *   #define TFT_DC     2
 *   #define TFT_RST    4
 * ILI9341 -- 240 x 320
 */

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <TFT_eSPI.h>

// ============================================================================
// Configuration
// ============================================================================

// WiFi credentials
const char *WIFI_SSID = "YOU WIFI SSID";
const char *WIFI_PASSWORD = "YOU WIFI PASSWORD";

// MQTT broker (Raspberry Pi server)
const char *MQTT_SERVER = "192.168.0.2"; // Replace with your Pi IP
const int MQTT_PORT = 1883;
const char *MQTT_TOPIC = "bbo_messages";

// Display rotation (0, 1, 2, 3)
const int DISPLAY_ROTATION = 1; // 1 = Landscape

// ============================================================================
// Global Objects
// ============================================================================

WiFiClient espClient;
PubSubClient mqtt(espClient);
TFT_eSPI tft = TFT_eSPI();

// ============================================================================
// BBO Data Structure
// ============================================================================

struct BboData
{
  char symbol[16];
  float bidPrice;
  int bidShares;
  float askPrice;
  int askShares;
  float spreadPrice;
  float spreadPercent;
  unsigned long timestamp;
} currentBbo;

// ============================================================================
// MQTT Callback
// ============================================================================

void mqttCallback(char *topic, byte *payload, unsigned int length)
{
  // Parse JSON message
  StaticJsonDocument<512> doc;
  DeserializationError error = deserializeJson(doc, payload, length);

  if (error)
  {
    Serial.print("JSON parse error: ");
    Serial.println(error.c_str());
    return;
  }

  // Extract BBO data
  const char *symbol = doc["symbol"];
  if (symbol)
    strncpy(currentBbo.symbol, symbol, 15);

  currentBbo.bidPrice = doc["bid"]["price"] | 0.0;
  currentBbo.bidShares = doc["bid"]["shares"] | 0;
  currentBbo.askPrice = doc["ask"]["price"] | 0.0;
  currentBbo.askShares = doc["ask"]["shares"] | 0;
  currentBbo.spreadPrice = doc["spread"]["price"] | 0.0;
  currentBbo.spreadPercent = doc["spread"]["percent"] | 0.0;
  currentBbo.timestamp = millis();

  // Update display
  updateDisplay();

  // Debug output
  Serial.printf("[%s] Bid: $%.2f (%d) | Ask: $%.2f (%d) | Spread: $%.2f\n",
                currentBbo.symbol,
                currentBbo.bidPrice, currentBbo.bidShares,
                currentBbo.askPrice, currentBbo.askShares,
                currentBbo.spreadPrice);
}

// ============================================================================
// Display Update
// ============================================================================

void updateDisplay()
{
  tft.fillScreen(TFT_BLACK);

  // Header - Symbol
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextSize(3);
  tft.setCursor(10, 5);
  tft.println(currentBbo.symbol);

  // Separator line
  tft.drawFastHLine(0, 30, 160, TFT_DARKGREY);

  // Bid price (Green)
  tft.setTextSize(1);
  tft.setTextColor(TFT_GREEN, TFT_BLACK);
  tft.setCursor(5, 38);
  tft.print("BID:");

  tft.setTextSize(2);
  tft.setCursor(5, 50);
  tft.printf("$%.2f", currentBbo.bidPrice);

  tft.setTextSize(1);
  tft.setCursor(100, 55);
  tft.printf("(%d)", currentBbo.bidShares);

  // Ask price (Red)
  tft.setTextColor(TFT_RED, TFT_BLACK);
  tft.setTextSize(1);
  tft.setCursor(5, 75);
  tft.print("ASK:");

  tft.setTextSize(2);
  tft.setCursor(5, 87);
  tft.printf("$%.2f", currentBbo.askPrice);

  tft.setTextSize(1);
  tft.setCursor(100, 92);
  tft.printf("(%d)", currentBbo.askShares);

  // Separator line
  tft.drawFastHLine(0, 108, 160, TFT_DARKGREY);

  // Spread (Yellow)
  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.setTextSize(1);
  tft.setCursor(5, 112);
  tft.print("SPREAD:");

  tft.setTextSize(1);
  tft.setCursor(60, 112);
  tft.printf("$%.2f (%.2f%%)", currentBbo.spreadPrice, currentBbo.spreadPercent);

  // Footer - Timestamp
  tft.setTextColor(TFT_DARKGREY, TFT_BLACK);
  tft.setTextSize(1);
  tft.setCursor(5, 120);
  tft.printf("Updated: %lus ago", (millis() - currentBbo.timestamp) / 1000);
}

// ============================================================================
// Display Splash Screen
// ============================================================================

void displaySplash(const char *message)
{
  tft.fillScreen(TFT_BLACK);
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextSize(2);
  tft.setCursor(10, 20);
  tft.println("FPGA");
  tft.println("Ticker");

  tft.setTextSize(1);
  tft.setCursor(10, 70);
  tft.setTextColor(TFT_CYAN, TFT_BLACK);
  tft.println(message);
}

// ============================================================================
// WiFi Connection
// ============================================================================

void connectWiFi()
{
  displaySplash("Connecting WiFi...");
  Serial.print("Connecting to WiFi: ");
  Serial.println(WIFI_SSID);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30)
  {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED)
  {
    Serial.println("\nWiFi connected!");
    Serial.print("IP address: ");
    Serial.println(WiFi.localIP());

    displaySplash("WiFi OK!");
    delay(1000);
  }
  else
  {
    Serial.println("\nWiFi connection failed!");
    displaySplash("WiFi FAILED!");
    delay(3000);
  }
}

// ============================================================================
// MQTT Connection
// ============================================================================

void connectMQTT()
{
  while (!mqtt.connected())
  {
    displaySplash("Connecting MQTT...");
    Serial.print("Connecting to MQTT broker: ");
    Serial.println(MQTT_SERVER);

    if (mqtt.connect("ESP32_TFT_Ticker", "trading", "trading123"))
    {
      Serial.println("MQTT connected!");
      mqtt.subscribe(MQTT_TOPIC);
      Serial.print("Subscribed to: ");
      Serial.println(MQTT_TOPIC);

      displaySplash("MQTT OK!\nWaiting for data...");
      delay(2000);
    }
    else
    {
      Serial.print("MQTT connection failed, rc=");
      Serial.println(mqtt.state());
      displaySplash("MQTT FAILED!\nRetrying...");
      delay(5000);
    }
  }
}

// ============================================================================
// Setup
// ============================================================================

void setup()
{
  // Initialize Serial
  Serial.begin(115200);
  Serial.println("\n\n=================================");
  Serial.println("FPGA Trading System");
  Serial.println("ESP32 TFT Ticker Display");
  Serial.println("Project 10 - IoT Market Data");
  Serial.println("=================================\n");

  // Initialize TFT display
  tft.init();
  tft.setRotation(DISPLAY_ROTATION);
  tft.fillScreen(TFT_BLACK);

  // Display splash
  displaySplash("Initializing...");
  delay(2000);

  // Connect WiFi
  connectWiFi();

  // Setup MQTT
  mqtt.setServer(MQTT_SERVER, MQTT_PORT);

  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(512); // Increase buffer for JSON messages

  // Connect MQTT
  connectMQTT();

  Serial.println("\nSetup complete. Ready to display BBO data.");
}

// ============================================================================
// Main Loop
// ============================================================================

void loop()
{
  // Maintain MQTT connection
  if (!mqtt.connected())
  {
    connectMQTT();
  }
  mqtt.loop();

  // Optional: Update "time ago" display every 10 seconds
  static unsigned long lastUpdate = 0;
  if (millis() - lastUpdate > 10000)
  {
    updateDisplay();
    lastUpdate = millis();
  }
}
