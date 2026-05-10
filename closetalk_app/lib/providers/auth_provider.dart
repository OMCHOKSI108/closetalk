import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_config.dart';

enum AuthStatus { uninitialized, authenticated, unauthenticated, loading }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.uninitialized;
  User? _user;
  String? _token;
  String? _refreshToken;
  String? _error;
  List<String>? _recoveryCodes;

  AuthStatus get status => _status;
  User? get user => _user;
  String? get token => _token;
  String? get error => _error;
  List<String>? get recoveryCodes => _recoveryCodes;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  AuthProvider() {
    _loadSavedSession();
  }

  Future<void> _loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('access_token');
    _refreshToken = prefs.getString('refresh_token');
    if (_token != null) {
      final userJson = prefs.getString('user');
      if (userJson != null) {
        _user = User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      }
      ApiConfig.token = _token;
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) prefs.setString('access_token', _token!);
    if (_refreshToken != null) prefs.setString('refresh_token', _refreshToken!);
    if (_user != null) prefs.setString('user', jsonEncode(_user!.toJson()));
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
            Uri.parse('${ApiConfig.authBaseUrl}/auth/register'));
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({
          'email': email,
          'password': password,
          'display_name': displayName,
        }));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 201) {
          final data = AuthResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
          _token = data.accessToken;
          _refreshToken = data.refreshToken;
          _user = data.user;
          _recoveryCodes = data.recoveryCodes;
          ApiConfig.token = _token;
          await _saveSession();
          _status = AuthStatus.authenticated;
        } else {
          final err = jsonDecode(body) as Map<String, dynamic>;
          _error = err['error'] as String? ?? 'Registration failed';
          _status = AuthStatus.unauthenticated;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _error = 'Network error: $e';
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
            Uri.parse('${ApiConfig.authBaseUrl}/auth/login'));
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({
          'email': email,
          'password': password,
        }));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          final data = AuthResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
          _token = data.accessToken;
          _refreshToken = data.refreshToken;
          _user = data.user;
          ApiConfig.token = _token;
          await _saveSession();
          _status = AuthStatus.authenticated;
        } else {
          final err = jsonDecode(body) as Map<String, dynamic>;
          _error = err['error'] as String? ?? 'Login failed';
          _status = AuthStatus.unauthenticated;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _error = 'Network error: $e';
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> googleLogin({required String idToken}) async {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
            Uri.parse('${ApiConfig.authBaseUrl}/auth/oauth'));
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({
          'code': idToken,
          'provider': 'google',
        }));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          final data = AuthResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
          _token = data.accessToken;
          _refreshToken = data.refreshToken;
          _user = data.user;
          ApiConfig.token = _token;
          await _saveSession();
          _status = AuthStatus.authenticated;
        } else {
          final err = jsonDecode(body) as Map<String, dynamic>;
          _error = err['error'] as String? ?? 'Google login failed';
          _status = AuthStatus.unauthenticated;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _error = 'Network error: $e';
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> githubLogin({required String code}) async {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
            Uri.parse('${ApiConfig.authBaseUrl}/auth/oauth'));
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({
          'code': code,
          'provider': 'github',
        }));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          final data = AuthResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
          _token = data.accessToken;
          _refreshToken = data.refreshToken;
          _user = data.user;
          ApiConfig.token = _token;
          await _saveSession();
          _status = AuthStatus.authenticated;
        } else {
          final err = jsonDecode(body) as Map<String, dynamic>;
          _error = err['error'] as String? ?? 'GitHub login failed';
          _status = AuthStatus.unauthenticated;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _error = 'Network error: $e';
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> refreshToken() async {
    if (_refreshToken == null) return false;
    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
            Uri.parse('${ApiConfig.authBaseUrl}/auth/refresh'));
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({'refresh_token': _refreshToken}));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          final data = jsonDecode(body) as Map<String, dynamic>;
          _token = data['access_token'] as String;
          _refreshToken = data['refresh_token'] as String;
          ApiConfig.token = _token;
          await _saveSession();
          return true;
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return false;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _token = null;
    _refreshToken = null;
    _user = null;
    _recoveryCodes = null;
    ApiConfig.token = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> recoverWithCode(String code) async {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
            Uri.parse('${ApiConfig.authBaseUrl}/auth/recover'));
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({'code': code}));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          final data = AuthResponse.fromJson(jsonDecode(body) as Map<String, dynamic>);
          _token = data.accessToken;
          _refreshToken = data.refreshToken;
          _user = data.user;
          ApiConfig.token = _token;
          await _saveSession();
          _status = AuthStatus.authenticated;
        } else {
          final err = jsonDecode(body) as Map<String, dynamic>;
          _error = err['error'] as String? ?? 'Recovery failed';
          _status = AuthStatus.unauthenticated;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _error = 'Network error: $e';
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> sendRecoveryEmail(String email) async {
    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
            Uri.parse('${ApiConfig.authBaseUrl}/auth/recover/email'));
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({'email': email}));
        await req.close();
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
