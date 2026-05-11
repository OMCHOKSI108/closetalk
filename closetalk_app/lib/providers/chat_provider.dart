import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../services/api_config.dart';
import 'e2ee_provider.dart';

class ChatProvider extends ChangeNotifier {
  final Map<String, List<Message>> _messages = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, String?> _nextCursors = {};
  final Map<String, Set<String>> _typingUsers = {};
  final Map<String, bool> _pinnedChats = {};
  final Map<String, int> _unreadCounts = {};
  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  bool _isConnected = false;
  bool _readNotifyQueued = false;
  String? currentUserId;

  List<Message> getMessages(String chatId) => _messages[chatId] ?? [];
  bool hasMore(String chatId) => _hasMore[chatId] ?? true;
  bool get isConnected => _isConnected;
  E2EEProvider? _e2ee;

  void setE2EE(E2EEProvider e2ee) => _e2ee = e2ee;
  bool isChatPinned(String chatId) => _pinnedChats[chatId] ?? false;
  List<String> get pinnedChatIds => _pinnedChats.entries
      .where((e) => e.value)
      .map((e) => e.key)
      .toList();

  int unreadCount(String chatId) => _unreadCounts[chatId] ?? 0;
  bool hasUnread(String chatId) => unreadCount(chatId) > 0;

  void markChatRead(String chatId) {
    if ((_unreadCounts[chatId] ?? 0) == 0) return;
    _unreadCounts[chatId] = 0;
    _notifyReadStateSoon();
  }

  void _notifyReadStateSoon() {
    if (_readNotifyQueued) return;
    _readNotifyQueued = true;
    Future.microtask(() {
      _readNotifyQueued = false;
      notifyListeners();
    });
  }

  Set<String> typingUsers(String chatId) => _typingUsers[chatId] ?? {};
  bool isUserTyping(String chatId, String userId) =>
      (_typingUsers[chatId] ?? {}).contains(userId);

