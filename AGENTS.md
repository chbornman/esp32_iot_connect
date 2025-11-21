# Agent Guidelines for ESP32 IoT Connect

## Project Structure
- **esp32_iot_program/**: ESP-IDF firmware (C) for ESP32-C6 with BLE + LCD
- **flutter_iot_app/**: Flutter mobile app (Dart) for BLE device control

## Build/Test Commands

### ESP32 Firmware
```bash
cd esp32_iot_program
. $HOME/esp/esp-idf/export.sh  # Setup ESP-IDF environment
idf.py set-target esp32c6      # Set target (first time only)
idf.py build                   # Build firmware
idf.py -p /dev/ttyUSB0 flash   # Flash to device
idf.py -p /dev/ttyUSB0 monitor # Monitor serial output
```

### Flutter App
```bash
cd flutter_iot_app
flutter pub get                # Install dependencies
flutter analyze                # Run static analysis
flutter test                   # Run all tests
flutter test test/widget_test.dart  # Run single test file
flutter run                    # Run on connected device
flutter build apk              # Build Android APK
```

## Code Style

### ESP32 C Code (main.c)
- **Includes**: Group system includes, then FreeRTOS, then ESP-specific, then drivers
- **Naming**: snake_case for functions/variables, SCREAMING_SNAKE_CASE for defines/macros
- **Logging**: Use ESP_LOGI/ESP_LOGE/ESP_LOGW with TAG constant
- **Error handling**: Always check ESP_ERROR_CHECK() for critical operations
- **Comments**: Use /* */ for multi-line, // for single-line explanations
- **Initialization**: Separate init functions (init_lcd, init_lvgl, init_ble)

### Flutter Dart Code (lib/main.dart)
- **Imports**: dart/flutter first, then packages, then relative imports
- **Naming**: camelCase for variables/functions, PascalCase for classes, SCREAMING_SNAKE_CASE for constants
- **Formatting**: Follow flutter_lints rules (dart format is enforced)
- **State**: Use StatefulWidget with State classes for interactive UI
- **Error handling**: Use try-catch with print() for BLE operations, show user feedback via SnackBar
- **Async**: Properly await Futures, check mounted before setState in async callbacks
- **BLE UUIDs**: Match ESP32 service (0x00FF) and characteristics (0xFF01 color, 0xFF02 text)

## Testing
- Flutter: Default widget_test.dart exists but needs updating for actual app functionality
- ESP32: Test via serial monitor logs and physical BLE connection
