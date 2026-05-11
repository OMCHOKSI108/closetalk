import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

class MessageService {
  final String baseUrl;
  final String Function() getToken;

  MessageService({required this.baseUrl, required this.getToken});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${getToken()}',
      };

  Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String content,
    String contentType = 'text',
    String? mediaId,
    String? replyToId,
  }) async {
    final body = <String, dynamic>{
      'chat_id': chatId,
      'content': content,
      'content_type': contentType,
      ?(mediaId == null ? null : 'media_id'): mediaId!,
      ?(replyToId == null ? null : 'reply_to_id'): replyToId!,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to send message: ${response.body}');
  }

  Future<Map<String, dynamic>> getMessages({
    required String chatId,
    String? cursor,
    int limit = 50,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      ?(cursor == null ? null : 'cursor'): cursor!,
    };
    final uri = Uri.parse('$baseUrl/messages/$chatId')
        .replace(queryParameters: queryParams);

    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to fetch messages: ${response.body}');
  }

  Future<void> editMessage({
    required String messageId,
    required String content,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/messages/$messageId'),
      headers: _headers,
      body: jsonEncode({'content': content}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to edit message: ${response.body}');
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/messages/$messageId'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete message: ${response.body}');
    }
  }

  Future<void> reactToMessage({
    required String messageId,
    required String emoji,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/messages/$messageId/react'),
      headers: _headers,
      body: jsonEncode({'emoji': emoji}),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to react: ${response.body}');
    }
  }

  Future<void> markRead(String messageId) async {
    await http.post(
      Uri.parse('$baseUrl/messages/$messageId/read'),
      headers: _headers,
    );
  }

  Future<void> addBookmark({
    required String messageId,
    required String chatId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/bookmarks'),
      headers: _headers,
      body: jsonEncode({'message_id': messageId, 'chat_id': chatId}),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to bookmark: ${response.body}');
    }
  }

  Future<void> removeBookmark(String messageId) async {
    await http.delete(
      Uri.parse('$baseUrl/bookmarks/$messageId'),
      headers: _headers,
    );
  }
}
