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
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  BluetoothDevice? connectedDevice;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void setConnectedDevice(BluetoothDevice device) {
    setState(() {
      connectedDevice = device;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          BluetoothScanPage(onDeviceConnected: setConnectedDevice),
          if (connectedDevice != null)
            PosturePage(device: connectedDevice!)
          else
            Center(child: Text('Please connect to a device first')),
          LogPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.accessibility_new),
            label: 'Posture',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Log',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

class BluetoothScanPage extends StatefulWidget {
  final Function(BluetoothDevice) onDeviceConnected;

  const BluetoothScanPage({Key? key, required this.onDeviceConnected}) : super(key: key);

  @override
  _BluetoothScanPageState createState() => _BluetoothScanPageState();
}

class _BluetoothScanPageState extends State<BluetoothScanPage> {
  List<ScanResult> scanResults = [];
  bool _isScanning = false;
  bool _mounted = false;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  @override
  void initState() {
    super.initState();
    _mounted = true;
    requestPermissions();
    initBluetooth();
  }

  @override
  void dispose() {
    _mounted = false;
    _scanResultsSubscription?.cancel();
    super.dispose();
  }

  void requestPermissions() async {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
  }

  void initBluetooth() {
    FlutterBluePlus.isScanning.listen((isScanning) {
      if (_mounted) {
        setState(() {
          _isScanning = isScanning;
        });
      }
    });
  }

  void scanForDevices() async {
    if (!_isScanning) {
      if (_mounted) {
        setState(() {
          scanResults.clear();
        });
      }
      try {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
        _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
          if (_mounted) {
            setState(() {
              scanResults = results;
            });
          }
        });
      } catch (e) {
        print('Error starting scan: $e');
      }
    } else {
      await FlutterBluePlus.stopScan();
    }
  }

  void connectToDevice(ScanResult result) async {
    await FlutterBluePlus.stopScan();
    try {
      await result.device.connect();
      widget.onDeviceConnected(result.device);
      // 연결 성공 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${result.device.name}')),
      );
    } catch (e) {
      print('Failed to connect: $e');
      // 연결 실패 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth Scan'),
        actions: [
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.search),
            onPressed: scanForDevices,
          ),
        ],
      ),
      body: ListView.builder(
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
      ),
    );
  }
}

class PosturePage extends StatefulWidget {
  final BluetoothDevice device;
  const PosturePage({Key? key, required this.device}) : super(key: key);
  @override
  _PosturePageState createState() => _PosturePageState();
}

class _PosturePageState extends State<PosturePage> {
  List<BluetoothService> bluetoothServices = [];
  StreamSubscription<List<int>>? dataSubscription;

  Map<String, double> sensorData = {
    'AccX': 0, 'AccY': 0, 'AccZ': 0,
    'AngX': 0, 'AngY': 0, 'AngZ': 0,
  };
  String direction = 'N/A';
  String previousDirection = '';
  String logMessage = '';
  Stopwatch directionStopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    startWorkingWithDevice(widget.device);
  }

  void startWorkingWithDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      discoverServices();
    } catch (e) {
      print('Failed to connect: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: ${e.toString()}')),
      );
    }
  }

  void discoverServices() async {
    bluetoothServices = await widget.device.discoverServices();
    for (var service in bluetoothServices) {
      if (service.uuid.toString() == '0000ffe5-0000-1000-8000-00805f9a34fb') {
        for (var characteristic in service.characteristics) {
          if (characteristic.uuid.toString() == '0000ffe4-0000-1000-8000-00805f9a34fb') {
            await characteristic.setNotifyValue(true);
            dataSubscription = characteristic.value.listen((value) {
              if (value.isNotEmpty) {
                processData(value);
              }
            });
            break;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Posture Detection'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connected Device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('Name: ${widget.device.name}'),
              Text('ID: ${widget.device.id}'),
              SizedBox(height: 20),
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
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    dataSubscription?.cancel();
    widget.device.disconnect();
    directionStopwatch.stop();
    super.dispose();
  }
}

class LogPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Records'),
      ),
      body: Center(
        child: Text('Log records will be displayed here'),
      ),
    );
  }
}
