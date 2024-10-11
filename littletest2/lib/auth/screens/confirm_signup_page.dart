import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'login_page.dart';

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
