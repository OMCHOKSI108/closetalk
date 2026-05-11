import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';

class AdminUser {
  final String id;
  final String email;
  final String displayName;
  final String username;
  final bool isActive;
  final bool isAdmin;
  final String createdAt;

  AdminUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.username,
    required this.isActive,
    required this.isAdmin,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'] as String? ?? '',
      email: json['email'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      isAdmin: json['is_admin'] as bool? ?? false,
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class FeatureFlag {
  final String id;
  final String name;
  final String description;
  bool enabled;
  int rolloutPercent;
  final String createdAt;
  final String updatedAt;

  FeatureFlag({
    required this.id,
    required this.name,
    this.description = '',
    required this.enabled,
    required this.rolloutPercent,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FeatureFlag.fromJson(Map<String, dynamic> json) {
    return FeatureFlag(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      rolloutPercent: (json['rollout_percent'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String? ?? '',
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

class AuditEntry {
  final String id;
  final String adminId;
  final String action;
  final String targetType;
  final String targetId;
  final String details;
  final String createdAt;

  AuditEntry({
    required this.id,
    required this.adminId,
    required this.action,
    required this.targetType,
    required this.targetId,
    this.details = '{}',
    required this.createdAt,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      id: json['id'] as String? ?? '',
      adminId: json['admin_id'] as String? ?? '',
      action: json['action'] as String? ?? '',
      targetType: json['target_type'] as String? ?? '',
      targetId: json['target_id'] as String? ?? '',
      details: json['details'] as String? ?? '{}',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class AdminProvider extends ChangeNotifier {
  List<AdminUser> _users = [];
  Map<String, dynamic>? _analytics;
  List<FeatureFlag> _flags = [];
  List<AuditEntry> _auditLog = [];
  bool _isLoading = false;
  String? _error;

  List<AdminUser> get users => _users;
  Map<String, dynamic>? get analytics => _analytics;
  List<FeatureFlag> get flags => _flags;
  List<AuditEntry> get auditLog => _auditLog;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadUsers({String? query}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final uri = Uri.parse('${ApiConfig.authBaseUrl}/admin/users')
          .replace(queryParameters: query != null ? {'q': query} : null);
      final response = await http.get(uri, headers: ApiConfig.headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _users = (data['users'] as List<dynamic>)
            .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _error = 'Failed to load users';
      }
    } catch (e) {
      _error = 'Network error: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> toggleUserDisabled(String userId) async {
    _error = null;
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/users/$userId/disable'),
        headers: ApiConfig.headers,
      );

      if (response.statusCode == 200) {
        await loadUsers();
        return true;
      }
      _error = 'Failed to update user';
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      return false;
    }
  }

  Future<void> loadAnalytics() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/analytics'),
        headers: ApiConfig.headers,
      );

      if (response.statusCode == 200) {
        _analytics = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadFlags() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/flags'),
        headers: ApiConfig.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _flags = (data['flags'] as List<dynamic>)
            .map((e) => FeatureFlag.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _error = 'Failed to load flags';
      }
    } catch (e) {
      _error = 'Network error: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> updateFlag(String flagId, {bool? enabled, int? rolloutPercent}) async {
    _error = null;
    try {
      final body = <String, dynamic>{};
      if (enabled != null) body['enabled'] = enabled;
      if (rolloutPercent != null) body['rollout_percent'] = rolloutPercent;

      final response = await http.put(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/flags/$flagId'),
        headers: ApiConfig.headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        await loadFlags();
        return true;
      }
      _error = 'Failed to update flag';
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      return false;
    }
  }

  Future<void> loadAuditLog() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/admin/audit-log'),
        headers: ApiConfig.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _auditLog = (data['entries'] as List<dynamic>)
            .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _error = 'Failed to load audit log';
      }
    } catch (e) {
      _error = 'Network error: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
