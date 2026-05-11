import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../services/api_config.dart';

class ChatProvider extends ChangeNotifier {
  final Map<String, List<Message>> _messages = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, String?> _nextCursors = {};
  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  bool _isConnected = false;

  List<Message> getMessages(String chatId) => _messages[chatId] ?? [];
  bool hasMore(String chatId) => _hasMore[chatId] ?? true;
  bool get isConnected => _isConnected;

  Future<void> fetchMessages(String chatId, {bool refresh = false}) async {
    if (refresh) {
      _messages[chatId] = [];
      _nextCursors[chatId] = null;
      _hasMore[chatId] = true;
    }

    if (!(_hasMore[chatId] ?? true)) return;

    try {
      final queryParams = <String, String>{'limit': '50'};
      final cursor = _nextCursors[chatId];
      if (cursor != null) queryParams['cursor'] = cursor;

      final uri = Uri.parse('${ApiConfig.baseUrl}/messages/$chatId')
          .replace(queryParameters: queryParams);
      final client = http.Client();
      try {
        final response = await client.get(uri, headers: ApiConfig.headers);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final paginated = PaginatedMessages.fromJson(data);
          _messages[chatId] = [
            ...? _messages[chatId],
            ...paginated.messages,
          ];
          _nextCursors[chatId] = paginated.nextCursor;
          _hasMore[chatId] = paginated.hasMore;
          notifyListeners();
        }
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  Future<void> sendMessage({
    required String chatId,
    required String content,
    String contentType = 'text',
    String? replyToId,
    String? mediaId,
  }) async {
    try {
      final client = http.Client();
      try {
        await client.post(
          Uri.parse('${ApiConfig.baseUrl}/messages'),
          headers: ApiConfig.headers,
          body: jsonEncode({
            'chat_id': chatId,
            'content': content,
            'content_type': contentType,
            if (replyToId != null) 'reply_to_id': replyToId,
            if (mediaId != null) 'media_id': mediaId,
          }),
        );
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  Future<void> editMessage(String messageId, String content) async {
    try {
      final client = http.Client();
      try {
        await client.put(
          Uri.parse('${ApiConfig.baseUrl}/messages/$messageId'),
          headers: ApiConfig.headers,
          body: jsonEncode({'content': content}),
        );
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      final client = http.Client();
      try {
        await client.delete(
          Uri.parse('${ApiConfig.baseUrl}/messages/$messageId'),
          headers: ApiConfig.headers,
        );
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  Future<void> reactToMessage(String messageId, String emoji) async {
    try {
      final client = http.Client();
      try {
        await client.post(
          Uri.parse('${ApiConfig.baseUrl}/messages/$messageId/react'),
          headers: ApiConfig.headers,
          body: jsonEncode({'emoji': emoji}),
        );
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  Future<SearchMessagesResponse> searchMessages(
      String chatId, String query,
      {String? cursor}) async {
    if (query.trim().isEmpty) {
      return SearchMessagesResponse(results: []);
    }
    try {
      final params = <String, String>{
        'q': query.trim(),
        'limit': '20',
      };
      if (cursor != null) params['cursor'] = cursor;

      final uri = Uri.parse('${ApiConfig.baseUrl}/messages/$chatId/search')
          .replace(queryParameters: params);
      final client = http.Client();
      try {
        final response = await client.get(uri, headers: ApiConfig.headers);
        if (response.statusCode == 200) {
          return SearchMessagesResponse.fromJson(
              jsonDecode(response.body) as Map<String, dynamic>);
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return SearchMessagesResponse(results: []);
  }

  Future<void> markRead(String messageId) async {
    try {
      final client = http.Client();
      try {
        await client.post(
          Uri.parse('${ApiConfig.baseUrl}/messages/$messageId/read'),
          headers: ApiConfig.headers,
        );
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  void connectWebSocket(String chatId) {
    final token = ApiConfig.token;
    if (token == null) return;

    disconnectWebSocket();

    final uri = Uri.parse('${ApiConfig.wsUrl}/ws?token=$token&chat_id=$chatId');
    _channel = WebSocketChannel.connect(uri);
    _isConnected = true;

    _wsSubscription = _channel!.stream.listen(
      (data) {
        final json = jsonDecode(data as String) as Map<String, dynamic>;
        _handleWsEvent(json);
      },
      onDone: () {
        _isConnected = false;
        Future.delayed(const Duration(seconds: 3), () {
          if (ApiConfig.token != null) connectWebSocket(chatId);
        });
      },
      onError: (_) {
        _isConnected = false;
      },
    );
  }

  void _handleWsEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    final payload = event['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    if (type == 'message.new') {
      final msg = Message.fromJson(payload);
      final chatId = msg.chatId;
      _messages[chatId] = [msg, ...(_messages[chatId] ?? [])];
      notifyListeners();
    }
  }

  void disconnectWebSocket() {
    _wsSubscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }

  @override
  void dispose() {
    disconnectWebSocket();
    super.dispose();
  }
}
