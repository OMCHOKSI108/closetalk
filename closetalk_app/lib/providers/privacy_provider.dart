import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/api_config.dart';

class PrivacySettings {
  String lastSeenVisibility;
  String profilePhotoVisibility;
  bool readReceiptsGlobal;
  String readReceiptsOverrides;
  String groupAddPermission;
  String statusPrivacy;
  String closeFriends;

  PrivacySettings({
    this.lastSeenVisibility = 'everyone',
    this.profilePhotoVisibility = 'everyone',
    this.readReceiptsGlobal = true,
    this.readReceiptsOverrides = '{}',
    this.groupAddPermission = 'everyone',
    this.statusPrivacy = 'contacts',
    this.closeFriends = '[]',
  });

  factory PrivacySettings.fromJson(Map<String, dynamic> json) {
    return PrivacySettings(
      lastSeenVisibility: json['last_seen_visibility'] as String? ?? 'everyone',
      profilePhotoVisibility: json['profile_photo_visibility'] as String? ?? 'everyone',
      readReceiptsGlobal: json['read_receipts_global'] as bool? ?? true,
      readReceiptsOverrides: json['read_receipts_overrides'] as String? ?? '{}',
      groupAddPermission: json['group_add_permission'] as String? ?? 'everyone',
      statusPrivacy: json['status_privacy'] as String? ?? 'contacts',
      closeFriends: json['close_friends'] as String? ?? '[]',
    );
  }

  Map<String, dynamic> toJson() => {
    'last_seen_visibility': lastSeenVisibility,
    'profile_photo_visibility': profilePhotoVisibility,
    'read_receipts_global': readReceiptsGlobal,
    'group_add_permission': groupAddPermission,
    'status_privacy': statusPrivacy,
  };
}

class PrivacyProvider extends ChangeNotifier {
  PrivacySettings _settings = PrivacySettings();
  bool _isLoading = false;
  String? _error;

  PrivacySettings get settings => _settings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/users/settings'),
        );
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          _settings = PrivacySettings.fromJson(
            jsonDecode(body) as Map<String, dynamic>,
          );
        } else {
          _error = 'Failed to load settings';
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _error = 'Network error: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> updateSettings(Map<String, dynamic> updates) async {
    _error = null;
    try {
      final client = HttpClient();
      try {
        final req = await client.putUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/users/settings'),
        );
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        req.write(jsonEncode(updates));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          await loadSettings();
          return true;
        }
        _error = 'Failed to update settings';
        return false;
      } finally {
        client.close();
      }
    } catch (e) {
      _error = 'Network error: $e';
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
