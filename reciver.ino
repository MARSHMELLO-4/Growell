#include <SPI.h>
#include <LoRa.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#ifdef ESP32
#include <esp_task_wdt.h>
#endif

// WiFi credentials
const char* ssid = "AmanRedmi";
const char* password = "Aman1234";

// Supabase configuration
const char* supabaseUrl = "https://lmqogledtugtltwyflho.supabase.co/rest/v1/";
const char* supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxtcW9nbGVkdHVndGx0d3lmbGhvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDI2NTkzNTYsImV4cCI6MjA1ODIzNTM1Nn0.8bs_jnJc7r4MW4YFZtNuczzCpIsusoX9SZ5IVrdKfkM";

// LoRa configuration
#define LORA_SS 5
#define LORA_RST 14
#define LORA_DIO0 26
#define LORA_FREQ 433E6
#define LORA_SYNC_WORD 0xF3

// Timing intervals
// ALERT_CHECK_INTERVAL is now effectively tied to incoming packet reception
const unsigned long HEARTBEAT_INTERVAL = 5000;     // 5 seconds for gateway status heartbeat

// Global variables
unsigned long lastHeartbeat = 0;

// Function prototypes
void handleResponse(int code, HTTPClient &http, String operation);
bool sendToSupabase(String farmId, String deviceId, int value);
void processIncomingPacket(int packetSize);
bool initWiFi();
bool initLoRa();
void checkAndSendAlerts();
void sendAlertToDevice(JsonObject alertData);
void sendHeartbeat();
void printAlertData(JsonObject alertData);
void manageWiFiConnection();
bool updateAlertStatus(String farmId, String deviceId, bool currentToAlertStatus);

void setup() {
  Serial.begin(115200);
  while (!Serial); // Wait for Serial to be ready

#ifdef ESP32
  // Initialize watchdog timer for ESP32 to prevent crashes
  esp_task_wdt_config_t wdt_config = {
    .timeout_ms = 30000,
    .trigger_panic = false // Don't panic on timeout // 60 seconds timeout.
  };
  esp_task_wdt_init(&wdt_config);
  // Add the current task (main loop) to the watchdog
  esp_task_wdt_add(NULL); 
#endif

  Serial.println("\nStarting LoRa Gateway Setup...");

  // Initialize WiFi and LoRa modules
  if (!initWiFi()) {
    Serial.println("WiFi initialization failed! Rebooting in 5 seconds...");
    delay(5000);
    ESP.restart(); // Reboot if WiFi fails to connect initially
  }

  if (!initLoRa()) {
    Serial.println("LoRa initialization failed! Rebooting in 5 seconds...");
    delay(5000);
    ESP.restart(); // Reboot if LoRa fails to initialize
  }

  // Set LoRa to receive mode by default
  LoRa.receive();
  Serial.println("Gateway initialized successfully! LoRa is in DATA RECEIVING mode.");
  Serial.println("Initial RSSI: " + String(LoRa.rssi()));
}

void loop() {
#ifdef ESP32
  esp_task_wdt_reset(); // Reset the watchdog timer in each loop iteration
#endif

  // Periodically check and reconnect to WiFi if disconnected
  manageWiFiConnection();

  // Send system heartbeat information periodically
  if (millis() - lastHeartbeat > HEARTBEAT_INTERVAL) {
    sendHeartbeat();
    lastHeartbeat = millis();
  }

  // Always process incoming LoRa packets
  int packetSize = LoRa.parsePacket();
  if (packetSize) {
    processIncomingPacket(packetSize);
  }

  delay(10); // Small delay to prevent busy-waiting and allow other tasks to run
}

/**
 * @brief Manages the WiFi connection, reconnecting if lost.
 * This function is called periodically but only attempts a reconnection if WiFi is disconnected.
 */
void manageWiFiConnection() {
  static unsigned long lastWiFiCheck = 0;
  const unsigned long WIFI_CHECK_INTERVAL = 10000; // Check every 10 seconds

  if (millis() - lastWiFiCheck > WIFI_CHECK_INTERVAL) {
    lastWiFiCheck = millis();
    
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("WiFi connection lost or not connected. Attempting to reconnect...");
      initWiFi(); // Call initWiFi to re-establish connection
    }
  }
}

