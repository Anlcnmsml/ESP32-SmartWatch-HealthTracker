#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "MAX30105.h"
#include "heartRate.h"
#include <math.h> 

// ==========================================
// 1. PIN AYARLARI
// ==========================================
#define SDA_PIN 10
#define SCL_PIN 1
#define MPU_ADDR 0x68
#define MAX30102_ADDR 0x57
#define BUZZER_PIN 2
#define BUTTON_PIN 3 

// ==========================================
// 2. DÜŞME ALGORİTMASI AYARLARI
// ==========================================
const float G_CONSTANT = 16384.0;
float darbeSiniri = 1.5; 
float hareketToleransi = 0.5; 
int beklemeSuresi = 2000; 
int dusmeDurumu = 0;
unsigned long darbeZamani = 0;

// ==========================================
// *HAREKETSİZLİK AYARLARI*
// ==========================================
unsigned long sonHareketZamani = 0;
const unsigned long hareketsizlikLimiti = 60000; 
bool hareketsizlikUyarisiGonderildi = false;

// ==========================================
// 3. BLE VE GENEL DEĞİŞKENLER
// ==========================================
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E" 
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer* pServer = NULL;
BLECharacteristic* pTxCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

MAX30105 particleSensor;
const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;
float beatAvg = 0;
unsigned long sonGonderim = 0;

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) { deviceConnected = true; };
    void onDisconnect(BLEServer* pServer) { deviceConnected = false; }
};

void setup() {
  Serial.begin(115200);
  delay(2000); 

  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  pinMode(BUTTON_PIN, INPUT_PULLUP);

  // --- SEQUENTIAL BOOT START ---
  
  // 1. Start I2C Bus
  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(100000);
  delay(100);

  // 2. MAX30102 Initialization (Retry loop for stability)
  bool maxStarted = false;
  for(int i=0; i<3; i++) {
    if (particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
      maxStarted = true;
      break;
    }
    delay(500);
  }

  if (!maxStarted) {
    Serial.println("UYARI: Nabız Sensörü bulunamadı!");
  } else {
    Serial.println("Nabız Sensörü OK.");
    byte ledBrightness = 0x3F;
    byte sampleAverage = 4;    
    byte ledMode = 2;
    int sampleRate = 100;      
    int pulseWidth = 411; // Increased for better stability      
    int adcRange = 4096;       
    particleSensor.setup(ledBrightness, sampleAverage, ledMode, sampleRate, pulseWidth, adcRange);
    particleSensor.setPulseAmplitudeRed(0x3F);
    particleSensor.setPulseAmplitudeGreen(0);
  }

  // 3. MPU6050 Initialization
  delay(200);
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B); 
  Wire.write(0x00); 
  if(Wire.endTransmission(true) == 0) {
     Serial.println("MPU6050 OK.");
  } else {
     Serial.println("UYARI: MPU6050 bulunamadı!");
  }

  // 4. BLE Initialization (Last to avoid power sag)
  delay(200);
  BLEDevice::init("Akilli_Saat_Pro");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902());
  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE);
  pService->start();
  BLEDevice::startAdvertising();

  Serial.println("Sistem Hazır. Buton, Düşme ve Hareketsizlik Sensörü Aktif.");
  sonHareketZamani = millis();
}

void ivmeOku(int16_t &ax, int16_t &ay, int16_t &az) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom((uint8_t)MPU_ADDR, (size_t)6, true);
  if (Wire.available() == 6) {
    ax = Wire.read() << 8 | Wire.read();
    ay = Wire.read() << 8 | Wire.read();
    az = Wire.read() << 8 | Wire.read();
  }
}

