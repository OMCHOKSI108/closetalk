import 'dart:convert';
import 'dart:io';

import '../models/group.dart';

class GroupService {
  final String baseUrl;
  final String Function() getToken;

  GroupService({required this.baseUrl, required this.getToken});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${getToken()}',
      };

  Future<Group> createGroup(CreateGroupRequest request) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl/groups'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode(request.toJson()));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 201) {
        return Group.fromJson(jsonDecode(body) as Map<String, dynamic>);
      }
      throw HttpException('Failed to create group: ${resp.statusCode}');
    } finally {
      client.close();
    }
  }

  Future<Group> getGroup(String groupId) async {
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(Uri.parse('$baseUrl/groups/$groupId'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 200) {
        return Group.fromJson(jsonDecode(body) as Map<String, dynamic>);
      }
      throw HttpException('Failed to get group: ${resp.statusCode}');
    } finally {
      client.close();
    }
  }

  Future<List<GroupListItem>> listGroups() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/groups'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        return (data['groups'] as List<dynamic>)
            .map((g) =>
                GroupListItem.fromJson(g as Map<String, dynamic>))
            .toList();
      }
      throw HttpException('Failed to list groups: ${resp.statusCode}');
    } finally {
      client.close();
    }
  }

  Future<InviteResponse> generateInvite(String groupId) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(
          Uri.parse('$baseUrl/groups/$groupId/invite'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 201) {
        return InviteResponse.fromJson(
            jsonDecode(body) as Map<String, dynamic>);
      }
      throw HttpException('Failed to generate invite: ${resp.statusCode}');
    } finally {
      client.close();
    }
  }

  Future<void> joinGroup(String code) async {
    final client = HttpClient();
    try {
      final req =
          await client.postUrl(Uri.parse('$baseUrl/groups/join'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({'code': code}));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        final body = await resp.transform(utf8.decoder).join();
        throw HttpException(
            'Failed to join group: $body');
      }
    } finally {
      client.close();
    }
  }

  Future<void> addMembers(
      String groupId, List<String> userIds) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(
          Uri.parse('$baseUrl/groups/$groupId/members'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({'user_ids': userIds}));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Failed to add members: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> removeMember(String groupId, String userId) async {
    final client = HttpClient();
    try {
      final req = await client.deleteUrl(
          Uri.parse('$baseUrl/groups/$groupId/members/$userId'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Failed to remove member: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> updateRole(
      String groupId, String userId, String role) async {
    final client = HttpClient();
    try {
      final req = await client.putUrl(Uri.parse(
          '$baseUrl/groups/$groupId/members/$userId/role'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({'role': role}));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Failed to update role: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> leaveGroup(String groupId) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(
          Uri.parse('$baseUrl/groups/$groupId/leave'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Failed to leave group: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> muteGroup(String groupId) async {
    final client = HttpClient();
    try {
      final req =
          await client.postUrl(Uri.parse('$baseUrl/groups/$groupId/mute'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Failed to mute group: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> unmuteGroup(String groupId) async {
    final client = HttpClient();
    try {
      final req =
          await client.postUrl(Uri.parse('$baseUrl/groups/$groupId/unmute'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Failed to unmute group: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> blockGroup(String groupId) async {
    final client = HttpClient();
    try {
      final req =
          await client.postUrl(Uri.parse('$baseUrl/groups/$groupId/block'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Failed to block group: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> updateSettings(
      String groupId, UpdateGroupSettingsRequest request) async {
    final client = HttpClient();
    try {
      final req = await client.putUrl(
          Uri.parse('$baseUrl/groups/$groupId/settings'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode(request.toJson()));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException(
            'Failed to update settings: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> pinMessage(String groupId, String messageId) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(
          Uri.parse('$baseUrl/groups/$groupId/pin'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({'message_id': messageId}));
      final resp = await req.close();
      if (resp.statusCode != 201) {
        throw HttpException('Failed to pin message: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }

  Future<void> unpinMessage(
      String groupId, String messageId) async {
    final client = HttpClient();
    try {
      final req = await client.deleteUrl(Uri.parse(
          '$baseUrl/groups/$groupId/pin/$messageId'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Failed to unpin message: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }
}
