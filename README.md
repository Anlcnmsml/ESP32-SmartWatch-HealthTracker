Health Guard: ESP32-Based Wearable Safety System
This repository contains the embedded firmware and mobile application source code for a wearable health monitor. The system is designed to provide real-time alerts for four critical emergency scenarios through sensor fusion and BLE communication.

🧠 Core Emergency Scenarios
The firmware implements a State Machine logic to monitor and report four distinct emergency states:

1.Fall Detection (2-Stage Logic):

Impact Detection: Uses the MPU6050 to detect a sudden acceleration spike exceeding the 1.5G threshold (darbeSiniri).
Stability Verification: After an impact, the system monitors for movement for a predefined period. If the user remains stationary (hareketToleransi), a fall is confirmed.
Alert: Triggers the local buzzer and sends ALARM: DUSME ONAYLANDI! to the mobile app.

2.Prolonged Inactivity (Fainting Detection):

Logic: Tracks the duration of stationary behavior.
Trigger: If no significant movement is detected for 60 seconds (hareketsizlikLimiti), an alert is triggered to address potential fainting or loss of consciousness.
Alert: Transmits ALARM: HAREKETSIZLIK ALGILANDI! notification.

3.Real-Time Heart Rate Monitoring:

Sensor: High-sensitivity MAX30105 (Integrated due to hardware iteration/stability requirements).
Filtering: Implements a 4-sample Moving Average Filter to stabilize biometric data.
Thresholds: Only processes valid heart rates between 40 BPM and 180 BPM, rejecting physiological outliers and noise.

4.Manual SOS Button (Fail-Safe):

Hardware: A physical tactile push-button (GPIO 3) that acts as an immediate override.
Action: Instantly bypasses sensor analysis to trigger the buzzer and send a priority ALARM: BUTON BASILDI! alert to caregivers.

🛠 Hardware Specifications

Microcontroller: ESP32-C3 Mini (Custom I2C: SDA=10, SCL=1).
Sensors: MAX30105 (Biometric), MPU6050 (Inertial).
Connectivity: Bluetooth Low Energy (BLE) using GATT Notify for real-time dashboarding.

📱 Mobile Application & System Integration (Flutter)

The device is integrated with a custom-built Flutter mobile application to provide a seamless health dashboard and emergency management interface.

Real-time Data Pipeline: Biometric and motion data are streamed from the ESP32-C3 to the smartphone using BLE GATT Services, ensuring low-latency updates.
Dual-Mode Connectivity (Fail-safe): The system prioritizes BLE for local monitoring but automatically switches to Wi-Fi and Firebase Realtime Database if the Bluetooth connection is lost, ensuring continuous remote oversight.
Visual & Audible Alerting: Upon receiving an alarm signal (Fall, Inactivity, or SOS), the app triggers a high-priority alert screen with distinctive colors (Red for Falls, Orange for Inactivity) and a countdown timer for user cancellation.
Threshold Configuration: Users can customize heart rate limits and sensitivity settings directly through the app interface.
Event Logging: All emergency events and historical heart rate data are timestamped and logged for post-event clinical evaluation.
