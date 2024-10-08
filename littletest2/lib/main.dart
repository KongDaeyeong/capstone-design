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

// aws cognito
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Cognito 사용자 풀 설정
final userPool = CognitoUserPool(
  'ap-northeast-2_YJNyRcILc',
  '7d3rk8vs4u0720p0ivj6ejb4h1',
);

class AuthService {
  final FlutterSecureStorage _storage = FlutterSecureStorage();

  Future<bool> signUp(String email, String password) async {
    try {
      await userPool.signUp(email, password, userAttributes: [
        AttributeArg(name: 'email', value: email)
      ]);
      return true;
    } catch (e) {
      print('Sign up error: $e');
      return false;
    }
  }

  Future<bool> confirmSignUp(String email, String confirmationCode) async {
    final cognitoUser = CognitoUser(email, userPool);
    try {
      await cognitoUser.confirmRegistration(confirmationCode);
      return true;
    } catch (e) {
      print('Confirmation error: $e');
      return false;
    }
  }

  Future<bool> signIn(String email, String password) async {
    final cognitoUser = CognitoUser(email, userPool);
    final authDetails = AuthenticationDetails(
      username: email,
      password: password,
    );
    try {
      final session = await cognitoUser.authenticateUser(authDetails);
      await _saveSession(session!);
      await _storage.write(key: 'user_email', value: email);
      return true;
    } catch (e) {
      print('Sign in error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    final cognitoUser = await getCurrentUser();
    await cognitoUser?.signOut();
    await _storage.deleteAll();
  }

  Future<void> _saveSession(CognitoUserSession session) async {
    await _storage.write(key: 'id_token', value: session.idToken.jwtToken);
    await _storage.write(key: 'access_token', value: session.accessToken.jwtToken);
    await _storage.write(key: 'refresh_token', value: session.refreshToken?.token);
  }

  Future<bool> isLoggedIn() async {
    final idToken = await _storage.read(key: 'id_token');
    return idToken != null;
  }

  Future<bool> autoLogin() async {
    final idToken = await _storage.read(key: 'id_token');
    final refreshToken = await _storage.read(key: 'refresh_token');
    final userEmail = await _storage.read(key: 'user_email');

    if (idToken == null || refreshToken == null || userEmail == null) {
      return false;
    }

    final cognitoUser = CognitoUser(userEmail, userPool);
    final session = CognitoUserSession(
      CognitoIdToken(idToken),
      CognitoAccessToken(await _storage.read(key: 'access_token') ?? ''),
      refreshToken: CognitoRefreshToken(refreshToken),
    );

    try {
      final newSession = await cognitoUser.refreshSession(session.refreshToken!);
      await _saveSession(newSession!);
      return true;
    } catch (e) {
      print('Auto login failed: $e');
      return false;
    }
  }

  Future<CognitoUser?> getCurrentUser() async {
    final email = await _storage.read(key: 'user_email');
    return email != null ? CognitoUser(email, userPool) : null;
  }

  Future<void> refreshSession() async {
    final refreshToken = await _storage.read(key: 'refresh_token');
    final userEmail = await _storage.read(key: 'user_email');

    if (refreshToken == null || userEmail == null) {
      throw Exception('Refresh token or user email not found');
    }

    final cognitoUser = CognitoUser(userEmail, userPool);
    final session = await cognitoUser.refreshSession(CognitoRefreshToken(refreshToken));
    await _saveSession(session!);
  }

  Future<String?> getCurrentUserEmail() async {
    return await _storage.read(key: 'user_email');
  }
}

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  Future<void> _signIn() async {
    final email = _emailController.text;
    final password = _passwordController.text;
    final success = await _authService.signIn(email, password);
    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade300, Colors.purple.shade300],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: Colors.white,
                  ),
                  SizedBox(height: 48),
                  Text(
                    'Welcome Back',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 48),
                  _buildTextField(
                    controller: _emailController,
                    hintText: 'Email',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  SizedBox(height: 16),
                  _buildTextField(
                    controller: _passwordController,
                    hintText: 'Password',
                    prefixIcon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _signIn,
                    child: Text('Sign In'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.blue.shade700, backgroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      textStyle: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => SignUpPage()),
                      );
                    },
                    child: Text(
                      'Don\'t have an account? Sign Up',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(30),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.white70),
          prefixIcon: Icon(prefixIcon, color: Colors.white70),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        ),
        style: TextStyle(color: Colors.white),
        keyboardType: keyboardType,
        obscureText: obscureText,
      ),
    );
  }
}