/**
 * @brief Checks the Supabase 'moisture_alert' table for active alerts
 * (where toAlert is true) and sends them to the respective LoRa devices.
 * This function is now called immediately after receiving and processing a sensor packet.
 */
void checkAndSendAlerts() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[ALERT] WiFi disconnected");
    return;
  }

  Serial.println("[ALERT] Starting alert check");
  
  HTTPClient http;
  String alertUrl = String(supabaseUrl) + "moisture_alert?toAlert=eq.true";
  http.begin(alertUrl);
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));

  int httpCode = http.GET();
  
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    DynamicJsonDocument doc(1024);  // Reduced size
    DeserializationError error = deserializeJson(doc, payload);
    
    if (!error) {
      for (JsonObject alert : doc.as<JsonArray>()) {
        Serial.println("[ALERT] Processing alert");
        sendAlertToDevice(alert);
        updateAlertStatus(alert["Farm_ID"].as<String>(), 
                         alert["Device_ID"].as<String>(), 
                         alert["toAlert"].as<bool>());
        delay(500);
      }
    }
    doc.clear();
  }
  http.end();
  LoRa.receive();
}

/**
 * @brief Prints the contents of a JsonObject (alert data) to the Serial monitor in a formatted way.
 * @param alertData The JsonObject containing the alert details.
 */
void printAlertData(JsonObject alertData) {
  Serial.println("┌───────────────────────────");
  for (JsonPair kv : alertData) {
    Serial.printf("│ %-15s: ", kv.key().c_str());
    if (kv.value().isNull()) {
      Serial.println("NULL");
    } else if (kv.value().is<String>()) {
      Serial.println(kv.value().as<String>());
    } else if (kv.value().is<int>()) {
      Serial.println(kv.value().as<int>());
    } else if (kv.value().is<float>()) {
      Serial.println(kv.value().as<float>(), 2);
    } else if (kv.value().is<bool>()) {
      Serial.println(kv.value().as<bool>() ? "true" : "false");
    }
  }
  Serial.println("└───────────────────────────");
}

/**
 * @brief Sends an alert as a LoRa packet. The entire 'alertData' JsonObject
 * is sent, with additional gateway metadata. The LoRa node will interpret this.
 * @param alertData The JsonObject containing the alert details from Supabase.
 */
void sendAlertToDevice(JsonObject alertData) {
  DynamicJsonDocument docToSend(1024); // Sufficient size for alert data + metadata
  
  // Copy all alert data directly into the document to be sent via LoRa
  for (JsonPair kv : alertData) {
    docToSend[kv.key()] = kv.value();
  }
  
  // Add gateway metadata to the outgoing packet
  docToSend["gateway_timestamp"] = millis();
  docToSend["gateway_type"] = "alert"; // Indicate this is an alert packet

  Serial.println("\n[ALERT] Sending LoRa packet with this data:");
  serializeJsonPretty(docToSend, Serial); // Print formatted JSON to serial
  Serial.println("\n");

  // Collision Avoidance: Ensure LoRa module is idle before starting transmission
  LoRa.idle();
  Serial.println("[LoRa Debug] LoRa.idle() called before beginPacket.");

  Serial.println("[LoRa Debug] Attempting LoRa.beginPacket()...");
  int beginResult = LoRa.beginPacket();
  if (beginResult == 0) { // beginPacket returns 0 on failure
    Serial.println("[LoRa Debug] LoRa.beginPacket() FAILED! LoRa module might not be initialized or responding.");
    docToSend.clear();
    LoRa.receive(); // Immediately return to receive mode if beginPacket fails
    return; // Exit if we can't even start a packet
  } else {
    Serial.println("[LoRa Debug] LoRa.beginPacket() SUCCESS.");
  }

  Serial.println("[LoRa Debug] Attempting serializeJson to LoRa buffer...");
  size_t bytesWritten = serializeJson(docToSend, LoRa); // Serialize JSON directly to LoRa buffer
  Serial.printf("[LoRa Debug] serializeJson wrote %u bytes.\n", bytesWritten);

  Serial.println("[LoRa Debug] Attempting LoRa.endPacket()...");
  int endResult = LoRa.endPacket();     // End and send the packet
  
  docToSend.clear(); // Clear the JSON document to free memory

  if (endResult == 1) {
    Serial.println("[ALERT] LoRa packet sent successfully (" + String(bytesWritten) + " bytes).");
  } else {
    Serial.println("[ALERT] LoRa packet send failed or no data written (LoRa.endPacket failed).");
    if (bytesWritten == 0) {
      Serial.println("[ALERT] No bytes were written to the LoRa buffer (this is critical if beginPacket succeeded).");
    }
  }
  // Collision Avoidance: Immediately return to receive mode after sending
  LoRa.receive();
  Serial.println("[LoRa Debug] LoRa.receive() called after endPacket.");
}

