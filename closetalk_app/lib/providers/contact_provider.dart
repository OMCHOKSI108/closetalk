import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/contact.dart';
import '../services/api_config.dart';

class ContactProvider extends ChangeNotifier {
  List<Contact> _contacts = [];
  List<Contact> _pendingRequests = [];
  List<Contact> _sentRequests = [];
  bool _isLoading = false;
  String? _error;
  List<String> _searchHistory = [];

  List<Contact> get contacts => _contacts;
  List<Contact> get pendingRequests => _pendingRequests;
  List<Contact> get sentRequests => _sentRequests;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<String> get searchHistory => _searchHistory;

  Future<void> loadContacts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/contacts'),
        );
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          final data = jsonDecode(body) as Map<String, dynamic>;
          final list = (data['contacts'] as List<dynamic>)
              .map((e) => Contact.fromJson(e as Map<String, dynamic>))
              .toList();

          _contacts = list.where((c) => c.isAccepted).toList();
          _pendingRequests = list.where((c) => c.isPending).toList();
          _sentRequests = list.where((c) => c.isSent).toList();
        } else {
          _error = 'Failed to load contacts';
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

  Future<Map<String, dynamic>> sendContactRequest(String contactId) async {
    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/contacts'),
        );
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        req.write(jsonEncode({'contact_id': contactId, 'action': 'send'}));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          await loadContacts();
          return {'success': true};
        }
        return jsonDecode(body) as Map<String, dynamic>;
      } finally {
        client.close();
      }
    } catch (e) {
      return {'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> acceptContactRequest(String contactId) async {
    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/contacts/accept'),
        );
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        req.write(jsonEncode({'contact_id': contactId}));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          await loadContacts();
          return jsonDecode(body) as Map<String, dynamic>;
        }
        return jsonDecode(body) as Map<String, dynamic>;
      } finally {
        client.close();
      }
    } catch (e) {
      return {'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> rejectContactRequest(String contactId) async {
    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/contacts/reject'),
        );
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        req.write(jsonEncode({'contact_id': contactId}));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          await loadContacts();
          return {'success': true};
        }
        return jsonDecode(body) as Map<String, dynamic>;
      } finally {
        client.close();
      }
    } catch (e) {
      return {'error': 'Network error: $e'};
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final result = await searchUsersDetailed(query);
    return result.users;
  }

  Future<UserSearchResult> searchUsersDetailed(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const UserSearchResult(users: []);
    try {
      final client = HttpClient();
      try {
        final uri = Uri.parse('${ApiConfig.authBaseUrl}/users/search')
            .replace(queryParameters: {'q': trimmed});
        final req = await client.getUrl(uri);
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        if (resp.statusCode == 200) {
          final data = jsonDecode(body) as Map<String, dynamic>;
          final users = (data['users'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              const [];
          if (users.isNotEmpty) _addToSearchHistory(trimmed);
          return UserSearchResult(users: users);
        }
        return UserSearchResult(
          users: const [],
          statusCode: resp.statusCode,
          error: _errorFromBody(body, resp.statusCode),
        );
      } finally {
        client.close();
      }
    } catch (e) {
      return UserSearchResult(users: const [], error: 'Network error: $e');
    }
  }

  String _errorFromBody(String body, int code) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] != null) return j['error'].toString();
      if (j is Map && j['message'] != null) return j['message'].toString();
    } catch (_) {}
    return 'Search failed (HTTP $code)';
  }

  Future<UserPublicProfile?> getUserProfile(String userId) async {
    try {
      final client = HttpClient();
      try {
        final req = await client.getUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/users/profile/$userId'),
        );
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        if (resp.statusCode == 200) {
          return UserPublicProfile.fromJson(
            jsonDecode(body) as Map<String, dynamic>,
          );
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> blockUser(String blockedUserId) async {
    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/users/block'),
        );
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        req.write(jsonEncode({'blocked_user_id': blockedUserId}));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        if (resp.statusCode == 200) {
          await loadContacts();
          return {'success': true};
        }
        return jsonDecode(body) as Map<String, dynamic>;
      } finally {
        client.close();
      }
    } catch (e) {
      return {'error': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> reportUser(
    String reportedUserId,
    String reason,
  ) async {
    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/users/report'),
        );
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        req.write(jsonEncode({
          'reported_user_id': reportedUserId,
          'reason': reason,
        }));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        if (resp.statusCode == 200) {
          return {'success': true};
        }
        return jsonDecode(body) as Map<String, dynamic>;
      } finally {
        client.close();
      }
    } catch (e) {
      return {'error': 'Network error: $e'};
    }
  }

  Future<DirectConversationResponse?> createDirectConversation(
    String userId,
  ) async {
    try {
      final client = HttpClient();
      try {
        final req = await client.postUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/conversations/direct'),
        );
        req.headers.set('Content-Type', 'application/json');
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
        req.write(jsonEncode({'user_id': userId}));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        if (resp.statusCode == 200) {
          return DirectConversationResponse.fromJson(
            jsonDecode(body) as Map<String, dynamic>,
          );
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }

  void _addToSearchHistory(String query) {
    _searchHistory.remove(query);
    _searchHistory.insert(0, query);
    if (_searchHistory.length > 10) {
      _searchHistory = _searchHistory.sublist(0, 10);
    }
    notifyListeners();
  }

  void clearSearchHistory() {
    _searchHistory.clear();
    notifyListeners();
  }

  void removeFromSearchHistory(String query) {
    _searchHistory.remove(query);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

class UserSearchResult {
  final List<Map<String, dynamic>> users;
  final String? error;
  final int? statusCode;

  const UserSearchResult({required this.users, this.error, this.statusCode});

  bool get hasError => error != null;
}
