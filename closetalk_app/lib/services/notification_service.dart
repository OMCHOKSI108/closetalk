import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

typedef OnNotificationTap = void Function(String? chatId, String? messageId);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[notification] background: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  bool _initialized = false;
  bool _firebaseAvailable = false;
  String? _fcmToken;
  OnNotificationTap? _onTap;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool get isInitialized => _initialized;
  String? get fcmToken => _fcmToken;

  void setOnTap(OnNotificationTap onTap) => _onTap = onTap;

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
      _firebaseAvailable = true;

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      _fcmToken = await messaging.getToken();
      debugPrint('[notification] FCM token: $_fcmToken');

      messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        debugPrint('[notification] token refreshed: $newToken');
      });

      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    } catch (e) {
      debugPrint('[notification] Firebase unavailable: $e');
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleLocalNotificationTap,
    );

    _initialized = true;
  }

  Future<bool> requestPermission() async {
    if (_firebaseAvailable) {
      try {
        final messaging = FirebaseMessaging.instance;
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      } catch (_) {}
    }

    final notif = await Permission.notification.request();
    return notif.isGranted;
  }

  Future<String?> getToken() async {
    if (_fcmToken != null) return _fcmToken;

    try {
      if (_firebaseAvailable) {
        final messaging = FirebaseMessaging.instance;
        _fcmToken = await messaging.getToken();
      }
    } catch (_) {}

    if (_fcmToken == null) {
      final prefs = await SharedPreferences.getInstance();
      _fcmToken = prefs.getString('fcm_token');
    }
    return _fcmToken;
  }

  Future<bool> _shouldSuppress(String? chatId) async {
    final prefs = await SharedPreferences.getInstance();

    final dnd = prefs.getBool('notif_dnd') ?? false;
    if (dnd) {
      final startH = prefs.getInt('quiet_start_hour') ?? 23;
      final startM = prefs.getInt('quiet_start_minute') ?? 0;
      final endH = prefs.getInt('quiet_end_hour') ?? 8;
      final endM = prefs.getInt('quiet_end_minute') ?? 0;
      final now = DateTime.now();
      final startMin = startH * 60 + startM;
      final endMin = endH * 60 + endM;
      final nowMin = now.hour * 60 + now.minute;
      if (startMin <= endMin) {
        if (nowMin >= startMin && nowMin < endMin) return true;
      } else {
        if (nowMin >= startMin || nowMin < endMin) return true;
      }
    }

    if (chatId != null) {
      final muted = prefs.getStringList('muted_chats') ?? [];
      if (muted.contains(chatId)) return true;
    }

    return false;
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (await _shouldSuppress(payload)) return;

    const androidDetails = AndroidNotificationDetails(
      'closetalk_messages',
      'Messages',
      channelDescription: 'New message notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      showLocalNotification(
        title: notification.title ?? '',
        body: notification.body ?? '',
        payload: message.data['chat_id'],
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    final chatId = message.data['chat_id'];
    final messageId = message.data['message_id'];
    _onTap?.call(chatId, messageId);
  }

  void _handleLocalNotificationTap(NotificationResponse response) {
    _onTap?.call(response.payload, null);
  }
}