/**
 * @brief Updates the 'toAlert' status of a specific alert in the Supabase 'moisture_alert' table to false.
 * This prevents the same alert from being repeatedly sent by the gateway.
 * @param farmId The Farm_ID of the alert to update.
 * @param deviceId The Device_ID of the alert to update.
 * @param currentToAlertStatus The current boolean value of 'toAlert' for this specific alert.
 * @return True if the update was successful, false otherwise.
 */
bool updateAlertStatus(String farmId, String deviceId, bool currentToAlertStatus) { 
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[ALERT_UPDATE] WiFi not connected. Cannot update alert status.");
    return false;
  }

  Serial.println("[ALERT_UPDATE] Attempting update for Farm_ID: " + farmId + ", Device_ID: " + deviceId + ", current toAlert: " + (currentToAlertStatus ? "true" : "false"));

  HTTPClient http;
  
  String updateUrl = String(supabaseUrl) + "moisture_alert?and=(Farm_ID.eq." + farmId + ",Device_ID.eq." + deviceId + ")";
  
  Serial.println("[ALERT_UPDATE] PATCH URL: " + updateUrl);
  
  http.begin(updateUrl);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("Prefer", "return=minimal"); // Request minimal response

  // Create the update payload to set 'toAlert' to false
  DynamicJsonDocument payloadDoc(128);
  payloadDoc["toAlert"] = false; // Always set to false
  String payload;
  serializeJson(payloadDoc, payload);
  payloadDoc.clear();

  Serial.println("[ALERT_UPDATE] PATCH Payload: " + payload);

  int httpCode = http.PATCH(payload); // Send PATCH request
  bool success = (httpCode == HTTP_CODE_OK || httpCode == HTTP_CODE_NO_CONTENT); // 200 OK or 204 No Content for successful PATCH
  
  handleResponse(httpCode, http, "Update Alert Status"); // Detailed response handling
  http.end(); // Close the HTTP connection
  
  if (!success) {
      Serial.println("[ALERT_UPDATE] Update failed with HTTP code: " + String(httpCode));
  }
  return success;
}

/**
 * @brief Sends a system heartbeat message to the Serial monitor.
 */
