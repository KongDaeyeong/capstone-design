import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fl_chart/fl_chart.dart';

import 'dart:math';
import 'dart:ui' as ui;

// DB와 캘린더 기능 추가..
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path_package;
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

// aws cognito
import 'auth/services/auth_service.dart';
import 'auth/screens/login_page.dart';

//aws api 호출
import 'package:http/http.dart' as http;
import 'dart:convert';

Future<void> sendLogToAPI(PostureLogEntry log) async {
  final url = 'https://eax80xae1d.execute-api.ap-northeast-2.amazonaws.com/proc/posturelogs';
  try {
    final response = await http.post(
      Uri.parse(url),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
        'Origin': 'http://localhost', // Replace with your app's origin
      },
      body: jsonEncode(<String, dynamic>{
        'id': log.id,
        'timestamp': log.timestamp.toIso8601String(),
        'fromDirection': log.fromDirection,
        'todirection': log.toDirection,
        'duration': log.duration.inSeconds,
      }),
    );

    if (response.statusCode == 200) {
      print('Log sent successfully');
    } else {
      print('Failed to send log. Status code: ${response.statusCode}');
      print('Response body: ${response.body}');
    }
  } catch (e) {
    print('Error sending log: $e');
  }
}
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
      'id': log.id,
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
        id: maps[i]['id'].toString(),
      );
    });
  }
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

class PostureLogEntry {
  final String id;
  final DateTime timestamp;
  final String fromDirection;
  final String toDirection;
  final Duration duration;

  PostureLogEntry({
    required this.id,
    required this.timestamp,
    required this.fromDirection,
    required this.toDirection,
    required this.duration,
  });
}

class PostureLogManager extends ChangeNotifier {
  List<PostureLogEntry> _logs = [];
  List<PostureLogEntry> _tempLogs = [];
  //dyDB
  Future<void> addLog(PostureLogEntry entry) async {
    await _dbHelper.insertLog(entry);
    _logs.add(entry);
    _tempLogs.add(entry);
    notifyListeners();
  }
  // DB
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Map<String, Duration> _postureDurations = {
    'front': Duration.zero,
    'left': Duration.zero,
    'right': Duration.zero,
    'back': Duration.zero,
  };
  bool _isConnected = false;

  List<PostureLogEntry> get logs => List.unmodifiable(_logs);

  Map<String, Duration> get postureDurations => Map.unmodifiable(_postureDurations);
  bool get isConnected => _isConnected;

  void resetPostureDurations() {
    _postureDurations = {
      'front': Duration.zero,
      'left': Duration.zero,
      'right': Duration.zero,
      'back': Duration.zero,
    };
    notifyListeners();
  }

  void setConnected(bool connected) {
    _isConnected = connected;
    if (!connected) {
      resetPostureDurations();
    }
    notifyListeners();
  }

  void updatePostureDuration(String posture, Duration duration) {
    if ((_isConnected && (posture != 'neutral')) && (posture != '초기화 중...')) {
      _postureDurations[posture] = (_postureDurations[posture] ?? Duration.zero) + duration;
      notifyListeners();
    }
  }

  Future<void> loadLogsByDate(DateTime date) async {
    _logs = await _dbHelper.getLogsByDate(date);
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  // 새로운 메서드: 임시 로그를 서버로 전송
  Future<void> sendLogsToDynamoDB() async {
    for (var log in _tempLogs) {
      await sendLogToAPI(log);
    }
    _tempLogs.clear();
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.instance.database;
  // 로그인 관련
  final authService = AuthService();
  bool isLoggedIn = await authService.autoLogin();

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
        Provider.value(value: authService),
      ],
      child: MyApp(isLoggedIn: isLoggedIn),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({Key? key, required this.isLoggedIn}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Sensor App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: isLoggedIn ? MainScreen() : LoginPage(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final AuthService _authService = AuthService();
  Timer? _tokenRefreshTimer;
  int _selectedIndex = 0;
  BluetoothDevice? connectedDevice;
  String currentDirection = '초기화 중...';
  Stopwatch currentDirectionStopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _startTokenRefreshTimer();
  }

  void _refreshToken() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      await authService.refreshSession();
    } catch (e) {
      print('Failed to refresh token: $e');
      _signOut();
    }
  }

