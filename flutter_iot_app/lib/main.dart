import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flex_color_picker/flex_color_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 IoT Connect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BluetoothScannerPage(),
    );
  }
}

class BluetoothScannerPage extends StatefulWidget {
  const BluetoothScannerPage({super.key});

  @override
  State<BluetoothScannerPage> createState() => _BluetoothScannerPageState();
}

class _BluetoothScannerPageState extends State<BluetoothScannerPage> {
  List<ScanResult> scanResults = [];
  bool isScanning = false;

  // Filter for specific device name
  static const String TARGET_DEVICE_NAME = "SusanESP";

  @override
  void initState() {
    super.initState();
    _requestPermissions();

    // Listen to scan results and filter for target device
    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          // Filter to only show devices with our target name
          scanResults = results.where((result) {
            return result.device.platformName == TARGET_DEVICE_NAME;
          }).toList();
        });
      }
    });

    // Listen to scanning state
    FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) {
        setState(() {
          isScanning = scanning;
        });
      }
    });
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetoothScan]!.isDenied ||
        statuses[Permission.bluetoothConnect]!.isDenied ||
        statuses[Permission.location]!.isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth permissions are required to scan for devices'),
          ),
        );
      }
    }
  }

  Future<void> _startScan() async {
    try {
      setState(() {
        scanResults.clear();
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting scan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      print('[BLE] Attempting to connect to ${device.platformName} (${device.remoteId})');
      await device.connect();
      print('[BLE] Connection successful!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device.platformName}'),
            backgroundColor: Colors.green,
          ),
        );
        // Navigate to device control page
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DeviceControlPage(device: device),
          ),
        );
      }
    } catch (e) {
      print('[BLE] Connection failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('ESP32 IoT Connect'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: isScanning ? null : _startScan,
              icon: Icon(isScanning ? Icons.hourglass_empty : Icons.search),
              label: Text(isScanning ? 'Scanning...' : 'Scan for Devices'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ),
          Expanded(
            child: scanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isScanning
                              ? 'Scanning for "$TARGET_DEVICE_NAME"...'
                              : 'No "$TARGET_DEVICE_NAME" device found.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isScanning
                              ? 'Make sure your device is powered on.'
                              : 'Tap "Scan for Devices" to start searching.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: scanResults.length,
                    itemBuilder: (context, index) {
                      final result = scanResults[index];
                      final device = result.device;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.bluetooth, color: Colors.blue),
                          title: Text(
                            device.platformName.isNotEmpty
                                ? device.platformName
                                : 'Unknown Device',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID: ${device.remoteId}'),
                              Text('RSSI: ${result.rssi} dBm'),
                            ],
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _connectToDevice(device),
                            child: const Text('Connect'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Device Control Page
class DeviceControlPage extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceControlPage({super.key, required this.device});

  @override
  State<DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<DeviceControlPage> {
  final TextEditingController _textController = TextEditingController();
  BluetoothCharacteristic? _textCharacteristic;
  BluetoothCharacteristic? _colorCharacteristic;
  bool isDiscovering = true;
  bool isConnected = true;
  String statusMessage = 'Discovering services...';
  Color selectedColor = Colors.red;

  // ESP32 UUIDs from the C code (short form)
  static const String SERVICE_UUID_SHORT = "00ff";
  static const String COLOR_CHAR_UUID_SHORT = "ff01";
  static const String TEXT_CHAR_UUID_SHORT = "ff02";

  // Full 128-bit UUIDs
  static const String SERVICE_UUID = "0000ff00-0000-1000-8000-00805f9b34fb";
  static const String COLOR_CHAR_UUID = "0000ff01-0000-1000-8000-00805f9b34fb";
  static const String TEXT_CHAR_UUID = "0000ff02-0000-1000-8000-00805f9b34fb";

  @override
  void initState() {
    super.initState();
    _discoverServices();
    _setupConnectionListener();
  }

  void _setupConnectionListener() {
    print('[BLE] Setting up connection state listener');
    widget.device.connectionState.listen((BluetoothConnectionState state) {
      print('[BLE] Connection state changed: $state');

      if (state == BluetoothConnectionState.disconnected) {
        print('[BLE] Device disconnected!');
        setState(() {
          isConnected = false;
          statusMessage = 'Device disconnected';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device disconnected!'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );

          // Navigate back to scanner page after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.pop(context);
            }
          });
        }
      } else if (state == BluetoothConnectionState.connected) {
        print('[BLE] Device connected');
        setState(() {
          isConnected = true;
        });
      }
    });
  }

  Future<void> _discoverServices() async {
    try {
      print('[BLE] Starting service discovery...');
      List<BluetoothService> services = await widget.device.discoverServices();
      print('[BLE] Found ${services.length} services');

      for (BluetoothService service in services) {
        String serviceUuidStr = service.uuid.toString().toLowerCase();
        print('[BLE] Service UUID: $serviceUuidStr');

        // Check if this is our service (match both short and full form)
        bool isTargetService = serviceUuidStr == SERVICE_UUID.toLowerCase() ||
                               serviceUuidStr == SERVICE_UUID_SHORT.toLowerCase() ||
                               serviceUuidStr.contains(SERVICE_UUID_SHORT.toLowerCase());

        if (isTargetService) {
          print('[BLE] Found target service!');
          print('[BLE] Service has ${service.characteristics.length} characteristics');

          for (BluetoothCharacteristic characteristic in service.characteristics) {
            String charUuidStr = characteristic.uuid.toString().toLowerCase();
            print('[BLE] Characteristic UUID: $charUuidStr');

            // Check if this is the color characteristic
            bool isColorChar = charUuidStr == COLOR_CHAR_UUID.toLowerCase() ||
                              charUuidStr == COLOR_CHAR_UUID_SHORT.toLowerCase() ||
                              charUuidStr.contains(COLOR_CHAR_UUID_SHORT.toLowerCase());

            // Check if this is the text characteristic (match both short and full form)
            bool isTextChar = charUuidStr == TEXT_CHAR_UUID.toLowerCase() ||
                             charUuidStr == TEXT_CHAR_UUID_SHORT.toLowerCase() ||
                             charUuidStr.contains(TEXT_CHAR_UUID_SHORT.toLowerCase());

            if (isColorChar) {
              print('[BLE] Found color characteristic!');
              print('[BLE] Properties: read=${characteristic.properties.read}, write=${characteristic.properties.write}');
              setState(() {
                _colorCharacteristic = characteristic;
              });
            }

            if (isTextChar) {
              print('[BLE] Found text characteristic!');
              print('[BLE] Properties: read=${characteristic.properties.read}, write=${characteristic.properties.write}');
              setState(() {
                _textCharacteristic = characteristic;
              });
            }

            // Update status when we have both characteristics
            if (_colorCharacteristic != null && _textCharacteristic != null) {
              setState(() {
                isDiscovering = false;
                statusMessage = 'Ready to control device!';
              });
            }
          }
        }
      }

      // Check if we found the characteristics
      if (_colorCharacteristic != null || _textCharacteristic != null) {
        setState(() {
          isDiscovering = false;
          statusMessage = _colorCharacteristic != null && _textCharacteristic != null
              ? 'Ready to control device!'
              : 'Some characteristics found';
        });
      } else {
        print('[BLE] Characteristics not found in any service');
        setState(() {
          isDiscovering = false;
          statusMessage = 'Characteristics not found';
        });
      }
    } catch (e) {
      print('[BLE] Error discovering services: $e');
      setState(() {
        isDiscovering = false;
        statusMessage = 'Error discovering services: $e';
      });
    }
  }

  Future<void> _sendToDisplay() async {
    bool colorSent = false;
    bool textSent = false;
    String message = '';

    // Send color first if characteristic is available
    if (_colorCharacteristic != null) {
      try {
        String hexColor = _colorToHexString(selectedColor);
        List<int> colorBytes = utf8.encode(hexColor);
        print('[BLE] Sending color: $hexColor (${colorBytes.length} bytes)');

        await _colorCharacteristic!.write(colorBytes);
        print('[BLE] Color write successful!');
        colorSent = true;
        message = 'Color sent';
      } catch (e) {
        print('[BLE] Color write failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send color: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }

    // Send text if characteristic is available and text is not empty
    if (_textCharacteristic != null && _textController.text.isNotEmpty) {
      try {
        final text = _textController.text;
        List<int> bytes = utf8.encode(text);
        print('[BLE] Sending text: "$text" (${bytes.length} bytes)');

        await _textCharacteristic!.write(bytes);
        print('[BLE] Text write successful!');
        textSent = true;

        if (colorSent) {
          message = 'Color and text sent!';
        } else {
          message = 'Text sent: $text';
        }

        _textController.clear();
      } catch (e) {
        print('[BLE] Text write failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send text: $e'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } else if (colorSent && _textController.text.isEmpty) {
      // Only color was sent (no text to send)
      message = 'Color sent!';
    }

    // Show success message if anything was sent
    if (colorSent || textSent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (colorSent) ...[
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: selectedColor,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to send. Enter text or select a color.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Convert Color to hex string format (easier and supported by ESP32)
  String _colorToHexString(Color color) {
    // Extract RGB components (0-255)
    int r = color.red;
    int g = color.green;
    int b = color.blue;

    // Convert to hex string format: #RRGGBB
    String hexColor = '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();

    print('[BLE] Color RGB($r,$g,$b) -> Hex: $hexColor');

    return hexColor;
  }

  Future<void> _showColorPicker() async {
    Color tempColor = selectedColor;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pick a color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              color: tempColor,
              onColorChanged: (Color color) {
                tempColor = color;
              },
              pickersEnabled: const <ColorPickerType, bool>{
                ColorPickerType.both: false,
                ColorPickerType.primary: true,
                ColorPickerType.accent: false,
                ColorPickerType.bw: false,
                ColorPickerType.custom: false,
                ColorPickerType.wheel: true,
              },
              heading: Text(
                'Select color',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subheading: Text(
                'Select color shade',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('OK'),
              onPressed: () {
                setState(() {
                  selectedColor = tempColor;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _disconnect() async {
    print('[BLE] Disconnecting from ${widget.device.platformName}');
    await widget.device.disconnect();
    print('[BLE] Disconnected successfully');
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isConnected
            ? Theme.of(context).colorScheme.inversePrimary
            : Colors.red.shade400,
        title: Row(
          children: [
            Icon(
              isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.device.platformName.isNotEmpty
                    ? widget.device.platformName
                    : 'ESP32 Device',
              ),
            ),
          ],
        ),
        actions: [
          if (isConnected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnect,
              tooltip: 'Disconnect',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status indicator
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: !isConnected
                    ? Colors.red.shade100
                    : (isDiscovering
                        ? Colors.orange.shade100
                        : (_textCharacteristic != null || _colorCharacteristic != null
                            ? Colors.green.shade100
                            : Colors.red.shade100)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    !isConnected
                        ? Icons.bluetooth_disabled
                        : (isDiscovering
                            ? Icons.hourglass_empty
                            : (_textCharacteristic != null || _colorCharacteristic != null
                                ? Icons.check_circle
                                : Icons.error)),
                    color: !isConnected
                        ? Colors.red
                        : (isDiscovering
                            ? Colors.orange
                            : (_textCharacteristic != null || _colorCharacteristic != null
                                ? Colors.green
                                : Colors.red)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      statusMessage,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Color picker section
            const Text(
              'Change Display Color:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Selected Color:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: selectedColor,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade400, width: 2),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '#${selectedColor.value.toRadixString(16).substring(2).toUpperCase()}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: (isConnected && _colorCharacteristic != null && !isDiscovering)
                            ? _showColorPicker
                            : null,
                        icon: const Icon(Icons.palette),
                        label: const Text('Pick Color'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  if (_colorCharacteristic == null && !isDiscovering)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Color characteristic not available',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Text input section
            const Text(
              'Send Text to Display:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Enter text (optional)',
                hintText: 'Type a message...',
                helperText: _textCharacteristic == null ? 'Text characteristic not available' : null,
              ),
              maxLength: 100,
              enabled: isConnected && _textCharacteristic != null && !isDiscovering,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: (isConnected &&
                         !isDiscovering &&
                         (_textCharacteristic != null || _colorCharacteristic != null))
                  ? _sendToDisplay
                  : null,
              icon: const Icon(Icons.send),
              label: Text(isConnected ? 'Send to Display' : 'Disconnected'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: isConnected ? Colors.blue : Colors.grey,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 24),

            // Info text
            SizedBox(
              height: 150,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isConnected ? Icons.info_outline : Icons.warning_amber_rounded,
                      size: 48,
                      color: isConnected ? Colors.grey : Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isConnected
                          ? 'Control your ESP32 display with colors and text'
                          : 'Connection lost. Returning to scanner...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isConnected ? Colors.grey : Colors.red,
                        fontSize: 14,
                        fontWeight: isConnected ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
