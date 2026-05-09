import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketEvent {
  final String type;
  final Map<String, dynamic> payload;

  WebSocketEvent({required this.type, required this.payload});

  factory WebSocketEvent.fromJson(Map<String, dynamic> json) {
    return WebSocketEvent(
      type: json['type'] as String,
      payload: json['payload'] as Map<String, dynamic>,
    );
  }
}

class WebSocketService {
  WebSocketChannel? _channel;
  final StreamController<WebSocketEvent> _controller =
      StreamController<WebSocketEvent>.broadcast();
  Timer? _pingTimer;
  String? _lastToken;
  String? _lastChatId;
  bool _isConnected = false;

  Stream<WebSocketEvent> get events => _controller.stream;
  bool get isConnected => _isConnected;

  Future<void> connect({
    required String wsUrl,
    required String token,
    required String chatId,
  }) async {
    _lastToken = token;
    _lastChatId = chatId;

    final uri = Uri.parse('$wsUrl/ws?token=$token&chat_id=$chatId');
    _channel = WebSocketChannel.connect(uri);

    await _channel!.ready;
    _isConnected = true;

    _startPing();

    _channel!.stream.listen(
      (data) {
        final json = jsonDecode(data as String) as Map<String, dynamic>;
        if (json['type'] == 'ping') {
          _send({'type': 'pong'});
          return;
        }
        _controller.add(WebSocketEvent.fromJson(json));
      },
      onError: (error) {
        _isConnected = false;
        _scheduleReconnect();
      },
      onDone: () {
        _isConnected = false;
        _scheduleReconnect();
      },
    );
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      try {
        _channel?.sink.add(jsonEncode({'type': 'pong'}));
      } catch (_) {}
    });
  }

  void _scheduleReconnect() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isConnected &&
          _lastToken != null &&
          _lastChatId != null &&
          _lastToken!.isNotEmpty) {
        connect(
          wsUrl: '',
          token: _lastToken!,
          chatId: _lastChatId!,
        );
      }
    });
  }

  void sendTyping(bool isTyping) {
    _send({
      'type': isTyping ? 'typing.start' : 'typing.stop',
      'payload': {'chat_id': _lastChatId},
    });
  }

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void disconnect() {
    _pingTimer?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _controller.close();
  }
}
