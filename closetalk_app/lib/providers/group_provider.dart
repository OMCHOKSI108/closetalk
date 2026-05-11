import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/group.dart';
import '../services/api_config.dart';

class GroupProvider extends ChangeNotifier {
  List<GroupListItem> _groups = [];
  Group? _currentGroup;
  InviteResponse? _inviteResponse;
  String? _error;
  bool _isLoading = false;

  List<GroupListItem> get groups => _groups;
  Group? get currentGroup => _currentGroup;
  InviteResponse? get inviteResponse => _inviteResponse;
  String? get error => _error;
  bool get isLoading => _isLoading;

  Future<void> fetchGroups() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/groups'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _groups = (data['groups'] as List<dynamic>)
            .map((g) => GroupListItem.fromJson(g as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _error = 'Failed to load groups';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchGroup(String groupId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        _currentGroup = Group.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
    } catch (_) {
      _error = 'Failed to load group';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createGroup(CreateGroupRequest request) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/groups'),
        headers: ApiConfig.headers,
        body: jsonEncode(request.toJson()),
      );
      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _error = 'Failed to create group';
    } catch (_) {
      _error = 'Network error';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<InviteResponse?> generateInvite(String groupId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId/invite'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 201) {
        _inviteResponse = InviteResponse.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
        notifyListeners();
        return _inviteResponse;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> joinGroup(String code) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/join'),
        headers: ApiConfig.headers,
        body: jsonEncode({'code': code}),
      );
      if (response.statusCode == 200) {
        await fetchGroups();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<List<DiscoverGroup>> discoverGroups({String query = ''}) async {
    try {
      final uri = Uri.parse('${ApiConfig.authBaseUrl}/groups/discover')
          .replace(queryParameters: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
      });
      final response = await http.get(uri, headers: ApiConfig.headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['groups'] as List<dynamic>?)
                ?.map((g) => DiscoverGroup.fromJson(g as Map<String, dynamic>))
                .toList() ??
            const [];
      }
    } catch (_) {}
    return const [];
  }

  Future<JoinResult> joinPublicGroup(String groupId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/join'),
        headers: ApiConfig.headers,
        body: jsonEncode({'group_id': groupId}),
      );
      if (response.statusCode == 200) {
        await fetchGroups();
        return const JoinResult(success: true);
      }
      String? message;
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          message = body['message'].toString();
        } else if (body is Map && body['error'] != null) {
          message = body['error'].toString();
        }
      } catch (_) {}
      return JoinResult(
        success: false,
        error: message ?? 'Could not join (HTTP ${response.statusCode})',
      );
    } catch (e) {
      return JoinResult(success: false, error: 'Network error: $e');
    }
  }

  Future<void> addMembers(String groupId, List<String> userIds) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId/members'),
        headers: ApiConfig.headers,
        body: jsonEncode({'user_ids': userIds}),
      );
    } catch (_) {}
  }

  Future<void> removeMember(String groupId, String userId) async {
    try {
      await http.delete(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId/members/$userId'),
        headers: ApiConfig.headers,
      );
    } catch (_) {}
  }

  Future<void> updateRole(String groupId, String userId, String role) async {
    try {
      await http.put(
        Uri.parse(
            '${ApiConfig.authBaseUrl}/groups/$groupId/members/$userId/role'),
        headers: ApiConfig.headers,
        body: jsonEncode({'role': role}),
      );
    } catch (_) {}
  }

  Future<void> leaveGroup(String groupId) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId/leave'),
        headers: ApiConfig.headers,
      );
      await fetchGroups();
    } catch (_) {}
  }

  Future<JoinResult> muteGroup(String groupId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId/mute'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        await fetchGroups();
        return const JoinResult(success: true);
      }
      return JoinResult(
        success: false,
        error: _parseError(response.body) ??
            'Could not mute group (HTTP ${response.statusCode})',
      );
    } catch (e) {
      return JoinResult(success: false, error: 'Network error: $e');
    }
  }

  Future<JoinResult> unmuteGroup(String groupId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId/unmute'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        await fetchGroups();
        return const JoinResult(success: true);
      }
      return JoinResult(
        success: false,
        error: _parseError(response.body) ??
            'Could not unmute group (HTTP ${response.statusCode})',
      );
    } catch (e) {
      return JoinResult(success: false, error: 'Network error: $e');
    }
  }

  Future<JoinResult> blockGroup(String groupId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId/block'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        await fetchGroups();
        return const JoinResult(success: true);
      }
      return JoinResult(
        success: false,
        error: _parseError(response.body) ??
            'Could not block group (HTTP ${response.statusCode})',
      );
    } catch (e) {
      return JoinResult(success: false, error: 'Network error: $e');
    }
  }

  Future<void> updateSettings(
      String groupId, UpdateGroupSettingsRequest request) async {
    try {
      await http.put(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId/settings'),
        headers: ApiConfig.headers,
        body: jsonEncode(request.toJson()),
      );
    } catch (_) {}
  }

  Future<void> pinMessage(String groupId, String messageId) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId/pin'),
        headers: ApiConfig.headers,
        body: jsonEncode({'message_id': messageId}),
      );
    } catch (_) {}
  }

  Future<void> unpinMessage(String groupId, String messageId) async {
    try {
      await http.delete(
        Uri.parse('${ApiConfig.authBaseUrl}/groups/$groupId/pin/$messageId'),
        headers: ApiConfig.headers,
      );
    } catch (_) {}
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String? _parseError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message'].toString();
      }
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {}
    return null;
  }
}

class DiscoverGroup {
  final String id;
  final String name;
  final String description;
  final String avatarUrl;
  final int memberCount;
  final int memberLimit;
  final bool isMember;
  final DateTime createdAt;

  const DiscoverGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.avatarUrl,
    required this.memberCount,
    required this.memberLimit,
    required this.isMember,
    required this.createdAt,
  });

  factory DiscoverGroup.fromJson(Map<String, dynamic> json) {
    return DiscoverGroup(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      memberCount: json['member_count'] as int? ?? 0,
      memberLimit: json['member_limit'] as int? ?? 1000,
      isMember: json['is_member'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class JoinResult {
  final bool success;
  final String? error;
  const JoinResult({required this.success, this.error});
}
  
