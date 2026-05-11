import 'dart:convert';
import 'dart:io';
import 'dart:async';

import '../models/message.dart';

class SyncService {
  final String baseUrl;
  final String Function() getToken;
  String? _lastCursor;
  bool _isSyncing = false;
  int _retryCount = 0;
  static const int _maxRetries = 5;

  SyncService({required this.baseUrl, required this.getToken});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${getToken()}',
      };

  /// Fetch incremental message sync since last cursor.
  /// Returns true if more messages are available (call again for next batch).
  Future<bool> syncMessages({
    int limit = 50,
    void Function(List<Message> messages)? onBatch,
  }) async {
    if (_isSyncing) return false;
    _isSyncing = true;

    try {
      final uri = Uri.parse('$baseUrl/sync/messages').replace(
        queryParameters: {
          'limit': limit.toString(),
          ?(_lastCursor == null ? null : 'after'): _lastCursor!,
        },
      );

      final client = HttpClient();
      try {
        final req = await client.getUrl(uri);
        _headers.forEach((k, v) => req.headers.set(k, v));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          final data = jsonDecode(body) as Map<String, dynamic>;
          final messages = (data['messages'] as List<dynamic>)
              .map((m) => Message.fromJson(m as Map<String, dynamic>))
              .toList();

          if (messages.isNotEmpty) {
            onBatch?.call(messages);
            _lastCursor = data['next_cursor'] as String?;
          }

          _retryCount = 0;
          return data['has_more'] as bool? ?? false;
        }
      } finally {
        client.close();
      }
    } catch (e) {
      _retryCount++;
      if (_retryCount <= _maxRetries) {
        // Exponential backoff: 2^retry * 1000ms
        final delay = Duration(milliseconds: (1 << _retryCount) * 1000);
        await Future.delayed(delay);
        return syncMessages(
          limit: limit,
          onBatch: onBatch,
        );
      }
    } finally {
      _isSyncing = false;
    }

    return false;
  }

  /// Full catch-up sync: fetches ALL messages since last cursor in batches.
  Future<void> fullSync({
    void Function(int total, int batch)? onProgress,
    void Function(List<Message> messages)? onBatch,
  }) async {
    int total = 0;
    bool hasMore = true;

    while (hasMore) {
      hasMore = await syncMessages(
        limit: 50,
        onBatch: (messages) {
          total += messages.length;
          onProgress?.call(total, messages.length);
          onBatch?.call(messages);
        },
      );
    }
  }

  void resetCursor() {
    _lastCursor = null;
    _retryCount = 0;
  }

  String? get lastCursor => _lastCursor;
  bool get isSyncing => _isSyncing;
}
