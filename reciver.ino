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
const unsigned long ALERT_CHECK_INTERVAL = 30000; // 30 seconds to check Supabase for new alerts
const unsigned long HEARTBEAT_INTERVAL = 5000;    // 5 seconds for gateway status heartbeat

// New: LoRa mode management
const unsigned long LORA_MODE_DURATION = 300000; // 5 minutes in milliseconds (5 * 60 * 1000)

// Global variables
unsigned long lastAlertCheck = 0;
unsigned long lastHeartbeat = 0;
unsigned long lastModeChange = 0; // Timer for mode switching
bool isSendingAlertsMode = true;  // Start in alert sending mode

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
  // Temporarily increased for debugging, revert to a lower value if stable.
  esp_task_wdt_config_t wdt_config = {
    .timeout_ms = 60000, // 60 seconds timeout for debugging. Consider 15000-30000 for production.
  };
  esp_task_wdt_init(&wdt_config);
  // Add the current task (main loop) to the watchdog
  esp_task_wdt_add(NULL); 
#endif

  Serial.println("\nStarting LoRa Gateway Setup...");

  // Initialize WiFi and LoRa modules
  // The first attempt to connect to WiFi happens here.
  if (!initWiFi()) { // Only check WiFi here. LoRa init is separate.
    Serial.println("WiFi initialization failed! Rebooting in 5 seconds...");
    delay(5000);
    ESP.restart(); // Reboot if WiFi fails to connect initially
  }

  if (!initLoRa()) {
    Serial.println("LoRa initialization failed! Rebooting in 5 seconds...");
    delay(5000);
    ESP.restart(); // Reboot if LoRa fails to initialize
  }

  Serial.println("Gateway initialized successfully!");
  Serial.println("Initial RSSI: " + String(LoRa.rssi()));

  // Initialize the mode change timer
  lastModeChange = millis();
  Serial.println("[MODE] Starting in ALERT SENDING mode (" + String(LORA_MODE_DURATION / 1000) + " seconds).");
  // LoRa is typically in standby/idle after LoRa.begin(), ready for beginPacket()
}

void loop() {
#ifdef ESP32
  esp_task_wdt_reset(); // Reset the watchdog timer in each loop iteration
#endif

  // Periodically check and reconnect to WiFi if disconnected
  // This will only attempt to reconnect if WiFi.status() is not WL_CONNECTED
  manageWiFiConnection();

  // Send system heartbeat information periodically
  if (millis() - lastHeartbeat > HEARTBEAT_INTERVAL) {
    sendHeartbeat();
    lastHeartbeat = millis();
  }

  // --- LoRa Mode Management ---
  // Check if the current mode duration has elapsed
  if (millis() - lastModeChange > LORA_MODE_DURATION) {
    isSendingAlertsMode = !isSendingAlertsMode; // Toggle mode
    lastModeChange = millis(); // Reset mode timer

    if (isSendingAlertsMode) {
      Serial.println("\n[MODE CHANGE] Switching to ALERT SENDING mode (" + String(LORA_MODE_DURATION / 1000) + " seconds).");
      // LoRa is ready for sending after this, no explicit receive() call needed as beginPacket() handles it.
    } else {
      Serial.println("\n[MODE CHANGE] Switching to DATA RECEIVING mode (" + String(LORA_MODE_DURATION / 1000) + " seconds).");
      LoRa.receive(); // Explicitly set LoRa module to receive mode
    }
  }

  // Act based on the current LoRa mode
  if (isSendingAlertsMode) {
    // Only check for and send alerts in ALERT SENDING mode
    if (millis() - lastAlertCheck > ALERT_CHECK_INTERVAL) {
      lastAlertCheck = millis();
      checkAndSendAlerts();
    }
  } else {
    // Only process incoming LoRa packets in DATA RECEIVING mode
    int packetSize = LoRa.parsePacket();
    if (packetSize) {
      processIncomingPacket(packetSize);
    }
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
    } else {
      // Serial.println("WiFi is connected. Status: " + String(WiFi.status())); // Optional: uncomment for verbose status
    }
  }
}

/**
 * @brief Checks the Supabase 'moisture_alert' table for active alerts
 * (where toAlert is true) and sends them to the respective LoRa devices.
 * If no alerts are found, it immediately switches the gateway to data receiving mode.
 */
