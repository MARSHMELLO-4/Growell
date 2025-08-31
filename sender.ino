#include <SPI.h>
#include <LoRa.h>
#include <ArduinoJson.h>

// LoRa configuration
#define LORA_SS 10
#define LORA_RST 9
#define LORA_DIO0 2
#define LORA_FREQ 433E6
#define LORA_SYNC_WORD 0xF3

// Hardware pins
#define BUZZER_PIN 7
#define MOISTURE_PIN A0 // Analog pin for moisture sensor

// Device specific identifier
const String deviceId = "21_2"; // This node's unique ID

// Timing intervals
const unsigned long MOISTURE_SEND_INTERVAL = 30000; // Send moisture data every 30 seconds
const unsigned int RANDOM_DELAY_MAX = 5000;         // Max random delay (0-5 seconds) for staggering
const unsigned long ALERT_RECEIVE_WINDOW = 8000;    // Stay in listening mode for 5 seconds after sending for alerts

// Global variables
unsigned long lastSentTime = 0; // Tracks when the last moisture data was sent

void setup() {
  Serial.begin(9600);
  while (!Serial); // Wait for Serial Monitor to open

  Serial.println("Nano Node Starting...");

  // Initialize hardware pins
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW); // Ensure buzzer is off initially
  pinMode(MOISTURE_PIN, INPUT);

  // LoRa Module Reset (common practice for SX127x modules)
  pinMode(LORA_RST, OUTPUT);
  digitalWrite(LORA_RST, LOW);
  delay(10);
  digitalWrite(LORA_RST, HIGH);
  delay(10);

  // Set LoRa module pins
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  // Initialize LoRa module
  if (!LoRa.begin(LORA_FREQ)) {
    Serial.println("LoRa init failed! Check connections and frequency.");
    while (1); // Halt execution if LoRa fails
  }

  LoRa.setSyncWord(LORA_SYNC_WORD); // Set the LoRa sync word
  LoRa.enableCrc();                 // Enable CRC for error checking
  Serial.println("LoRa initialized!");

  // Seed random number generator with analogRead from an unconnected pin for better randomness
  randomSeed(analogRead(A1)); 

  // Initialize lastSentTime to ensure an immediate send or wait for the first interval
  lastSentTime = millis() - MOISTURE_SEND_INTERVAL - random(RANDOM_DELAY_MAX); // Forces an immediate send on first loop
                                                                                // or adjust if you want to wait for the first interval
}

void loop() {
  unsigned long currentTime = millis();

  // ---------------- MOISTURE SENDING PHASE ----------------
  // Check if it's time to send moisture data
  if (currentTime - lastSentTime >= (MOISTURE_SEND_INTERVAL + random(0, RANDOM_DELAY_MAX))) {
    // Send moisture data
    sendMoistureData();
    lastSentTime = currentTime; // Update the last sent time
    
    // ---------------- ALERT RECEIVE WINDOW ----------------
    // Immediately enter listening mode for a short window to receive alerts
    Serial.println("Entering alert receive window for " + String(ALERT_RECEIVE_WINDOW / 1000) + " seconds...");
    LoRa.receive(); // Explicitly set LoRa module to receive mode
    unsigned long receiveWindowStartTime = currentTime;

    while (millis() - receiveWindowStartTime < ALERT_RECEIVE_WINDOW) {
      int packetSize = LoRa.parsePacket();
      if (packetSize) {
        String receivedData = "";
        while (LoRa.available()) {
          receivedData += (char)LoRa.read();
        }
        Serial.println("Received during alert window: " + receivedData);

        StaticJsonDocument<256> doc;
        DeserializationError error = deserializeJson(doc, receivedData);

        if (error) {
          Serial.println("JSON Deserialization Error in alert window: " + String(error.c_str()));
          // Continue listening or break if severe
        } else {
          String incomingDeviceId = doc["Device_ID"] | "";
          String gatewayType = doc["gateway_type"] | "";

          if (incomingDeviceId == deviceId) {
            Serial.println("ALERT RECEIVED for this device! Activating buzzer.");
            digitalWrite(BUZZER_PIN, HIGH);
            delay(4000); // Buzzer on for 4 seconds
            digitalWrite(BUZZER_PIN, LOW);
            // Optionally, break out of the receive window early if an alert is received and processed
            // break; 
          }
          // If it's not an alert for this device, or not an alert, simply ignore and continue listening
        }
      }
      delay(10); // Small delay to prevent busy-waiting during receive window
    }
    Serial.println("Exiting alert receive window.");
    // After the receive window, LoRa module is still in receive mode from LoRa.receive() above.
    // It will remain in receive mode until the next sendMoistureData() call.
  }
  
  // If not sending, stay in implicit listening mode (LoRa.receive() from previous cycle)
  // and wait for the next scheduled send time. No active LoRa.parsePacket() here
  // because we only listen right after sending.
  
  delay(10); // Small delay to prevent busy-waiting during the main loop
}

/**
 * @brief Sends moisture sensor data via LoRa.
 * Incorporates LoRa.idle() before transmission and LoRa.receive() after.
 */
void sendMoistureData() {
  int moisture = analogRead(MOISTURE_PIN); // Read moisture value
  Serial.println("Preparing to send moisture: " + String(moisture));

  StaticJsonDocument<128> outDoc;
  outDoc["Farm_ID"] = 21;
  outDoc["Device_ID"] = deviceId;
  outDoc["value"] = moisture;
  

  String outPayload;
  serializeJson(outDoc, outPayload);

  Serial.println("Sending LoRa packet: " + outPayload);

  // Collision Avoidance: Ensure LoRa module is idle before starting transmission
  LoRa.idle(); // Put LoRa into idle mode
  
  LoRa.beginPacket(); // Start LoRa packet transmission
  LoRa.print(outPayload); // Write JSON payload to packet
  int endPacketResult = LoRa.endPacket(); // End and send the packet

  if (endPacketResult) {
    Serial.println("LoRa packet sent successfully.");
  } else {
    Serial.println("LoRa packet send failed.");
  }

  // Collision Avoidance: Immediately return to receive mode after sending
  // This is handled by LoRa.receive() at the start of the ALERT_RECEIVE_WINDOW
  // which immediately follows this function call.
}
