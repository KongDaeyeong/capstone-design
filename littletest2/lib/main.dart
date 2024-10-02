import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// DB와 캘린더 기능 추가..
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_package;
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

import 'package:fl_chart/fl_chart.dart';

// DB 관련 코드
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('posture_logs.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = path_package.join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE posture_logs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT,
        fromDirection TEXT,
        toDirection TEXT,
        duration INTEGER
      )
    ''');
  }

  Future<int> insertLog(PostureLogEntry log) async {
    final db = await database;
    return await db.insert('posture_logs', {
      'timestamp': log.timestamp.toIso8601String(),
      'fromDirection': log.fromDirection,
      'toDirection': log.toDirection,
      'duration': log.duration.inSeconds,
    });
  }

  Future<List<PostureLogEntry>> getLogsByDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(Duration(days: 1));

    final maps = await db.query(
      'posture_logs',
      where: 'timestamp BETWEEN ? AND ?',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'timestamp DESC',
    );

    return List.generate(maps.length, (i) {
      return PostureLogEntry(
        timestamp: DateTime.parse(maps[i]['timestamp'] as String),
        fromDirection: maps[i]['fromDirection'] as String,
        toDirection: maps[i]['toDirection'] as String,
        duration: Duration(seconds: maps[i]['duration'] as int),
      );
    });
  }
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

class PostureLogEntry {
  final DateTime timestamp;
  final String fromDirection;
  final String toDirection;
  final Duration duration;

  PostureLogEntry({
    required this.timestamp,
    required this.fromDirection,
    required this.toDirection,
    required this.duration,
  });
}

class PostureLogManager extends ChangeNotifier {
  List<PostureLogEntry> _logs = [];
  // DB
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  List<PostureLogEntry> get logs => List.unmodifiable(_logs);

  Future<void> addLog(PostureLogEntry entry) async {
    await _dbHelper.insertLog(entry);
    _logs.add(entry);
    notifyListeners();
  }

  Future<void> loadLogsByDate(DateTime date) async {
    _logs = await _dbHelper.getLogsByDate(date);
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  final DarwinInitializationSettings initializationSettingsIOS =
  DarwinInitializationSettings();


  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => PostureLogManager()),
      ],
      child: const MyApp(),
    ),
  );
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

  void setConnectedDevice(BluetoothDevice? device) {
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
          BluetoothScanPage(onDeviceConnected: setConnectedDevice,
            connectedDevice: connectedDevice,),
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
  final Function(BluetoothDevice?) onDeviceConnected;
  final BluetoothDevice? connectedDevice;

  const BluetoothScanPage({Key? key, required this.onDeviceConnected, required this.connectedDevice}) : super(key: key);

  @override
  _BluetoothScanPageState createState() => _BluetoothScanPageState();
}

class _BluetoothScanPageState extends State<BluetoothScanPage> {
  List<ScanResult> scanResults = [];
  bool _isScanning = false;
  bool _mounted = false;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  DateTime? _connectionStartTime;
  Timer? _connectionTimer;

  @override
  void initState() {
    super.initState();
    _mounted = true;
    requestPermissions();
    initBluetooth();
    if (widget.connectedDevice != null) {
      _connectionStartTime = DateTime.now();
      _startConnectionTimer();
    }
  }

  @override
  void dispose() {
    _mounted = false;
    _scanResultsSubscription?.cancel();
    _connectionTimer?.cancel();
    super.dispose();
  }

  void requestPermissions() async {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
    await Permission.notification.request();
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
      setState(() {
        _connectionStartTime = DateTime.now();
      });
      _startConnectionTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${result.device.name}')),
      );
    } catch (e) {
      print('Failed to connect: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect: ${e.toString()}')),
      );
    }
  }

  void disconnectDevice() async {
    try {
      await widget.connectedDevice?.disconnect();
      widget.onDeviceConnected(null);
      setState(() {
        _connectionStartTime = null;
      });
      _connectionTimer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disconnected from ${widget.connectedDevice?.name}')),
      );
    } catch (e) {
      print('Failed to disconnect: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to disconnect: ${e.toString()}')),
      );
    }
  }

  void _startConnectionTimer() {
    _connectionTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_mounted) {
        setState(() {});
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
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
      body: Column(
        children: [
          if (widget.connectedDevice != null)
            Card(
              margin: EdgeInsets.all(8),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connected Device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Name: ${widget.connectedDevice!.name}'),
                    Text('ID: ${widget.connectedDevice!.id}'),
                    if (_connectionStartTime != null)
                      Text('Connection Duration: ${_formatDuration(DateTime.now().difference(_connectionStartTime!))}'),
                    ElevatedButton(
                      onPressed: disconnectDevice,
                      child: Text('Disconnect'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: scanResults.where((result) => result.device.name.startsWith('WT')).length,
              itemBuilder: (context, index) {
                final filteredResults = scanResults.where((result) => result.device.name.startsWith('WT')).toList();
                final result = filteredResults[index];
                return ListTile(
                  title: Text(result.device.name),
                  subtitle: Text(result.device.id.id),
                  onTap: () => connectToDevice(result),
                );
              },
            ),
          ),
        ],
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
  StreamSubscription<List<int>>? dataSubscription;

  Map<String, double> sensorData = {
    'AccX': 0,
    'AccY': 0,
    'AccZ': 0,
  };

  String currentDirection = 'Initializing...';
  String potentialNewDirection = '';
  Stopwatch potentialDirectionStopwatch = Stopwatch();
  Stopwatch currentDirectionStopwatch = Stopwatch();

  String logMessage = '';
  bool showAlert = false;
  bool isInitialized = false;

  @override
  void initState() {
    super.initState();
    startWorkingWithDevice(widget.device);
    Timer.periodic(Duration(seconds: 1), (timer) {
      checkPostureDuration();
    });
  }

  void checkPostureDuration() {
    if (currentDirectionStopwatch.elapsed >= Duration(seconds: 10)) {
      showNotification();
      setState(() {
        showAlert = true;
      });
    } else {
      setState(() {
        showAlert = false;
      });
    }
  }

  Future<void> showNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'posture_channel_id',
      'Posture Notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
    DarwinNotificationDetails();

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      '자세 변경 알림',
      '자세를 바꿀 시간입니다!',
      platformChannelSpecifics,
      payload: 'posture_notification',
    );
  }


  void startWorkingWithDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      discoverServices();
    } catch (e) {
      print('Failed to connect: $e');
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('Failed to connect: ${e.toString()}')),
      );
    }
  }

  void discoverServices() async {
    List<BluetoothService> services = await widget.device.discoverServices();
    for (var service in services) {
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

        String newDirection = classifyDirection();

        if (newDirection != 'neutral') {
          if (!isInitialized) {
            // Set initial direction
            currentDirection = newDirection;
            isInitialized = true;
            currentDirectionStopwatch.start();
            logMessage = 'Initial direction: $currentDirection';
          } else {
            updateDirection(newDirection);
          }
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
    double accY = sensorData['AccY']!;
    double accZ = sensorData['AccZ']!;

    // 테스트용 알고리즘
    // if (accZ >= 0.974) return 'front';
    // if (accZ <= -0.8) return 'back';
    // if (accX <= -0.9) return 'left';
    // if (accX >= 0.9) return 'right';
    // return 'neutral';

    if ((accZ > accY) && (accZ > accX)) {
      if ((accZ - accY) > 0.5) {
        return 'front';
      } else {
        return 'left';
      }
    }
    else if (accZ <= -0.3) {
      return 'back';
    }
    else if ((accX > accY) && (accX > accZ)) {
      return 'right';
    }
    return 'neutral';
  }

  void updateDirection(String newDirection) {
    if (newDirection != currentDirection) {
      if (newDirection != potentialNewDirection) {
        // Reset the stopwatch if a new potential direction is detected
        potentialNewDirection = newDirection;
        potentialDirectionStopwatch.reset();
        potentialDirectionStopwatch.start();
      } else if (potentialDirectionStopwatch.elapsed >= Duration(seconds: 5)) {
        // If the potential direction has been maintained for 5 seconds, update the direction
        final logManager = Provider.of<PostureLogManager>(context as BuildContext, listen: false);
        logManager.addLog(PostureLogEntry(
          timestamp: DateTime.now(),
          fromDirection: currentDirection,
          toDirection: newDirection,
          duration: currentDirectionStopwatch.elapsed,
        ));

        setState(() {
          logMessage = 'Direction changed from $currentDirection to $newDirection';
          currentDirection = newDirection;
          currentDirectionStopwatch.reset();
          currentDirectionStopwatch.start();
          potentialDirectionStopwatch.reset();
          showAlert = false;
        });
      }
    } else {
      // Reset potential direction if current direction is detected again
      potentialNewDirection = '';
      potentialDirectionStopwatch.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Posture Detection'),
        elevation: 0,
      ),
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDirectionInfo(),
                SizedBox(height: 20),
                _buildLogSection(),
                if (showAlert) _buildAlert(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectionInfo() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Direction Info',
              style: Theme.of(context as BuildContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _buildInfoRow('Current Direction', currentDirection),
            _buildInfoRow('Potential New Direction', potentialNewDirection),
            StreamBuilder(
              stream: Stream.periodic(Duration(seconds: 1)),
              builder: (context, snapshot) {
                return Column(
                  children: [
                    _buildInfoRow('Current Duration', formatDuration(currentDirectionStopwatch.elapsed)),
                    _buildInfoRow('Potential Duration', formatDuration(potentialDirectionStopwatch.elapsed)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildLogSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Log',
              style: Theme.of(context as BuildContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              logMessage,
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlert() {
    return Card(
      color: Colors.yellow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '자세를 바꿀 시간입니다!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    dataSubscription?.cancel();
    widget.device.disconnect();
    currentDirectionStopwatch.stop();
    super.dispose();
  }
}

class LogPage extends StatefulWidget {
  @override
  _LogPageState createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startTime = DateTime(_startTime.year, _startTime.month, _startTime.day,
        _startTime.hour, (_startTime.minute ~/ 5) * 5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('log'),
      ),
      body: SingleChildScrollView(  // 스크롤 가능하게 만듦
        child: Column(
          children: [
            Text('시작 시간: ${DateFormat('yyyy-MM-dd HH:mm').format(_startTime)}',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

            Consumer<PostureLogManager>(
              builder: (context, logManager, child) {
                print('로그 개수: ${logManager.logs.length}'); // 디버깅용 출력
                return Column(
                  children: [
                    Text('낮 시간 그래프 (5분)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    _buildPieChart(logManager.logs, isDayTime: true),
                    Text('밤 시간 그래프 (5분)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    _buildPieChart(logManager.logs, isDayTime: false),
                    // 그래프와 로그 사이의 여백 추가
                    SizedBox(height: 20),
                    Container(
                      height: 400, // 로그를 위한 고정된 높이
                      child: ListView.builder(
                        itemCount: logManager.logs.length,
                        itemBuilder: (context, index) {
                          final log = logManager.logs[index];
                          return ListTile(
                            title: Text('${log.fromDirection} → ${log.toDirection}'),
                            subtitle: Text('Duration: ${formatDuration(log.duration)}'),
                            trailing: Text(DateFormat('HH:mm:ss').format(log.timestamp)),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(List<PostureLogEntry> logs, {required bool isDayTime}) {
    final DateTime startTime = isDayTime ? _startTime : _startTime.add(Duration(minutes: 5));
    final DateTime endTime = startTime.add(Duration(minutes: 5));


    final Map<String, double> postureDurations = {
      'front': 0.0,
      'back': 0.0,
      'left': 0.0,
      'right': 0.0,
    };




    List<PieChartSectionData> sections = [];
    postureDurations.forEach((direction, duration) {
      if (duration > 0) {
        sections.add(PieChartSectionData(
          color: _getPostureColor(direction),
          value: duration,
          title: '$direction\n${duration.toStringAsFixed(1)}s',
          radius: 70, // 그래프 크기 조정
          titleStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ));
      }
    });

    if (sections.isEmpty) {
      return Center(child: Text('이 시간대의 데이터가 없습니다'));
    }

    return Container(
      height: 200,
      padding: EdgeInsets.all(16),
      child: PieChart(
        PieChartData(
          sections: sections,
          centerSpaceRadius: 30, // 중심 공간 크기 조정
          sectionsSpace: 2,
          pieTouchData: PieTouchData(touchCallback: (_, __) {}),
        ),
      ),
    );
  }

  Color _getPostureColor(String direction) {
    switch (direction) {
      case 'front': return Colors.green;
      case 'back': return Colors.red;
      case 'left': return Colors.blue;
      case 'right': return Colors.orange;
      default: return Colors.grey;
    }
  }
}

String formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
  String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
  return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
}
