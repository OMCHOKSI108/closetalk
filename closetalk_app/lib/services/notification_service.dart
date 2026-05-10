import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  bool _initialized = false;
  String? _fcmToken;

  bool get isInitialized => _initialized;
  String? get fcmToken => _fcmToken;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    return true;
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    _fcmToken = prefs.getString('fcm_token');
    return _fcmToken;
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
  }) async {
    debugPrint('[notification] $title: $body');
  }
}