void sendHeartbeat() {
  Serial.println("\n[STATUS] System Heartbeat");
  Serial.println("──────────────────────────");
  #ifdef ESP32
  Serial.printf("│ Free Heap:      %8d bytes\n", ESP.getFreeHeap());
  Serial.printf("│ Min Free Heap:  %8d bytes\n", ESP.getMinFreeHeap());
  #endif
  Serial.printf("│ Uptime:         %8d sec\n", millis()/1000);
  Serial.printf("│ WiFi:           %8s\n", WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected");
  Serial.printf("│ RSSI:           %8d dBm\n", LoRa.rssi());
  Serial.printf("│ LoRa Mode:      %8s\n", "DATA REC (Default)"); // Always in receive mode by default
  Serial.println("──────────────────────────");
}

/**
 * @brief Processes an incoming LoRa packet. It can be an acknowledgment (ACK)
 * or sensor data.
 * @param packetSize The size of the incoming LoRa packet.
 */
void processIncomingPacket(int packetSize) {
  // Check for alerts
  #ifdef ESP32
  esp_task_wdt_reset();
  #endif
  Serial.println("[LoRa] Checking for alerts...");
  checkAndSendAlerts();
  Serial.println("\n[LoRa] Incoming packet (" + String(packetSize) + " bytes)");

  // Add watchdog reset at start
  #ifdef ESP32
  esp_task_wdt_reset();
  #endif

  String incoming;
  while (LoRa.available()) {
    incoming += (char)LoRa.read();
  }

  Serial.println("[LoRa] Raw data: " + incoming);
  incoming.trim();

  // Check for ACK first
  if (incoming.startsWith("{\"type\":\"ack\"")) {
    DynamicJsonDocument ackDoc(128);  // Reduced size
    DeserializationError ackError = deserializeJson(ackDoc, incoming);
    if (!ackError) {
      Serial.println("[LoRa] Received ACK from device:");
      serializeJsonPretty(ackDoc, Serial);
    } else {
      Serial.print("[LoRa] ACK JSON error: ");
      Serial.println(ackError.c_str());
    }
    ackDoc.clear();
    LoRa.receive();
    return;
  }

  // Process sensor data
  DynamicJsonDocument doc(256);  // Reduced size
  DeserializationError error = deserializeJson(doc, incoming);

  if (error) {
    Serial.print("[LoRa] JSON error: ");
    Serial.println(error.c_str());
    doc.clear();
    LoRa.receive();
    return;
  }

  // Validate fields
  if (!doc.containsKey("Farm_ID") || !doc.containsKey("Device_ID") || !doc.containsKey("value")) {
    Serial.println("[LoRa] Missing required fields");
    doc.clear();
    LoRa.receive();
    return;
  }

  String farmId = doc["Farm_ID"].as<String>();
  String deviceId = doc["Device_ID"].as<String>();
  int value = doc["value"].as<int>();
  doc.clear();  // Clear early to save memory

  Serial.printf("[LoRa] Received data - Farm: %s, Device: %s, Value: %d\n", 
               farmId.c_str(), deviceId.c_str(), value);

  // Send to Supabase with retries
  bool success = false;
  for (int attempt = 1; attempt <= 3 && !success; attempt++) {
    #ifdef ESP32
    esp_task_wdt_reset();
    #endif
    
    Serial.printf("[LoRa] Attempt %d/3 to send data...\n", attempt);
    success = sendToSupabase(farmId, deviceId, value);
    if (!success) delay(2000);
  }

  Serial.println(success ? "[LoRa] Data saved to Supabase" : "[LoRa] Failed to save data");

  // Ensure we return to receive mode
  LoRa.receive();
}

/**
 * @brief Sends sensor data to the Supabase 'moisture_data' table.
 * It checks if a record for the given Farm_ID and Device_ID exists,
 * then updates it (PATCH) or creates a new one (POST).
 * @param farmId The Farm_ID from the sensor data.
 * @param deviceId The Device_ID from the sensor data.
 * @param value The moisture value from the sensor.
 * @return True if the operation (insert or update) was successful, false otherwise.
 */
bool sendToSupabase(String farmId, String deviceId, int value) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[Supabase-Data] WiFi not connected. Cannot send data.");
    return false;
  }

  HTTPClient http;
  bool success = false;

  // --- Step 1: Check if record exists ---
  String checkUrl = String(supabaseUrl) + "moisture_data?and=(Device_ID.eq." + deviceId + ",Farm_ID.eq." + farmId + ")";
  Serial.println("[Supabase-Data] Checking existence URL: " + checkUrl);
  http.begin(checkUrl);
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.addHeader("Range", "0-1"); // Request only 1 record to check existence

  int checkCode = http.GET();
  String checkPayload = http.getString();
  Serial.println("[Supabase-Data] Check response code: " + String(checkCode));
  Serial.println("[Supabase-Data] Check response payload: " + checkPayload);

  // A record exists if the HTTP code is OK/Partial Content and the response payload is not "[]"
  bool recordExists = (checkCode == HTTP_CODE_OK || checkCode == HTTP_CODE_PARTIAL_CONTENT) && 
                      checkPayload.length() > 2 && checkPayload != "[]"; // "> 2" means it's not just "[]"
  http.end(); // Always end the current HTTP client connection

  Serial.println("[Supabase-Data] Record exists: " + String(recordExists ? "Yes" : "No"));

  // --- Step 2: Prepare payload for insert/update ---
  DynamicJsonDocument payloadDoc(256);
  payloadDoc["Farm_ID"] = farmId;
  payloadDoc["Device_ID"] = deviceId;
  payloadDoc["value"] = value;
  // Supabase automatically handles created_at and updated_at if configured.
  String payload;
  serializeJson(payloadDoc, payload);
  payloadDoc.clear();
  Serial.println("[Supabase-Data] Data Payload: " + payload);


  // --- Step 3: Update or Create record ---
  if (recordExists) {
    // If record exists, update it (PATCH)
    String updateUrl = String(supabaseUrl) + "moisture_data?and=(Device_ID.eq." + deviceId + ",Farm_ID.eq." + farmId + ")";
    Serial.println("[Supabase-Data] PATCHing to: " + updateUrl);
    http.begin(updateUrl);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("apikey", supabaseKey);
    http.addHeader("Authorization", "Bearer " + String(supabaseKey));
    http.addHeader("Prefer", "return=minimal"); // We don't need the updated record back
    
    int updateCode = http.PATCH(payload);
    success = (updateCode == HTTP_CODE_OK || updateCode == HTTP_CODE_NO_CONTENT); // 200 OK or 204 No Content for successful PATCH
    handleResponse(updateCode, http, "Update Sensor Data");
  } else {
    // If record doesn't exist, create a new one (POST)
    String insertUrl = String(supabaseUrl) + "moisture_data";
    Serial.println("[Supabase-Data] POSTing to: " + insertUrl);
    http.begin(insertUrl);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("apikey", supabaseKey);
    http.addHeader("Authorization", "Bearer " + String(supabaseKey));
    http.addHeader("Prefer", "return=minimal"); // We don't need the inserted record back
    
    int insertCode = http.POST(payload);
    success = (insertCode == HTTP_CODE_CREATED); // 201 Created for successful POST
    handleResponse(insertCode, http, "Insert Sensor Data");
  }
  http.end(); // Always end the current HTTP client connection

  return success;
}

