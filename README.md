# ESP32 IoT Connect

A complete IoT solution consisting of an ESP32-C6 device with LCD display and a Flutter mobile app for BLE control.

## Project Structure

```
esp32_iot_connect/
├── esp32_iot_program/    # ESP-IDF firmware for ESP32-C6
└── flutter_iot_app/      # Flutter mobile app for BLE control
```

## Overview

This project demonstrates a full-stack IoT application with:
- **ESP32-C6 Device**: BLE server with 1.47" LCD display (ST7789, 172x320)
- **Flutter App**: Cross-platform mobile app for controlling the device via Bluetooth Low Energy

## Features

### ESP32 Firmware
- BLE Server advertising as "ESP32_IoT_Display"
- LCD display control (ST7789 driver)
- Two BLE characteristics:
  - **Color Control** (0xFF01): Change screen color via RGB565 format
  - **Text Display** (0xFF02): Display text with visual feedback
- Visual connection/disconnection indicators
- Automatic advertising on boot and after disconnect

### Flutter App
- BLE device scanning and connection
- Control ESP32 display remotely
- Send colors and text commands
- Cross-platform support (Android, iOS, etc.)

## Hardware Requirements

- ESP32-C6 development board
- 1.47" ST7789 LCD display (172x320 resolution)

**Pin Configuration:**
- MOSI: GPIO 6
- CLK: GPIO 7
- CS: GPIO 14
- DC: GPIO 15
- RST: GPIO 21
- Backlight: GPIO 22

## Getting Started

### ESP32 Firmware

1. **Install ESP-IDF**
   ```bash
   # Follow official ESP-IDF installation guide
   # https://docs.espressif.com/projects/esp-idf/en/latest/esp32c6/get-started/
   ```

2. **Build and Flash**
   ```bash
   # Set up environment
   . $HOME/esp/esp-idf/export.sh

   # Navigate to firmware directory
   cd esp32_iot_program

   # Set target
   idf.py set-target esp32c6

   # Build
   idf.py build

   # Flash and monitor
   idf.py -p /dev/ttyUSB0 flash monitor
   ```

### Flutter App

1. **Install Flutter**
   ```bash
   # Follow official Flutter installation guide
   # https://docs.flutter.dev/get-started/install
   ```

2. **Run the App**
   ```bash
   cd flutter_iot_app

   # Get dependencies
   flutter pub get

   # Run on connected device
   flutter run
   ```

## BLE Communication Protocol

### Service UUID
- **Service**: 0x00FF

### Characteristics

#### Color Control (0xFF01)
- **Type**: Write, Read
- **Format**: 2 bytes (RGB565)
- **Examples**:
  - Red: `0xF800`
  - Green: `0x07E0`
  - Blue: `0x001F`
  - White: `0xFFFF`
  - Black: `0x0000`

#### Text Display (0xFF02)
- **Type**: Write, Read
- **Format**: UTF-8 string
- **Effect**: Displays text with white flash feedback

## Visual Feedback

The ESP32 device provides visual indicators:
- **Green flash**: Device connected
- **Red flash**: Device disconnected
- **White flash**: Text command received

## Development

### ESP32 Development
See [esp32_iot_program/README.md](esp32_iot_program/README.md) for detailed firmware documentation.

### Flutter Development
See [flutter_iot_app/README.md](flutter_iot_app/README.md) for Flutter app details.

## License

This project is open source and available under the MIT License.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

For issues and questions, please open an issue on GitHub.