void loop() {
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); pServer->startAdvertising(); oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) oldDeviceConnected = deviceConnected;

  // I2C STABILITY: Keep MAX30102 buffer moving
  particleSensor.check(); 

  // 0. ACİL DURUM BUTONU
  if (digitalRead(BUTTON_PIN) == LOW) {
    Serial.println("\n!!! ACIL YARDIM BUTONU BASILDI !!!");
    digitalWrite(BUZZER_PIN, HIGH);
    if (deviceConnected) {
      pTxCharacteristic->setValue("ALARM: BUTON BASILDI!"); 
      pTxCharacteristic->notify();
    }
    delay(1000); 
    digitalWrite(BUZZER_PIN, LOW);
    while(digitalRead(BUTTON_PIN) == LOW) { delay(50); }
  }

  // 1. NABIZ OKUMA
  long irValue = particleSensor.getIR();
  if (irValue > 50000) { // Stable threshold
    if (checkForBeat(irValue) == true) {
      long delta = millis() - lastBeat;
      lastBeat = millis();
      float rawBpm = 60 / (delta / 1000.0);
      if (rawBpm > 40 && rawBpm < 180) {
        rates[rateSpot++] = (byte)rawBpm;
        rateSpot %= RATE_SIZE;
        long total = 0;
        for (byte x = 0; x < RATE_SIZE; x++) total += rates[x];
        beatAvg = total / (float)RATE_SIZE;
      }
    }
  } else {
    beatAvg = 0;
  }

  // 2. İVME & HAREKETSİZLİK
  int16_t ax, ay, az;
  ivmeOku(ax, ay, az);
  float toplamIvme = sqrt(pow(ax, 2) + pow(ay, 2) + pow(az, 2)) / G_CONSTANT;

  if (abs(toplamIvme - 1.0) > hareketToleransi) {
      sonHareketZamani = millis(); 
      hareketsizlikUyarisiGonderildi = false;
  }

  if (millis() - sonHareketZamani > hareketsizlikLimiti) {
      if (!hareketsizlikUyarisiGonderildi) {
          Serial.println("UYARI: UZUN SURE HAREKETSIZLIK!");
          if (deviceConnected) {
              pTxCharacteristic->setValue("ALARM: HAREKETSIZLIK ALGILANDI!");
              pTxCharacteristic->notify();
          }
          digitalWrite(BUZZER_PIN, HIGH); delay(200); digitalWrite(BUZZER_PIN, LOW);
          hareketsizlikUyarisiGonderildi = true; 
      }
  }

  // 3. DÜŞME ALGORİTMASI
  if (dusmeDurumu == 0) {
    if (toplamIvme > darbeSiniri) {
      Serial.println("\n!!! SIDDETLI DARBE !!!");
      darbeZamani = millis();
      dusmeDurumu = 1; 
    }
  }
  else if (dusmeDurumu == 1) {
    if (millis() - darbeZamani >= beklemeSuresi) {
      dusmeDurumu = 2;
    }
  }
  else if (dusmeDurumu == 2) {
      bool hareketTespitEdildi = false;
      for(int i=0; i<50; i++) {
         ivmeOku(ax, ay, az);
         float anlikIvme = sqrt(pow(ax, 2) + pow(ay, 2) + pow(az, 2)) / G_CONSTANT;
         if(abs(anlikIvme - 1.0) > hareketToleransi) {
            hareketTespitEdildi = true; break;
         }
         particleSensor.check(); 
         delay(60);
      }
      if (hareketTespitEdildi) {
         dusmeDurumu = 0; 
      } else {
         Serial.println("* DUSME ONAYLANDI! *");
         digitalWrite(BUZZER_PIN, HIGH);
         delay(500); digitalWrite(BUZZER_PIN, LOW);
         if (deviceConnected) {
            pTxCharacteristic->setValue("ALARM: DUSME ONAYLANDI!");
            pTxCharacteristic->notify();
         }
         dusmeDurumu = 0;
      }
  }

  // 4. VERİ GÖNDERME
  if (millis() - sonGonderim > 1000) {
    sonGonderim = millis();
    String durumStr = "NORMAL";
    if(dusmeDurumu != 0) durumStr = "ANALIZ";
    if(hareketsizlikUyarisiGonderildi) durumStr = "HAREKETSIZ";
    
    Serial.print("BPM: "); Serial.print(beatAvg);
    Serial.print(" | Durum: "); Serial.println(durumStr);
    
    if (deviceConnected) {
      String veri = "NABIZ:" + String((int)beatAvg) + " | MOD:" + durumStr;
      pTxCharacteristic->setValue(veri.c_str());
      pTxCharacteristic->notify();
    }
  }
}