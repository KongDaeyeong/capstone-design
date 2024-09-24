import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Sensor App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const BluetoothScreen(),
    );
  }
}

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({Key? key}) : super(key: key);

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  FlutterBluePlus flutterBlue = FlutterBluePlus();
  List<ScanResult> scanResults = [];
  BluetoothDevice? connectedDevice;
  List<BluetoothService> bluetoothServices = [];
  bool _isScanning = false;

  Map<String, double> sensorData = {
    'AccX': 0, 'AccY': 0, 'AccZ': 0,
    'AngX': 0, 'AngY': 0, 'AngZ': 0,
  };
  String direction = 'N/A';
  String previousDirection = '';
  String logMessage = '';
  Stopwatch directionStopwatch = Stopwatch();
  Timer? updateTimer;

  @override
  void initState() {
    super.initState();
    requestPermissions();
    initBluetooth();
  }

  void requestPermissions() async {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
  }

  void initBluetooth() {
    FlutterBluePlus.isScanning.listen((isScanning) {
      setState(() {
        _isScanning = isScanning;
      });
    });
  }

  void scanForDevices() async {
    if (!_isScanning) {
      setState(() {
        scanResults.clear();
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          scanResults = results;
        });
      });
    } else {
      await FlutterBluePlus.stopScan();
    }
  }

  void connectToDevice(ScanResult result) async {
    await FlutterBluePlus.stopScan();
    try {
      await result.device.connect();
      setState(() {
        connectedDevice = result.device;
      });
      discoverServices(result.device);
    } catch (e) {
      print('Failed to connect: $e');
    }
  }

  void discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    setState(() {
      bluetoothServices = services;
    });

    for (BluetoothService service in services) {
      if (service.uuid.toString() == '0000ffe5-0000-1000-8000-00805f9a34fb') {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == '0000ffe4-0000-1000-8000-00805f9a34fb') {
            await characteristic.setNotifyValue(true);
            characteristic.value.listen((value) {
              processData(value);
            });
          }
        }
      }
    }
  }

  void processData(List<int> data) {
    if (data.length >= 20 && data[1] == 0x61) {
      setState(() {
        sensorData['AccX'] = getSignedInt16(data[3] << 8 | data[2]) / 32768 * 16;
        sensorData['AccY'] = getSignedInt16(data[5] << 8 | data[4]) / 32768 * 16;
        sensorData['AccZ'] = getSignedInt16(data[7] << 8 | data[6]) / 32768 * 16;
        sensorData['AngX'] = getSignedInt16(data[15] << 8 | data[14]) / 32768 * 180;
        sensorData['AngY'] = getSignedInt16(data[17] << 8 | data[16]) / 32768 * 180;
        sensorData['AngZ'] = getSignedInt16(data[19] << 8 | data[18]) / 32768 * 180;

        direction = classifyDirection();

        if (direction != previousDirection) {
          logMessage = 'Direction changed from $previousDirection to $direction';
          previousDirection = direction;
          directionStopwatch.reset();
          directionStopwatch.start();
        }
      });
    }
  }

  int getSignedInt16(int value) {
    if (value >= 32768) {
      value -= 65536;
    }
    return value;
  }

  String classifyDirection() {
    double accX = sensorData['AccX']!;
    double accZ = sensorData['AccZ']!;

    if (accZ >= 0.974) return 'front';
    if (accZ <= -0.8) return 'back';
    if (accX <= -0.9) return 'left';
    if (accX >= 0.9) return 'right';
    return 'neutral';
  }

  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }

  Widget deviceList() {
    return ListView.builder(
      itemCount: scanResults.length,
      itemBuilder: (context, index) {
        final result = scanResults[index];
        return ListTile(
          title: Text(result.device.name.isNotEmpty
              ? result.device.name
              : 'Unknown Device'),
          subtitle: Text(result.device.id.id),
          onTap: () => connectToDevice(result),
        );
      },
    );
  }

  Widget connectedDeviceView() {
    return Column(
      children: [
        Text('Connected to ${connectedDevice!.name}'),
        Expanded(
          child: ListView(
            children: [
              Text('Sensor Data', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ...sensorData.entries.map((entry) =>
                  Text('${entry.key}: ${entry.value.toStringAsFixed(3)}')
              ),
              SizedBox(height: 20),
              Text('Direction Info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('Current Direction: $direction'),
              StreamBuilder(
                stream: Stream.periodic(Duration(seconds: 1)),
                builder: (context, snapshot) {
                  return Text('Duration: ${formatDuration(directionStopwatch.elapsed)}');
                },
              ),
              SizedBox(height: 20),
              Text('Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(logMessage),
              SizedBox(height: 20),
              Text('Services', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ...bluetoothServices.map((service) {
                return ExpansionTile(
                  title: Text('Service: ${service.uuid}'),
                  children: service.characteristics.map((characteristic) {
                    return ListTile(
                      title: Text('Characteristic: ${characteristic.uuid}'),
                      subtitle: Text('Properties: ${characteristic.properties}'),
                    );
                  }).toList(),
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Sensor App'),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.search),
            onPressed: scanForDevices,
          ),
        ],
      ),
      body: connectedDevice == null ? deviceList() : connectedDeviceView(),
      bottomNavigationBar: BottomAppBar(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: scanForDevices,
                child: Text('Start'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (connectedDevice != null) {
                    connectedDevice!.disconnect();
                    setState(() {
                      connectedDevice = null;
                      bluetoothServices.clear();
                    });
                  }
                },
                child: Text('Stop'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (connectedDevice != null) {
                    connectedDevice!.disconnect();
                  }
                  setState(() {
                    connectedDevice = null;
                    bluetoothServices.clear();
                    sensorData = Map.fromIterables(sensorData.keys, List.filled(sensorData.length, 0.0));
                    direction = 'N/A';
                    logMessage = '';
                    directionStopwatch.reset();
                  });
                },
                child: Text('Shutdown'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    updateTimer?.cancel();
    if (connectedDevice != null) {
      connectedDevice!.disconnect();
    }
    super.dispose();
  }
}