/**
 * @brief Handles HTTP responses by printing the status code and response body (if any)
 * or error message to the Serial monitor.
 * @param code The HTTP status code.
 * @param http The HTTPClient object.
 * @param operation A string describing the operation (e.g., "Insert", "Update").
 */
void handleResponse(int code, HTTPClient &http, String operation) {
  Serial.printf("[HTTP] %s status: %d\n", operation.c_str(), code);
  if (code > 0) { // HTTP codes are positive
    String response = http.getString();
    if (response.length() > 0) {
      Serial.println("[HTTP] Response: " + response);
    }
  } else { // Negative codes indicate connection/client errors
    Serial.println("[HTTP] Error: " + http.errorToString(code));
  }
}

/**
 * @brief Initializes the WiFi connection to the specified SSID and password.
 * @return True if WiFi connection is successful within timeout, false otherwise.
 */
bool initWiFi() {
  Serial.println("\n[WiFi] Connecting to: " + String(ssid));
  
  WiFi.disconnect(true); // Disconnect from any previous connection
  delay(100);
  WiFi.mode(WIFI_STA);   // Set WiFi to station mode
  WiFi.begin(ssid, password); // Start connection attempt

  unsigned long startTime = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startTime < 25000) { // 25 second timeout
    delay(500);
    Serial.print("."); // Print dots while connecting
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n[WiFi] Connected!");
    Serial.println("[WiFi] IP: " + WiFi.localIP().toString());
    return true;
  } else {
    Serial.println("\n[WiFi] Connection failed!");
    return false;
  }
}

/**
 * @brief Initializes the LoRa module with specified pins, frequency, and sync word.
 * @return True if LoRa initialization is successful, false otherwise.
 */
bool initLoRa() {
  Serial.println("\n[LoRa] Initializing...");

  // Set LoRa module pins (SS, RST, DIO0)
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);
  
  // Initialize LoRa at the specified frequency
  if (!LoRa.begin(LORA_FREQ)) {
    Serial.println("[LoRa] Init failed!");
    return false;
  }

  LoRa.setSyncWord(LORA_SYNC_WORD); // Set the LoRa sync word for filtering packets
  LoRa.enableCrc();              // Enable CRC for error checking
  Serial.println("[LoRa] Initialized successfully!");
  return true;
}
