import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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

  @override
  void initState() {
    super.initState();
    _requestPermissions();

    // Listen to scan results
    FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          scanResults = results;
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
                    child: Text(
                      isScanning
                          ? 'Scanning for Bluetooth devices...'
                          : 'No devices found. Tap "Scan for Devices" to start.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
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
  bool isDiscovering = true;
  bool isConnected = true;
  String statusMessage = 'Discovering services...';

  // ESP32 UUIDs from the C code (short form)
  static const String SERVICE_UUID_SHORT = "00ff";
  static const String TEXT_CHAR_UUID_SHORT = "ff02";

  // Full 128-bit UUIDs
  static const String SERVICE_UUID = "0000ff00-0000-1000-8000-00805f9b34fb";
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

            // Check if this is the text characteristic (match both short and full form)
            bool isTextChar = charUuidStr == TEXT_CHAR_UUID.toLowerCase() ||
                             charUuidStr == TEXT_CHAR_UUID_SHORT.toLowerCase() ||
                             charUuidStr.contains(TEXT_CHAR_UUID_SHORT.toLowerCase());

            if (isTextChar) {
              print('[BLE] Found text characteristic!');
              print('[BLE] Properties: read=${characteristic.properties.read}, write=${characteristic.properties.write}');

              setState(() {
                _textCharacteristic = characteristic;
                isDiscovering = false;
                statusMessage = 'Ready to send messages!';
              });
              return;
            }
          }
        }
      }

      print('[BLE] Text characteristic not found in any service');
      setState(() {
        isDiscovering = false;
        statusMessage = 'Text characteristic not found';
      });
    } catch (e) {
      print('[BLE] Error discovering services: $e');
      setState(() {
        isDiscovering = false;
        statusMessage = 'Error discovering services: $e';
      });
    }
  }

  Future<void> _sendText() async {
    if (_textCharacteristic == null) {
      print('[BLE] Cannot send: text characteristic not available');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Text characteristic not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final text = _textController.text;
    if (text.isEmpty) {
      print('[BLE] Cannot send: text is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter some text'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Convert text to bytes
      List<int> bytes = utf8.encode(text);
      print('[BLE] Sending text: "$text" (${bytes.length} bytes)');
      print('[BLE] Bytes: $bytes');

      await _textCharacteristic!.write(bytes);
      print('[BLE] Write successful!');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sent: $text'),
          backgroundColor: Colors.green,
        ),
      );

      _textController.clear();
    } catch (e) {
      print('[BLE] Write failed: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send text: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
                        : (_textCharacteristic != null
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
                            : (_textCharacteristic != null
                                ? Icons.check_circle
                                : Icons.error)),
                    color: !isConnected
                        ? Colors.red
                        : (isDiscovering
                            ? Colors.orange
                            : (_textCharacteristic != null
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
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Enter text',
                hintText: 'Type a message...',
              ),
              maxLength: 100,
              enabled: isConnected && _textCharacteristic != null && !isDiscovering,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: (isConnected && _textCharacteristic != null && !isDiscovering)
                  ? _sendText
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
                          ? 'Your text will be sent to the ESP32 display'
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
