import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/auth_text_field.dart';
import 'confirm_signup_page.dart';

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

  Future _signUp() async {
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
                  AuthTextField(
                    controller: _emailController,
                    hintText: 'Email',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  SizedBox(height: 16),
                  Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      AuthTextField(
                        controller: _passwordController,
                        hintText: 'Password',
                        prefixIcon: Icons.lock_outline,
                        obscureText: _obscurePassword,
                      ),
                      IconButton(
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
                    ],
                  ),
                  SizedBox(height: 16),
                  Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      AuthTextField(
                        controller: _confirmPasswordController,
                        hintText: 'Confirm Password',
                        prefixIcon: Icons.lock_outline,
                        obscureText: _obscureConfirmPassword,
                      ),
                      IconButton(
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
                    ],
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

// import 'package:flutter/material.dart';
// import '../constants/styles.dart';
// import '../widgets/auth_text_field.dart';
// import 'base_auth_page.dart';
// import '../services/auth_service.dart';
//
// class SignUpPage extends BaseAuthPage {
//   SignUpPage({Key? key}) : super(key: key, title: 'Create Account');
//
//   @override
//   IconData getHeaderIcon() => Icons.account_circle_outlined;
//
//   @override
//   List<Widget> buildForm(BuildContext context) {
//     final TextEditingController _emailController = TextEditingController();
//     final TextEditingController _passwordController = TextEditingController();
//     final TextEditingController _confirmPasswordController = TextEditingController();
//     final AuthService _authService = AuthService();
//
//     return [
//       AuthTextField(
//         controller: _emailController,
//         hintText: 'Email',
//         prefixIcon: Icons.email_outlined,
//         keyboardType: TextInputType.emailAddress,
//       ),
//       SizedBox(height: 16),
//       AuthTextField(
//         controller: _passwordController,
//         hintText: 'Password',
//         prefixIcon: Icons.lock_outline,
//         obscureText: true,
//       ),
//       SizedBox(height: 16),
//       AuthTextField(
//         controller: _confirmPasswordController,
//         hintText: 'Confirm Password',
//         prefixIcon: Icons.lock_outline,
//         obscureText: true,
//       ),
//       SizedBox(height: 24),
//       ElevatedButton(
//         onPressed: () async {
//           if (_passwordController.text != _confirmPasswordController.text) {
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(content: Text('Passwords do not match')),
//             );
//             return;
//           }
//           final success = await _authService.signUp(
//             _emailController.text,
//             _passwordController.text,
//           );
//           if (success) {
//             Navigator.of(context).pushNamed('/confirm-signup', arguments: _emailController.text);
//           } else {
//             ScaffoldMessenger.of(context).showSnackBar(
//               SnackBar(content: Text('Sign up failed. Please try again.')),
//             );
//           }
//         },
//         child: Text('Sign Up'),
//         style: AuthStyles.primaryButtonStyle,
//       ),
//       SizedBox(height: 16),
//       TextButton(
//         onPressed: () {
//           Navigator.of(context).pop();
//         },
//         child: Text(
//           'Already have an account? Sign In',
//           style: TextStyle(color: Colors.white),
//         ),
//       ),
//     ];
//   }
// }