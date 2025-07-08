#include <SPI.h>
#include <LoRa.h>
#include <ArduinoJson.h>

#define LORA_SS 10
#define LORA_RST 9
#define LORA_DIO0 2
#define LORA_FREQ 433E6
#define LORA_SYNC_WORD 0xF3
#define BUZZER_PIN 7
#define MOISTURE_PIN A0

const String deviceId = "21_2";

unsigned long lastReceivedTime = 0;
bool isSendingMoisture = false;
unsigned long modeStartTime = 0;

void setup() {
  Serial.begin(9600);
  while (!Serial);

  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  pinMode(MOISTURE_PIN, INPUT);

  pinMode(LORA_RST, OUTPUT);
  digitalWrite(LORA_RST, LOW);
  delay(10);
  digitalWrite(LORA_RST, HIGH);
  delay(10);

  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  if (!LoRa.begin(LORA_FREQ)) {
    Serial.println("LoRa init failed!");
    while (1);
  }

  LoRa.setSyncWord(LORA_SYNC_WORD);
  LoRa.enableCrc();
  Serial.println("LoRa initialized!");

  lastReceivedTime = millis();
}

void loop() {
  unsigned long currentTime = millis();

  if (!isSendingMoisture) {
    // ---------------- LISTENING MODE ----------------
    int packetSize = LoRa.parsePacket();
    if (packetSize) {
      lastReceivedTime = currentTime;

      String receivedData = "";
      while (LoRa.available()) {
        receivedData += (char)LoRa.read();
      }
      Serial.println("Received: " + receivedData);

      StaticJsonDocument<256> doc;
      DeserializationError error = deserializeJson(doc, receivedData);

      if (error) {
        Serial.println("JSON Error");
        digitalWrite(BUZZER_PIN, LOW);
        return;
      }

      String incomingDeviceId = doc["Device_ID"] | "";
      String gatewayType = doc["gateway_type"] | "";

      if (gatewayType == "alert" && incomingDeviceId == deviceId) {
        Serial.println("Alert for this device!");
        digitalWrite(BUZZER_PIN, HIGH);
        delay(4000);
        digitalWrite(BUZZER_PIN, LOW);
      } else {
        digitalWrite(BUZZER_PIN, LOW);
      }
    }

    // Check timeout: 60 sec = 60000 ms
    if (currentTime - lastReceivedTime >= 60000) {
      isSendingMoisture = true;
      modeStartTime = currentTime;
      Serial.println("No data for 1 minute! Switching to moisture sending mode...");
    }

  } else {
    // ---------------- SENDING MODE ----------------
    if (currentTime - modeStartTime <= 60000) {
      int moisture = analogRead(MOISTURE_PIN);
      Serial.println("Sending moisture: " + String(moisture));

      StaticJsonDocument<128> outDoc;
      outDoc["Device_ID"] = deviceId;
      outDoc["moisture"] = moisture;
      outDoc["type"] = "moisture";

      String outPayload;
      serializeJson(outDoc, outPayload);

      LoRa.beginPacket();
      LoRa.print(outPayload);
      LoRa.endPacket();

      delay(5000); // Send every 5 seconds
    } else {
      isSendingMoisture = false;
      lastReceivedTime = millis(); // reset timeout timer
      Serial.println("Switching back to listening mode.");
    }
  }

  delay(50); // Small delay
}