class SignUpPage extends StatefulWidget {
  @override
  _SignUpPageState createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool _hasUpperCase = false;
  bool _hasLowerCase = false;
  bool _hasDigit = false;
  bool _hasSpecialChar = false;
  bool _hasMinLength = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_checkPasswordStrength);
  }

  void _checkPasswordStrength() {
    final password = _passwordController.text;
    setState(() {
      _hasUpperCase = password.contains(RegExp(r'[A-Z]'));
      _hasLowerCase = password.contains(RegExp(r'[a-z]'));
      _hasDigit = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
      _hasMinLength = password.length >= 8;
    });
  }

  Future<void> _signUp() async {
    final email = _emailController.text;
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    if (!_hasUpperCase || !_hasLowerCase || !_hasDigit || !_hasSpecialChar || !_hasMinLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password does not meet all requirements')),
      );
      return;
    }

    final success = await _authService.signUp(email, password);

    if (success) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ConfirmSignUpPage(email: email)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign up failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade300, Colors.purple.shade300],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.account_circle_outlined,
                    size: 80,
                    color: Colors.white,
                  ),
                  SizedBox(height: 48),
                  Text(
                    'Create Account',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 48),
                  _buildTextField(
                    controller: _emailController,
                    hintText: 'Email',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  SizedBox(height: 16),
                  _buildTextField(
                    controller: _passwordController,
                    hintText: 'Password',
                    prefixIcon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  SizedBox(height: 16),
                  _buildTextField(
                    controller: _confirmPasswordController,
                    hintText: 'Confirm Password',
                    prefixIcon: Icons.lock_outline,
                    obscureText: _obscureConfirmPassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  SizedBox(height: 24),
                  _buildPasswordRequirements(),
                  SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _signUp,
                    child: Text('Sign Up'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      textStyle: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Already have an account? Sign In',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(30),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.white70),
          prefixIcon: Icon(prefixIcon, color: Colors.white70),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        ),
        style: TextStyle(color: Colors.white),
        keyboardType: keyboardType,
        obscureText: obscureText,
      ),
    );
  }

  Widget _buildPasswordRequirements() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Password must:',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        _buildRequirement('Contain at least one uppercase letter', _hasUpperCase),
        _buildRequirement('Contain at least one lowercase letter', _hasLowerCase),
        _buildRequirement('Contain at least one digit', _hasDigit),
        _buildRequirement('Contain at least one special character', _hasSpecialChar),
        _buildRequirement('Be at least 8 characters long', _hasMinLength),
      ],
    );
  }

  Widget _buildRequirement(String text, bool isMet) {
    return Row(
      children: [
        Icon(
          isMet ? Icons.check_circle : Icons.cancel,
          color: isMet ? Colors.green : Colors.red,
          size: 16,
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _passwordController.removeListener(_checkPasswordStrength);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}

class ConfirmSignUpPage extends StatefulWidget {
  final String email;

  ConfirmSignUpPage({required this.email});

  @override
  _ConfirmSignUpPageState createState() => _ConfirmSignUpPageState();
}

class _ConfirmSignUpPageState extends State<ConfirmSignUpPage> {
  final AuthService _authService = AuthService();
  final TextEditingController _confirmationCodeController = TextEditingController();
  bool _isLoading = false;

  Future<void> _confirmSignUp() async {
    setState(() {
      _isLoading = true;
    });

    final confirmationCode = _confirmationCodeController.text;

    final success = await _authService.confirmSignUp(widget.email, confirmationCode);

    setState(() {
      _isLoading = false;
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign up confirmed. Please log in.')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginPage()),
            (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Confirmation failed. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue.shade300, Colors.purple.shade300],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 80,
                    color: Colors.white,
                  ),
                  SizedBox(height: 48),
                  Text(
                    'Confirm Sign Up',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Please enter the confirmation code sent to ${widget.email}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 48),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: TextField(
                      controller: _confirmationCodeController,
                      decoration: InputDecoration(
                        hintText: 'Confirmation Code',
                        hintStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.confirmation_number_outlined, color: Colors.white70),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      ),
                      style: TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _confirmSignUp,
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.blue.shade700)
                        : Text('Confirm Sign Up'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                      textStyle: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Back to Sign In',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
// aws 관련 코드 끝



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
            PosturePage(device: connectedDevice!)
          else
            Center(child: Text('먼저 센서와 연결이 필요합니다.')),
          LogPage(),
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('기기 검색'),
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
                    Text('연결된 기기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('기기 이름: ${widget.connectedDevice!.name}'),
                    Text('기기 아이디: ${widget.connectedDevice!.id}'),
                    if (_connectionStartTime != null)
                      Text('연결 유지 시간: ${_formatDuration(DateTime.now().difference(_connectionStartTime!))}'),
                    ElevatedButton(
                      onPressed: disconnectDevice,
                      child: Text('연결 해제'),
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

  String currentDirection = '초기화 중...';
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
        title: Text('자세 판별'),
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

  @override
  Widget build(BuildContext context) {
    // 여기서 로그를 로드합니다
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PostureLogManager>(context, listen: false).loadLogsByDate(_selectedDate);
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
          Expanded(
            child: Consumer<PostureLogManager>(
              builder: (context, logManager, child) {
                return ListView.builder(
                  itemCount: logManager.logs.length,
                  itemBuilder: (context, index) {
                    final log = logManager.logs[index];
                    return ListTile(
                      title: Text('${log.fromDirection} → ${log.toDirection}'),
                      subtitle: Text('유지 시간: ${formatDuration(log.duration)}'),
                      trailing: Text(DateFormat('HH:mm:ss').format(log.timestamp)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
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
          Provider.of<PostureLogManager>(context as BuildContext, listen: false).loadLogsByDate(_selectedDate);
        });
      },
      onFormatChanged: (format) {
        setState(() {
          _calendarFormat = format;
        });
      },
    );
  }
}

String formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
  String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
  return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
}