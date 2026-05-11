import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';

class ScheduledMessage {
  final String id;
  final String chatId;
  final String content;
  final String contentType;
  final String sendAt;
  final String status;
  final String createdAt;

  ScheduledMessage({
    required this.id,
    required this.chatId,
    required this.content,
    this.contentType = 'text',
    required this.sendAt,
    this.status = 'pending',
    required this.createdAt,
  });

  factory ScheduledMessage.fromJson(Map<String, dynamic> json) {
    return ScheduledMessage(
      id: json['id'] as String? ?? '',
      chatId: json['chat_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      contentType: json['content_type'] as String? ?? 'text',
      sendAt: json['send_at'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] as String? ?? '',
    );
  }
}

class ScheduleProvider extends ChangeNotifier {
  List<ScheduledMessage> _scheduled = [];
  bool _isLoading = false;
  String? _error;

  List<ScheduledMessage> get scheduled => _scheduled;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadScheduled() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/messages/scheduled'),
        headers: ApiConfig.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _scheduled = (data['scheduled'] as List<dynamic>)
            .map((e) => ScheduledMessage.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _error = 'Failed to load scheduled messages';
      }
    } catch (e) {
      _error = 'Network error: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<String?> scheduleMessage({
    required String chatId,
    required String content,
    required String sendAt,
    String contentType = 'text',
    String? mediaUrl,
    String? replyToId,
  }) async {
    _error = null;
    try {
      final body = <String, dynamic>{
        'chat_id': chatId,
        'content': content,
        'content_type': contentType,
        'send_at': sendAt,
      };
      if (mediaUrl != null) body['media_url'] = mediaUrl;
      if (replyToId != null) body['reply_to_id'] = replyToId;

      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/messages/schedule'),
        headers: ApiConfig.headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await loadScheduled();
        return data['id'] as String?;
      }
      _error = 'Failed to schedule message';
      return null;
    } catch (e) {
      _error = 'Network error: $e';
      return null;
    }
  }

  Future<bool> cancelScheduled(String id) async {
    _error = null;
    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.authBaseUrl}/messages/scheduled/$id'),
        headers: ApiConfig.headers,
      );

      if (response.statusCode == 200) {
        await loadScheduled();
        return true;
      }
      _error = 'Failed to cancel scheduled message';
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
