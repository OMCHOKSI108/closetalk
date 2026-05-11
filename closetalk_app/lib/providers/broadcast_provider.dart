import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';

class Broadcast {
  final String id;
  final String name;
  final String members;
  final String createdAt;

  Broadcast({
    required this.id,
    required this.name,
    required this.members,
    required this.createdAt,
  });

  factory Broadcast.fromJson(Map<String, dynamic> json) {
    return Broadcast(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      members: json['members'] as String? ?? '[]',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class BroadcastProvider extends ChangeNotifier {
  List<Broadcast> _broadcasts = [];
  bool _isLoading = false;
  String? _error;

  List<Broadcast> get broadcasts => _broadcasts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadBroadcasts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/broadcasts'),
        headers: ApiConfig.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _broadcasts = (data['broadcasts'] as List<dynamic>)
            .map((e) => Broadcast.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _error = 'Failed to load broadcasts';
      }
    } catch (e) {
      _error = 'Network error: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<String?> createBroadcast(String name, List<String> memberIds) async {
    _error = null;
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/broadcasts'),
        headers: ApiConfig.headers,
        body: jsonEncode({'name': name, 'member_ids': memberIds}),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await loadBroadcasts();
        return data['id'] as String?;
      }
      _error = 'Failed to create broadcast';
      return null;
    } catch (e) {
      _error = 'Network error: $e';
      return null;
    }
  }

  Future<bool> sendBroadcast(String broadcastId, String content, {String contentType = 'text'}) async {
    _error = null;
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/broadcasts/$broadcastId/send'),
        headers: ApiConfig.headers,
        body: jsonEncode({'content': content, 'content_type': contentType}),
      );

      if (response.statusCode == 200) {
        return true;
      }
      _error = 'Failed to send broadcast';
      return false;
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