void checkAndSendAlerts() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[ALERT] WiFi not connected. Cannot check alerts.");
    return;
  }

  Serial.println("\n[ALERT] Checking for active moisture alerts...");
  
  HTTPClient http;
  // Query Supabase for alerts where 'toAlert' is true
  String alertUrl = String(supabaseUrl) + "moisture_alert?toAlert=eq.true";
  Serial.println("[ALERT] Fetching from: " + alertUrl);

  http.begin(alertUrl);
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + String(supabaseKey));
  http.setConnectTimeout(10000); // 10 second connection timeout
  http.setTimeout(15000);       // 15 second data transfer timeout

  int httpCode = http.GET(); // Send GET request
  
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    Serial.println("[ALERT] Received alert data:");
    Serial.println(payload);
    
    DynamicJsonDocument doc(2048); // Use a larger document size for alerts
    DeserializationError error = deserializeJson(doc, payload);
    
    if (error) {
      Serial.print("[ALERT] JSON error: ");
      Serial.println(error.c_str());
    } else {
      JsonArray alerts = doc.as<JsonArray>();
      if (alerts.size() == 0) {
        Serial.println("[ALERT] No active alerts found in Supabase. Switching to DATA RECEIVING mode immediately.");
        isSendingAlertsMode = false; // Force switch to data receiving mode
        lastModeChange = millis();   // Reset the mode timer
        LoRa.receive();              // Set LoRa module to receive mode
      } else {
        // Iterate through each alert in the JSON array
        for (JsonObject alert : alerts) {
          Serial.println("\n[ALERT] Processing alert:");
          printAlertData(alert); // Print alert details to serial
          
          // Now send the complete alert JSON via LoRa
          for(int i = 0; i < 3; i++){ // Retrying LoRa send 3 times for robustness
            Serial.println("[ALERT] Attempting to send alert via LoRa... attempt " + String(i + 1));
            sendAlertToDevice(alert); 
            delay(100); // Small delay between retries
          }
          Serial.println("[ALERT] LoRa send initiated for alert.");
          
          // Mark the alert as 'toAlert=false' in Supabase immediately after fetching.
          if (alert.containsKey("Farm_ID") && alert.containsKey("Device_ID") && alert.containsKey("toAlert")) {
            Serial.println("[ALERT] Attempting to mark alert as processed in Supabase...");
            // Pass alert["toAlert"] as bool
            if (!updateAlertStatus(alert["Farm_ID"].as<String>(), alert["Device_ID"].as<String>(), alert["toAlert"].as<bool>())) {
                Serial.println("[ALERT] WARNING: Failed to update alert status in Supabase. This alert might be re-sent on next cycle if the update eventually fails.");
            } else {
                Serial.println("[ALERT] Alert status successfully updated to 'false' in Supabase.");
            }
          } else {
              Serial.println("[ALERT] Missing Farm_ID, Device_ID, or toAlert for updating alert status. Alert cannot be marked as processed in Supabase.");
          }         
          delay(500); // Small delay between processing multiple alerts to prevent LoRa buffer overflow and allow time for node to receive
        }
      }
    }
    doc.clear(); // Clear the JSON document to free memory
  } else {
    Serial.print("[ALERT] HTTP GET error: ");
    Serial.println(httpCode);
    Serial.println("[ALERT] Response: " + http.getString());
    // If there was an HTTP error, stay in the current mode or consider immediate retry logic
    // For now, we'll let the timer eventually switch modes.
  }
  
  http.end(); // Close the HTTP connection
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

  // --- Granular LoRa Debugging ---
  Serial.println("[LoRa Debug] Attempting LoRa.beginPacket()...");
  int beginResult = LoRa.beginPacket();
  if (beginResult == 0) { // beginPacket returns 0 on failure
    Serial.println("[LoRa Debug] LoRa.beginPacket() FAILED! LoRa module might not be initialized or responding.");
    docToSend.clear();
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
}

/**
 * @brief Updates the 'toAlert' status of a specific alert in the Supabase 'moisture_alert' table to false.
 * This prevents the same alert from being repeatedly sent by the gateway.
 * @param farmId The Farm_ID of the alert to update.
 * @param deviceId The Device_ID of the alert to update.
 * @param currentToAlertStatus The current boolean value of 'toAlert' for this specific alert.
 * This parameter is received from the fetched alert data, but the filter for the PATCH
 * request explicitly looks for `toAlert=true` to target active alerts.
 * @return True if the update was successful, false otherwise.
 */