  void sendTyping(String chatId, bool isTyping) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'type': isTyping ? 'typing.start' : 'typing.stop',
        'payload': {'chat_id': chatId},
      }));
    } catch (_) {}
  }

  void togglePinned(String chatId) {
    _pinnedChats[chatId] = !(_pinnedChats[chatId] ?? false);
    notifyListeners();
  }

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
          final decrypted = <Message>[];
          for (final msg in paginated.messages) {
            if (_e2ee != null && _e2ee!.enabled && msg.contentType == 'e2ee' && _e2ee!.hasSessionKey(msg.chatId)) {
              final plain = await _e2ee!.decrypt(encryptedBase64: msg.content, chatId: msg.chatId);
              decrypted.add(plain != null ? msg.copyWith(content: plain, contentType: 'text') : msg);
            } else {
              decrypted.add(msg);
            }
          }
          _messages[chatId] = [
            ...? _messages[chatId],
            ...decrypted,
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

  Future<bool> sendMessage({
    required String chatId,
    required String content,
    String contentType = 'text',
    String? replyToId,
    String? mediaId,
    String? mediaUrl,
    String? disappearAfter,
  }) async {
    final tempId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    String finalContent = content;
    String finalContentType = contentType;
    if (_e2ee != null && _e2ee!.enabled && _e2ee!.hasSessionKey(chatId)) {
      final encrypted = await _e2ee!.encrypt(plaintext: content, chatId: chatId);
      if (encrypted != null) {
        finalContent = encrypted;
        finalContentType = 'e2ee';
      }
    }

    final optimistic = Message(
      id: tempId,
      chatId: chatId,
      senderId: currentUserId ?? '',
      content: finalContent,
      contentType: finalContentType,
      mediaId: mediaId,
      mediaUrl: mediaUrl,
      replyToId: replyToId,
      status: 'sending',
      createdAt: DateTime.now(),
    );
    _messages[chatId] = [optimistic, ...(_messages[chatId] ?? [])];
    notifyListeners();

    try {
      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse('${ApiConfig.baseUrl}/messages'),
          headers: ApiConfig.headers,
          body: jsonEncode({
            'chat_id': chatId,
            'content': finalContent,
            'content_type': finalContentType,
            ?(replyToId == null ? null : 'reply_to_id'): replyToId!,
            ?(mediaId == null ? null : 'media_id'): mediaId!,
            ?(mediaUrl == null ? null : 'media_url'): mediaUrl!,
            ?(disappearAfter == null ? null : 'disappear_after'):
                disappearAfter!,
          }),
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          Message sent = optimistic.copyWith(status: 'sent');
          try {
            final body = jsonDecode(response.body);
            if (body is Map<String, dynamic> && body['id'] != null) {
              sent = Message.fromJson(body);
            } else if (body is Map<String, dynamic> &&
                body['message'] is Map<String, dynamic>) {
              sent = Message.fromJson(body['message'] as Map<String, dynamic>);
            }
          } catch (_) {}
          _replaceLocalMessage(chatId, tempId, sent);
          return true;
        }

        _replaceLocalMessage(
          chatId,
          tempId,
          optimistic.copyWith(status: 'failed'),
        );
        return false;
      } finally {
        client.close();
      }
    } catch (_) {
      _replaceLocalMessage(
        chatId,
        tempId,
        optimistic.copyWith(status: 'failed'),
      );
      return false;
    }
  }

  void _replaceLocalMessage(String chatId, String tempId, Message replacement) {
    final list = _messages[chatId];
    if (list == null) return;
    final existingServerIndex =
        list.indexWhere((m) => m.id == replacement.id && m.id != tempId);
    if (existingServerIndex >= 0) {
      list.removeWhere((m) => m.id == tempId);
      notifyListeners();
      return;
    }
    final index = list.indexWhere((m) => m.id == tempId);
    if (index >= 0) {
      list[index] = replacement;
      notifyListeners();
    }
  }

  Future<Map<String, String>?> uploadVoice(
      String filePath, double durationSec) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/messages/voice'),
      );
      request.headers['Authorization'] =
          'Bearer ${ApiConfig.token ?? ''}';
      request.files
          .add(await http.MultipartFile.fromPath('voice', filePath));
      request.fields['duration'] = durationSec.toStringAsFixed(1);

      final streamed = await request.send();
      if (streamed.statusCode == 201) {
        final body = await streamed.stream.bytesToString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final mediaUrl = data['media_url'] as String?;
        final duration = data['duration'] as String?;
        if (mediaUrl != null) {
          return {
            'media_url': mediaUrl,
            'duration': duration ?? durationSec.toStringAsFixed(1),
          };
        }
      }
    } catch (_) {}
    return null;
  }

  Future<bool> forwardMessage({
    required String messageId,
    required List<String> targetChatIds,
  }) async {
    try {
      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse('${ApiConfig.baseUrl}/messages/forward'),
          headers: ApiConfig.headers,
          body: jsonEncode({
            'message_id': messageId,
            'target_chat_ids': targetChatIds,
          }),
        );
        return response.statusCode == 201;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
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
    // Optimistic toggle so the UI reacts instantly. The server is authoritative,
    // so we reconcile with the response (and any websocket broadcast).
    final myId = currentUserId;
    if (myId != null) {
      _toggleReactionLocally(messageId: messageId, userId: myId, emoji: emoji);
      notifyListeners();
    }

    try {
      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse('${ApiConfig.baseUrl}/messages/$messageId/react'),
          headers: ApiConfig.headers,
          body: jsonEncode({'emoji': emoji}),
        );
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final list = (body['reactions'] as List<dynamic>?) ?? const [];
          final reactions = list
              .map((e) => Reaction.fromJson(e as Map<String, dynamic>))
              .toList();
          _applyReactions(messageId: messageId, reactions: reactions);
          notifyListeners();
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // Network error — server didn't see the toggle. Revert.
      if (myId != null) {
        _toggleReactionLocally(messageId: messageId, userId: myId, emoji: emoji);
        notifyListeners();
      }
    }
  }

  void _toggleReactionLocally({
    required String messageId,
    required String userId,
    required String emoji,
  }) {
    for (final entry in _messages.entries) {
      final list = entry.value;
      final index = list.indexWhere((m) => m.id == messageId);
      if (index < 0) continue;
      final msg = list[index];
      final has = msg.reactions
          .any((r) => r.userId == userId && r.emoji == emoji);
      final next = List<Reaction>.from(msg.reactions);
      if (has) {
        next.removeWhere((r) => r.userId == userId && r.emoji == emoji);
      } else {
        next.add(Reaction(
          userId: userId,
          emoji: emoji,
          createdAt: DateTime.now(),
        ));
      }
      list[index] = msg.copyWith(reactions: next);
      return;
    }
  }

  void _applyReactions({
    required String messageId,
    required List<Reaction> reactions,
  }) {
    for (final entry in _messages.entries) {
      final list = entry.value;
      final index = list.indexWhere((m) => m.id == messageId);
      if (index < 0) continue;
      list[index] = list[index].copyWith(reactions: reactions);
      return;
    }
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

  Future<SearchMessagesResponse> searchMessagesGlobal(
    String query, {
    String? cursor,
  }) async {
    if (query.trim().isEmpty) {
      return SearchMessagesResponse(results: []);
    }
    try {
      final params = <String, String>{
        'q': query.trim(),
        'limit': '20',
      };
      if (cursor != null) params['cursor'] = cursor;

      final uri = Uri.parse('${ApiConfig.baseUrl}/messages/search')
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

  Future<void> markDelivered(String messageId) async {
    try {
      final client = http.Client();
      try {
        await client.post(
          Uri.parse('${ApiConfig.baseUrl}/messages/$messageId/delivered'),
          headers: ApiConfig.headers,
        );
      } finally {
        client.close();
      }
    } catch (_) {}
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
      (data) async {
        final json = jsonDecode(data as String) as Map<String, dynamic>;
        await _handleWsEvent(json, chatId);
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

  Future<void> _handleWsEvent(Map<String, dynamic> event, String chatId) async {
    final type = event['type'] as String?;
    final payload = event['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    if (type == 'message.new') {
      var msg = Message.fromJson(payload);
      if (_e2ee != null && _e2ee!.enabled && msg.contentType == 'e2ee') {
        final decrypted = await _e2ee!.decrypt(encryptedBase64: msg.content, chatId: msg.chatId);
        if (decrypted != null) {
          msg = msg.copyWith(content: decrypted, contentType: 'text');
        }
      }
      final msgChatId = msg.chatId;
      final list = _messages[msgChatId] ?? [];
      if (list.any((m) => m.id == msg.id)) return;
      _messages[msgChatId] = [msg, ...(_messages[msgChatId] ?? [])];

      if (currentUserId != null && msg.senderId != currentUserId) {
        markDelivered(msg.id);
        _unreadCounts[msgChatId] = (_unreadCounts[msgChatId] ?? 0) + 1;
      }

      notifyListeners();
    } else if (type == 'message.status') {
      final messageId = payload['message_id'] as String?;
      final status = payload['status'] as String?;
      if (messageId == null || status == null) return;

      for (final entry in _messages.entries) {
        final list = entry.value;
        final index = list.indexWhere((m) => m.id == messageId);
        if (index >= 0) {
          list[index] = list[index].copyWith(status: status);
          notifyListeners();
          return;
        }
      }
    } else if (type == 'message.reaction') {
      final messageId = payload['message_id'] as String?;
      final raw = payload['reactions'] as List<dynamic>?;
      if (messageId == null) return;
      final reactions = (raw ?? const [])
          .map((e) => Reaction.fromJson(e as Map<String, dynamic>))
          .toList();
      _applyReactions(messageId: messageId, reactions: reactions);
      notifyListeners();
    } else if (type == 'typing.start' || type == 'typing.stop') {
      final senderId = payload['sender_id'] as String?;
      final eventChatId = payload['chat_id'] as String? ?? chatId;
      if (senderId == null || senderId == currentUserId) return;

      _typingUsers.putIfAbsent(eventChatId, () => {});
      if (type == 'typing.start') {
        _typingUsers[eventChatId]!.add(senderId);
      } else {
        _typingUsers[eventChatId]!.remove(senderId);
      }
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
