# ESP32 IoT BLE Display Controller

ESP-IDF project for controlling an ESP32-C6 with 1.47" LCD display via Bluetooth Low Energy.

## Features

- **BLE Server**: Device presents as "ESP32_IoT_Display" on startup
- **LCD Control**: 172x320 ST7789 display support
- **Two BLE Commands**:
  1. **Set Color**: Change the screen color (RGB565 format)
  2. **Display Text**: Show text on screen (visual feedback with flash)

## Hardware

- ESP32-C6
- 1.47" ST7789 LCD (172x320 resolution)
- Pin configuration:
  - MOSI: GPIO 6
  - CLK: GPIO 7
  - CS: GPIO 14
  - DC: GPIO 15
  - RST: GPIO 21
  - Backlight: GPIO 22

## BLE Service

- **Device Name**: ESP32_IoT_Display
- **Service UUID**: 0x00FF
- **Characteristics**:
  - **Color Control**: UUID 0xFF01 (Write, Read)
    - Write 2 bytes: RGB565 color format (e.g., 0xF800 for red)
  - **Text Display**: UUID 0xFF02 (Write, Read)
    - Write string: Text to display (triggers visual feedback)

## Building and Flashing

```bash
# Set up ESP-IDF environment
. $HOME/esp/esp-idf/export.sh

# Navigate to project
cd esp32_iot_program

# Configure for your board (if needed)
idf.py set-target esp32c6

# Build
idf.py build

# Flash and monitor
idf.py -p /dev/ttyUSB0 flash monitor
```

## Testing with Flutter

The device will automatically start advertising on boot. Connect from your Flutter app using flutter_blue_plus:

1. Scan for device named "ESP32_IoT_Display"
2. Connect to the device
3. Discover services
4. Write to characteristics:
   - **0xFF01**: Send 2 bytes for color (big-endian RGB565)
   - **0xFF02**: Send string for text display

## Color Examples (RGB565)

- Black: 0x0000
- White: 0xFFFF
- Red: 0xF800
- Green: 0x07E0
- Blue: 0x001F
- Yellow: 0xFFE0
- Cyan: 0x07FF
- Magenta: 0xF81F

## Visual Feedback

- **Connection**: Green flash at top of screen
- **Disconnection**: Red flash at top of screen
- **Text Received**: White flash at top of screen

## Notes

- Text rendering uses visual feedback only (flashing). For full text rendering, integrate a font library like LVGL or custom bitmap fonts.
- The device will automatically start advertising after boot and after disconnection.
