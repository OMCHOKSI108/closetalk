import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';

class Bookmark {
  final String messageId;
  final String chatId;
  final String preview;
  final DateTime createdAt;

  Bookmark({
    required this.messageId,
    required this.chatId,
    required this.preview,
    required this.createdAt,
  });

  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      messageId: json['message_id'] as String,
      chatId: json['chat_id'] as String,
      preview: json['preview'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class BookmarkProvider extends ChangeNotifier {
  List<Bookmark> _bookmarks = [];
  String? _nextCursor;
  bool _hasMore = true;
  bool _isLoading = false;

  List<Bookmark> get bookmarks => _bookmarks;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  Future<void> fetchBookmarks({bool refresh = false}) async {
    if (refresh) {
      _bookmarks = [];
      _nextCursor = null;
      _hasMore = true;
    }

    if (!_hasMore) return;
    _isLoading = true;
    notifyListeners();

    try {
      final queryParams = <String, String>{'limit': '50'};
      if (_nextCursor != null) queryParams['cursor'] = _nextCursor!;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/bookmarks')
            .replace(queryParameters: queryParams),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (data['bookmarks'] as List<dynamic>?)
                ?.map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        _bookmarks.addAll(items);
        _nextCursor = data['next_cursor'] as String?;
        _hasMore = data['has_more'] as bool? ?? false;
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addBookmark(String messageId, String chatId) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/bookmarks'),
        headers: ApiConfig.headers,
        body: jsonEncode({'message_id': messageId, 'chat_id': chatId}),
      );
      await fetchBookmarks(refresh: true);
    } catch (_) {}
  }

  Future<void> removeBookmark(String messageId) async {
    try {
      await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/bookmarks/$messageId'),
        headers: ApiConfig.headers,
      );
      _bookmarks.removeWhere((b) => b.messageId == messageId);
      notifyListeners();
    } catch (_) {}
  }
}