  void _startTokenRefreshTimer() {
    _tokenRefreshTimer = Timer.periodic(Duration(minutes: 50), (_) async {
      try {
        await _authService.refreshSession();
      } catch (e) {
        print('Failed to refresh token: $e');
        _signOut();
      }
    });
  }

  @override
  void dispose() {
    _tokenRefreshTimer?.cancel();
    super.dispose();
  }


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

  Future<void> _signOut() async {
    await _authService.signOut();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          BluetoothScanPage(onDeviceConnected: setConnectedDevice, connectedDevice: connectedDevice),
          if (connectedDevice != null)
            PosturePage(
              device: connectedDevice!,
              onDirectionChange: (direction) {
                setState(() {
                  currentDirection = direction;
                });
              },
              onStopwatchUpdate: (stopwatch) {
                currentDirectionStopwatch = stopwatch;
              },
            )
          else
            Center(child: Text('먼저 센서와 연결이 필요합니다.')),
          LogPage( ),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.bluetooth),
            label: '기기 검색',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.accessibility_new),
            label: '자세',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: '기록',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final AuthService _authService = Provider.of<AuthService>(context);

    return Scaffold(
      body: FutureBuilder<String?>(
        future: _authService.getCurrentUserEmail(),
        builder: (context, snapshot) {
          final String email = snapshot.data ?? 'Loading...';

          return ListView(
            children: [
              UserAccountsDrawerHeader(
                accountName: Text("환영합니다!"),
                accountEmail: Text(email),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 50, color: Colors.blue),
                ),
                decoration: BoxDecoration(
                  color: Colors.blue,
                ),
              ),
              ListTile(
                leading: Icon(Icons.exit_to_app),
                title: Text('로그아웃'),
                onTap: () => _showLogoutDialog(context, _authService),
              ),
              // 여기에 다른 설정 옵션들을 추가할 수 있습니다.
            ],
          );
        },
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthService authService) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('로그아웃'),
          content: Text('정말 로그아웃하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              child: Text('취소'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('로그아웃'),
              onPressed: () async {
                await authService.signOut();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => LoginPage()),
                      (Route<dynamic> route) => false,
                );
              },
            ),
          ],
        );
      },
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
      bool isBluetoothOn = await FlutterBluePlus.isOn;

      if (!isBluetoothOn) {
        // Show Snackbar if Bluetooth is off
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('블루투스를 켜고 다시 시도해주세요.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.0),
            ),
          ),
        );
        return; // Exit the method if Bluetooth is off
      }
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
        SnackBar(content: Text('연결에 성공했습니다. : ${result.device.name}')),
      );
    } catch (e) {
      print('Failed to connect: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('연결에 실패했습니다. : ${e.toString()}')),
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
        SnackBar(content: Text('기기 연결 해제 ${widget.connectedDevice?.name}')),
      );
    } catch (e) {
      print('Failed to disconnect: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('기기 연결에 실패했습니다. : ${e.toString()}')),
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
  Widget _buildScanningIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('블루투스 기기 검색 중...', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('기기 검색', style: TextStyle(fontWeight: FontWeight.bold)),
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
            _buildConnectedDeviceCard(),
          Expanded(
            child: _isScanning
                ? _buildScanningIndicator()
                : _buildScanResultsList(),
          ),
        ],
      ),
    );
  }


  Widget _buildConnectedDeviceCard() {
    return Card(
      margin: EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('연결된 기기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('기기 이름: ${widget.connectedDevice!.name}'),
            Text('기기 아이디: ${widget.connectedDevice!.id}'),
            if (_connectionStartTime != null)
              Text('연결 유지 시간: ${_formatDuration(DateTime.now().difference(_connectionStartTime!))}'),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: disconnectDevice,
              child: Text('연결 해제'),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanResultsList() {
    final filteredResults = scanResults.where((result) => result.device.name.startsWith('WT')).toList();

    if (filteredResults.isEmpty) {
      return Center(
        child: Text('검색된 기기가 없습니다.', style: TextStyle(fontSize: 16)),
      );
    }

    return ListView.builder(
      itemCount: filteredResults.length,
      itemBuilder: (context, index) {
        final result = filteredResults[index];
        return Card(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            title: Text(result.device.name, style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(result.device.id.id),
            trailing: ElevatedButton(
              child: Text('연결'),
              onPressed: () => connectToDevice(result),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PosturePage extends StatefulWidget {
  final BluetoothDevice device;
  final Function(String) onDirectionChange;
  final Function(Stopwatch) onStopwatchUpdate;

  const PosturePage({
    Key? key,
    required this.device,
    required this.onDirectionChange,
    required this.onStopwatchUpdate,
  }) : super(key: key);
  @override
  _PosturePageState createState() => _PosturePageState();
}

class _PosturePageState extends State<PosturePage> with SingleTickerProviderStateMixin {
  StreamSubscription<List<int>>? dataSubscription;
  bool isConnected = false;
  DateTime lastDataReceived = DateTime.now();

  //임시 DB
  List<PostureLogEntry> _tempLogs = [];

  late AnimationController _animationController;
  late Animation<double> _animation;

  Map<String, double> sensorData = {
    'AccX': 0,
    'AccY': 0,
    'AccZ': 0,
  };

  String currentDirection = '초기화 중...';
  String potentialNewDirection = '';
  Stopwatch potentialDirectionStopwatch = Stopwatch();
  Stopwatch currentDirectionStopwatch = Stopwatch();

  String logMessage = '';
  bool showAlert = false;
  bool isInitialized = false;
  bool showChart = false;


  //자세 가이드
  List<String> postureSequence = ['front', 'right', 'back', 'left'];
  int currentPostureIndex = 0;
  bool showWarning = false;

  String get nextRecommendedPosture {
    return postureSequence[(currentPostureIndex + 1) % postureSequence.length];
  }

  @override
  void initState() {
    super.initState();
    monitorConnection();
    startWorkingWithDevice(widget.device);
    Timer.periodic(Duration(seconds: 1), (timer) {
      checkPostureDuration();
      checkDataReception();
      updatePostureDuration();
    });
  }

  void checkPostureDuration() {
    bool _notificationSent = false;
    DateTime _lastNotificationTime = DateTime.now();
    if (currentDirectionStopwatch.elapsed >= Duration(seconds: 7200)) {
      showNotification();
      setState(() {
        showAlert = true;
        _notificationSent = true;
        _lastNotificationTime = DateTime.now();
      });
    } else {
      setState(() {
        showAlert = false;
        _notificationSent = false;
      });
    }
  }

  void monitorConnection() {
    widget.device.connectionState.listen((BluetoothConnectionState state) {
      final logManager = Provider.of<PostureLogManager>(context, listen: false);
      if (state == BluetoothConnectionState.disconnected) {
        setState(() {
          isConnected = false;
          currentDirection = '연결 끊김';
          currentDirectionStopwatch.stop();
        });
        logManager.setConnected(false);
        widget.onDirectionChange(currentDirection);
        widget.onStopwatchUpdate(currentDirectionStopwatch);
      } else if (state == BluetoothConnectionState.connected) {
        setState(() {
          isConnected = true;
        });
        logManager.setConnected(true);
      }
    });
  }

  void updatePostureDuration() {
    if ((isConnected && (currentDirection != '초기화 중...')) && (currentDirection != '연결 끊김')) {
      final logManager = Provider.of<PostureLogManager>(context, listen: false);
      logManager.updatePostureDuration(currentDirection, Duration(seconds: 1));
    }
  }

  void checkDataReception() {
    if (DateTime.now().difference(lastDataReceived).inSeconds > 3) {
      setState(() {
        isConnected = false;
        currentDirection = '연결 끊김';
        currentDirectionStopwatch.stop();
      });
      widget.onDirectionChange(currentDirection);
      widget.onStopwatchUpdate(currentDirectionStopwatch);
    }
  }

  void stopRecording() {
    currentDirectionStopwatch.stop();
    setState(() {
      currentDirection = '연결 끊김';
    });
    // 필요한 경우 로그 저장 등의 작업 수행
  }

  Future<void> showNotification() async {
    AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'posture_channel_id',
      'Posture Notifications',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 200, 500]),
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
    DarwinNotificationDetails(
      presentSound: true,
    );

    NotificationDetails platformChannelSpecifics = NotificationDetails(
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

    HapticFeedback.vibrate();
  }


  void startWorkingWithDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      discoverServices();
    } catch (e) {
      print('Failed to connect: $e');
      ScaffoldMessenger.of(context as BuildContext).showSnackBar(
        SnackBar(content: Text('기기 연결에 실패했습니다. : ${e.toString()}')),
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
    lastDataReceived = DateTime.now();
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
            logMessage = '초기 자세: $currentDirection';
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


    if ((accZ.abs() > accX.abs()) && (accZ.abs() > accY.abs())) {
      if (accZ >= 0) {
        return 'front';
      }
      else if(accZ < 0){
        return 'back';
      }
    }
    else if((accX.abs() > accZ.abs()) && (accX.abs() > accY.abs())){
      if (accX >= 0) {
        return 'right';
      }
      else if(accX < 0){
        return 'left';
      }
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
      } else if (potentialDirectionStopwatch.elapsed >= Duration(seconds: 5) || !isInitialized) {
        // If the potential direction has been maintained for 5 seconds, update the direction
        final logManager = Provider.of<PostureLogManager>(context, listen: false);
        final entry = PostureLogEntry(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            timestamp: DateTime.now(),
            fromDirection: currentDirection,
            toDirection: newDirection,
            duration: currentDirectionStopwatch.elapsed
        );
        logManager.addLog(entry);

        if (newDirection != nextRecommendedPosture) {
          showWarningDialog(newDirection);
        } else {
          updatePostureIndex(newDirection);
        }

        setState(() {
          logMessage = 'Direction changed from $currentDirection to $newDirection';
          currentDirection = newDirection;
          currentDirectionStopwatch.reset();
          currentDirectionStopwatch.start();
          potentialDirectionStopwatch.reset();
          showAlert = false;
        });
        widget.onDirectionChange(currentDirection);
        widget.onStopwatchUpdate(currentDirectionStopwatch);
      }
    } else {
      // Reset potential direction if current direction is detected again
      potentialNewDirection = '';
      potentialDirectionStopwatch.reset();
    }
  }

  // 데이터 전송 함수
  Future<void> sendLogsToServer() async {
    final logManager = Provider.of<PostureLogManager>(context, listen: false);

    for (var log in _tempLogs) {
      await logManager.addLog(log);
    }

    // 여기에 API를 통한 서버 전송 로직 추가
    // 예: await apiService.sendLogs(_tempLogs);

    setState(() {
      _tempLogs.clear(); // 전송 후 임시 로그 클리어
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('로그가 성공적으로 전송되었습니다.')),
    );
  }

  void updatePostureIndex(String newDirection) {
    currentPostureIndex = postureSequence.indexOf(newDirection);
  }

  void showWarningDialog(String newDirection) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('잘못된 자세 변경'),
          content: Text('권장 자세($nextRecommendedPosture)가 아닌 $newDirection(으)로 변경했습니다. 계속 진행하시겠습니까?'),
          actions: <Widget>[
            TextButton(
              child: Text('아니요'),
              onPressed: () {
                Navigator.of(context).pop();
                showCorrectPostureAlert();
              },
            ),
            TextButton(
              child: Text('예'),
              onPressed: () {
                Navigator.of(context).pop();
                updatePostureIndex(newDirection);
              },
            ),
          ],
        );
      },
    );
  }

  void showCorrectPostureAlert() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('올바른 자세($nextRecommendedPosture)로 변경해주세요.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('자세 판별'),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.send),
            onPressed: () async {
              final logManager = Provider.of<PostureLogManager>(context, listen: false);
              await logManager.sendLogsToDynamoDB();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('로그가 성공적으로 전송되었습니다.')),
              );
            },
          ),
          IconButton(
            icon: Icon(showChart ? Icons.info : Icons.bar_chart),
            onPressed: () {
              setState(() {
                showChart = !showChart;
              });
            },
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!showChart) ...[
                    _buildDirectionInfo(),
                    SizedBox(height: 20),
                    _buildNextPostureGuide(),
                    SizedBox(height: 20),
                    _buildLogSection(),
                    if (showAlert) _buildAlert(),
                  ],
                  if (showChart) _buildBarChart(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNextPostureGuide() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '다음 권장 자세',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              nextRecommendedPosture,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ],
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
              '자세 정보',
              style: Theme.of(context as BuildContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            _buildInfoRow('현재 자세', currentDirection),
            _buildInfoRow('변경 예정 자세', potentialNewDirection),
            StreamBuilder(
              stream: Stream.periodic(Duration(seconds: 1)),
              builder: (context, snapshot) {
                return Column(
                  children: [
                    _buildInfoRow('자세 유지 시간', formatDuration(currentDirectionStopwatch.elapsed)),
                    _buildInfoRow('자세 변경 시간', formatDuration(potentialDirectionStopwatch.elapsed)),
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
              '최근 자세 변동 이력',
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

  Widget _buildBarChart() {
    final logManager = Provider.of<PostureLogManager>(context);
    final postureDurations = logManager.postureDurations;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7, // 화면 높이의 70%로 설정
      padding: EdgeInsets.all(16),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: postureDurations.values.fold(0, (max, duration) => duration.inSeconds > max ? duration.inSeconds : max).toDouble(),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                String postureName = '';
                switch (group.x.toInt()) {
                  case 0:
                    postureName = '앞';
                    break;
                  case 1:
                    postureName = '왼쪽';
                    break;
                  case 2:
                    postureName = '오른쪽';
                    break;
                  case 3:
                    postureName = '뒤';
                    break;
                }
                return BarTooltipItem(
                  '$postureName\n${_formatDuration(Duration(seconds: rod.toY.toInt()))}',
                  const TextStyle(color: Colors.yellow),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  switch (value.toInt()) {
                    case 0:
                      return Text('앞');
                    case 1:
                      return Text('왼쪽');
                    case 2:
                      return Text('오른쪽');
                    case 3:
                      return Text('뒤');
                    default:
                      return Text('');
                  }
                },
                reservedSize: 30,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(_formatDuration(Duration(seconds: value.toInt())));
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            BarChartGroupData(
              x: 0,
              barRods: [BarChartRodData(toY: postureDurations['front']!.inSeconds.toDouble(), color: Colors.red)],
            ),
            BarChartGroupData(
              x: 1,
              barRods: [BarChartRodData(toY: postureDurations['left']!.inSeconds.toDouble(), color: Colors.green)],
            ),
            BarChartGroupData(
              x: 2,
              barRods: [BarChartRodData(toY: postureDurations['right']!.inSeconds.toDouble(), color: Colors.blue)],
            ),
            BarChartGroupData(
              x: 3,
              barRods: [BarChartRodData(toY: postureDurations['back']!.inSeconds.toDouble(), color: Colors.yellow)],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0
        ? '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds'
        : '$twoDigitMinutes:$twoDigitSeconds';
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
  bool _showCalendar = false;
  DateTime _selectedDate = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // Store data for morning (00:00 - 11:59) and afternoon (12:00 - 23:59)
  Map<String, List<PostureTimeSlot>> morningData = {};
  Map<String, List<PostureTimeSlot>> afternoonData = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      Provider.of<PostureLogManager>(context, listen: false).loadLogsByDate(_selectedDate);
      _processLogs();
    });
  }

  void _processLogs() {
    final logs = Provider.of<PostureLogManager>(context, listen: false).logs;
    morningData.clear();
    afternoonData.clear();

    for (var log in logs) {
      final startTime = log.timestamp.subtract(log.duration);  // 시작 시간 계산
      final endTime = log.timestamp;  // 종료 시간 (기존의 timestamp)
      final isAfternoon = startTime.hour >= 12;
      final targetData = isAfternoon ? afternoonData : morningData;

      if (!targetData.containsKey(log.fromDirection)) {
        targetData[log.fromDirection] = [];
      }

      targetData[log.fromDirection]!.add(PostureTimeSlot(
        start: startTime,
        end: endTime,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PostureLogManager>(context, listen: false).loadLogsByDate(_selectedDate);
      _processLogs();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('자세 변경 이력'),
        actions: [
          IconButton(
            icon: Icon(_showCalendar ? Icons.list : Icons.calendar_today),
            onPressed: () {
              setState(() {
                _showCalendar = !_showCalendar;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showCalendar) _buildCalendar(),
          Text(
            '선택된 날짜: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Consumer<PostureLogManager>(
                builder: (context, logManager, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('오전 그래프 (00:00 - 11:59)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      buildClockChart(morningData, isMorning: true),
                      Text('오후 그래프 (12:00 - 23:59)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      buildClockChart(afternoonData, isMorning: false),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        itemCount: logManager.logs.length,
                        itemBuilder: (context, index) {
                          final log = logManager.logs[index];
                          return ListTile(
                            title: Text('${log.fromDirection} → ${log.toDirection}'),
                            subtitle: Text('유지 시간: ${formatDuration(log.duration)}'),
                            trailing: Text(DateFormat('HH:mm:ss').format(log.timestamp)),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildClockChart(Map<String, List<PostureTimeSlot>> data, {required bool isMorning}) {
    List<PieChartSectionData> sections = [];
    final startHour = isMorning ? 0 : 12;
    final endHour = isMorning ? 12 : 24;


    for (int hour = startHour; hour < endHour; hour++) {
      for (int minute = 0; minute < 60; minute++) {
        final time = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour, minute);
        String? posture = _getPostureAtTime(data, time);

        sections.add(PieChartSectionData(
          color: _getPostureColor(posture),
          value: 1,
          title: '',
          radius: 130,
          showTitle: false,
        ));
      }
    }

    return Container(
      height: 400,
      width: 400,
      padding: EdgeInsets.all(16),
      child: Stack(
        children: [
          PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 0,
              sectionsSpace: 0,
              startDegreeOffset: -90,
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: ClockFacePainter(isMorning: isMorning),
            ),
          ),
        ],
      ),
    );
  }

  String? _getPostureAtTime(Map<String, List<PostureTimeSlot>> data, DateTime time) {
    for (var entry in data.entries) {
      for (var slot in entry.value) {
        if (time.isAfter(slot.start) && time.isBefore(slot.end)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  Widget _buildCalendar() {
    return TableCalendar(
      firstDay: DateTime.utc(2023, 1, 1),
      lastDay: DateTime.utc(2030, 12, 31),
      focusedDay: _selectedDate,
      calendarFormat: _calendarFormat,
      selectedDayPredicate: (day) {
        return isSameDay(_selectedDate, day);
      },
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDate = selectedDay;
          Provider.of<PostureLogManager>(context, listen: false).loadLogsByDate(_selectedDate);
          _processLogs();
        });
      },
      onFormatChanged: (format) {
        setState(() {
          _calendarFormat = format;
        });
      },
    );
  }

  Color _getPostureColor(String? direction) {
    switch (direction) {
      case 'front':
        return Colors.green;
      case 'back':
        return Colors.red;
      case 'left':
        return Colors.blue;
      case 'right':
        return Colors.orange;
      default:
        return Colors.white; // For unmeasured time
    }
  }
}

String formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
  String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
  return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
}

class PostureTimeSlot {
  final DateTime start;
  final DateTime end;

  PostureTimeSlot({required this.start, required this.end});
  Duration get duration => end.difference(start);
}

class ClockFacePainter extends CustomPainter {
  final bool isMorning;

  ClockFacePainter({required this.isMorning});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Draw circle
    canvas.drawCircle(center, radius, paint);

    // Draw hour marks
    for (int i = 0; i < 12; i++) {
      final angle = (i * 30 - 90) * (pi / 180);
      final hourMarkStart = Offset(
        center.dx + cos(angle) * (radius - 10),
        center.dy + sin(angle) * (radius - 10),
      );
      final hourMarkEnd = Offset(
        center.dx + cos(angle) * radius,
        center.dy + sin(angle) * radius,
      );
      canvas.drawLine(hourMarkStart, hourMarkEnd, paint);

      // Draw hour numbers
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${isMorning ? i : i + 12}',
          style: TextStyle(color: Colors.black, fontSize: 16),
        ),
        textDirection: ui.TextDirection.ltr,
      );
      textPainter.layout();
      final textCenter = Offset(
        center.dx + cos(angle) * (radius - 30) - textPainter.width / 2,
        center.dy + sin(angle) * (radius - 30) - textPainter.height / 2,
      );
      textPainter.paint(canvas, textCenter);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}