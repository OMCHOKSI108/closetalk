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

  String? _pendingEmail;

  String? get pendingEmail => _pendingEmail;

  /// Step 1: submit registration form, receive OTP via email
  Future<Map<String, dynamic>> registerInit({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) async {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
            Uri.parse('${ApiConfig.authBaseUrl}/auth/register/init'));
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({
          'email': email,
          'password': password,
          'display_name': displayName,
          'username': username,
        }));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          _pendingEmail = email;
          _status = AuthStatus.unauthenticated;
          notifyListeners();
          return jsonDecode(body) as Map<String, dynamic>;
        } else {
          final err = jsonDecode(body) as Map<String, dynamic>;
          _error = err['error'] as String? ?? 'Failed to send verification code';
          _status = AuthStatus.unauthenticated;
          notifyListeners();
          return err;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _error = 'Network error: $e';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return {'error': _error};
    }
  }

  /// Step 2: verify OTP to complete registration
  Future<Map<String, dynamic>> registerVerify({
    required String email,
    required String otp,
  }) async {
    _status = AuthStatus.loading;
    _error = null;
    notifyListeners();

    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
            Uri.parse('${ApiConfig.authBaseUrl}/auth/register/verify'));
        req.headers.set('Content-Type', 'application/json');
        req.write(jsonEncode({'email': email, 'otp': otp}));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 201) {
          final data = AuthResponse.fromJson(
              jsonDecode(body) as Map<String, dynamic>);
          _token = data.accessToken;
          _refreshToken = data.refreshToken;
          _user = data.user;
          _recoveryCodes = data.recoveryCodes;
          _pendingEmail = null;
          ApiConfig.token = _token;
          await _saveSession();
          _status = AuthStatus.authenticated;
          notifyListeners();
          return {'success': true};
        } else {
          final err = jsonDecode(body) as Map<String, dynamic>;
          _error = err['error'] as String? ?? 'Verification failed';
          _status = AuthStatus.unauthenticated;
          notifyListeners();
          return err;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _error = 'Network error: $e';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return {'error': _error};
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String username,
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
          'username': username,
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

  Future<Map<String, dynamic>> updateProfile({
    String? displayName,
    String? username,
    String? bio,
    String? avatarUrl,
  }) async {
    _error = null;
    final body = <String, dynamic>{};
    if (displayName != null) body['display_name'] = displayName;
    if (username != null) body['username'] = username;
    if (bio != null) body['bio'] = bio;
    if (avatarUrl != null) body['avatar_url'] = avatarUrl;

    Future<HttpClientResponse> doRequest() async {
      final client = HttpClient();
      final req = await client.putUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/auth/profile'));
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Authorization', 'Bearer $_token');
      req.write(jsonEncode(body));
      return req.close();
    }

    try {
      var resp = await doRequest();
      var responseBody = await resp.transform(utf8.decoder).join();

      if (resp.statusCode == 401) {
        // Access token expired — try refresh, then retry once.
        final refreshed = await refreshToken();
        if (refreshed) {
          resp = await doRequest();
          responseBody = await resp.transform(utf8.decoder).join();
        } else {
          _status = AuthStatus.unauthenticated;
          _error = 'Session expired, please sign in again';
          notifyListeners();
          return {'error': _error};
        }
      }

      if (resp.statusCode == 200) {
        final data = jsonDecode(responseBody) as Map<String, dynamic>;
        _user = User.fromJson(data['user'] as Map<String, dynamic>);
        await _saveSession();
        notifyListeners();
        return data;
      }
      final err = jsonDecode(responseBody) as Map<String, dynamic>;
      _error = err['error'] as String? ?? 'Failed to update profile';
      notifyListeners();
      return err;
    } catch (e) {
      _error = 'Network error: $e';
      notifyListeners();
      return {'error': _error};
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.isEmpty) return [];
    try {
      final client = HttpClient();
      try {
        final req = await client.getUrl(
            Uri.parse('${ApiConfig.authBaseUrl}/users/search?q=$query'));
        req.headers.set('Authorization', 'Bearer $_token');
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        if (resp.statusCode == 200) {
          final data = jsonDecode(body) as Map<String, dynamic>;
          return (data['users'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> registerNotificationToken({
    required String token,
    required String platform,
    String? deviceId,
  }) async {
    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(Uri.parse(
            '${ApiConfig.authBaseUrl}/devices/notification'));
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Authorization', 'Bearer $_token');
        req.write(jsonEncode({
          'token': token,
          'platform': platform,
          if (deviceId != null) 'device_id': deviceId,
        }));
        final resp = await req.close();
        return resp.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
