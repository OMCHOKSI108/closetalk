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
}
