import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  final userPool = CognitoUserPool(
    'ap-northeast-2_rgdBJwnAT',
    '7u0kvvdipnrqgis90u77popgkt',
  );
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