bool updateAlertStatus(String farmId, String deviceId, bool currentToAlertStatus) { 
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[ALERT_UPDATE] WiFi not connected. Cannot update alert status.");
    return false;
  }

  // Updated print statement to reflect boolean value
  Serial.println("[ALERT_UPDATE] Attempting update for Farm_ID: " + farmId + ", Device_ID: " + deviceId + ", current toAlert: " + (currentToAlertStatus ? "true" : "false"));

  HTTPClient http;
  
  // Construct the URL to target the specific alert record.
  // ALWAYS filter for toAlert.eq.true because you want to mark an *active* alert as processed.
  String updateUrl = String(supabaseUrl) + "moisture_alert?and=(Farm_ID.eq." + farmId + ",Device_ID.eq." + deviceId + ",toAlert.eq.true)"; // Correct filter
  
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
  Serial.printf("│ Uptime:         %8d sec\n", millis()/1000);
  Serial.printf("│ WiFi:           %8s\n", WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected");
  Serial.printf("│ RSSI:           %8d dBm\n", LoRa.rssi());
  Serial.printf("│ Next alert:     %8d sec\n", (ALERT_CHECK_INTERVAL - (millis() - lastAlertCheck))/1000);
  Serial.printf("│ LoRa Mode:      %8s\n", isSendingAlertsMode ? "ALERT SEND" : "DATA REC");
  Serial.printf("│ Mode change in: %8d sec\n", (LORA_MODE_DURATION - (millis() - lastModeChange))/1000);
  Serial.println("──────────────────────────");
}

/**
 * @brief Processes an incoming LoRa packet. It can be an acknowledgment (ACK)
 * or sensor data.
 * @param packetSize The size of the incoming LoRa packet.
 */
void processIncomingPacket(int packetSize) {
  Serial.println("\n[LoRa] Incoming packet (" + String(packetSize) + " bytes)");

  String incoming;
  while (LoRa.available()) {
    incoming += (char)LoRa.read();
  }

  Serial.println("[LoRa] Raw data: " + incoming);
  incoming.trim(); // Remove any whitespace

  // Check if the incoming packet is an acknowledgment from a node
  if (incoming.startsWith("{\"type\":\"ack\"")) {
    DynamicJsonDocument ackDoc(256);
    DeserializationError ackError = deserializeJson(ackDoc, incoming);
    if (!ackError) {
      Serial.println("[LoRa] Received ACK from device:");
      serializeJsonPretty(ackDoc, Serial);
      Serial.println();
      // You could potentially add logic here to mark an alert as acknowledged
      // in Supabase if the ACK packet contains enough information (e.g., Farm_ID, Device_ID, alert_id)
      // This would involve another call to updateAlertStatus or a similar function,
      // possibly updating a different field like 'ack_received' to true.
    } else {
        Serial.print("[LoRa] ACK JSON deserialization error: ");
        Serial.println(ackError.c_str());
    }
    ackDoc.clear();
    return; // Exit as this packet was an ACK
  }

  // Assume other incoming packets are sensor data
  DynamicJsonDocument doc(512); // Sufficient size for sensor data
  DeserializationError error = deserializeJson(doc, incoming);

  if (error) {
    Serial.print("[LoRa] JSON deserialization error for sensor data: ");
    Serial.println(error.c_str());
    doc.clear();
    return;
  }

  // Validate required fields for sensor data
  if (!doc.containsKey("Farm_ID") || !doc.containsKey("Device_ID") || !doc.containsKey("value")) {
    Serial.println("[LoRa] Missing required fields (Farm_ID, Device_ID, value) in sensor data packet.");
    doc.clear();
    return;
  }

  String farmId = doc["Farm_ID"].as<String>();
  String deviceId = doc["Device_ID"].as<String>();
  int value = doc["value"].as<int>();

  Serial.printf("[LoRa] Received sensor data - Farm: %s, Device: %s, Value: %d, RSSI: %d dBm, SNR: %.2f\n", 
                farmId.c_str(), deviceId.c_str(), value, LoRa.packetRssi(), LoRa.packetSnr());

  // Send sensor data to Supabase (retry mechanism included)
  bool success = false;
  for (int attempt = 1; attempt <= 3 && !success; attempt++) {
    Serial.printf("[LoRa] Attempt %d/3 to send sensor data to Supabase...\n", attempt);
    success = sendToSupabase(farmId, deviceId, value);
    if (!success) {
      Serial.println("[LoRa] Retrying in 2 seconds...");
      delay(2000); // Delay before retrying
    }
  }

  Serial.println(success ? "[LoRa] Sensor data saved successfully to Supabase." : "[LoRa] Failed to save sensor data to Supabase after multiple attempts.");
  doc.clear();
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