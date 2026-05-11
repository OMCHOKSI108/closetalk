import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_config.dart';

enum CallStatus { idle, calling, ringing, connected, ended }

class CallProvider extends ChangeNotifier {
  CallStatus _status = CallStatus.idle;
  String? _remoteUserId;
  String? _remoteDisplayName;
  String? _chatId;
  bool _isVideo = false;
  Timer? _callTimer;
  int _callDuration = 0;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;

  CallStatus get status => _status;
  String? get remoteUserId => _remoteUserId;
  String? get remoteDisplayName => _remoteDisplayName;
  bool get isVideo => _isVideo;
  int get callDuration => _callDuration;

  void connectSignaling(String token, String chatId) {
    disconnectSignaling();
    final uri = Uri.parse('${ApiConfig.wsUrl}/ws?token=$token&chat_id=$chatId');
    _channel = WebSocketChannel.connect(uri);
    _chatId = chatId;

    _wsSubscription = _channel!.stream.listen(
      (data) {
        final json = jsonDecode(data as String) as Map<String, dynamic>;
        _handleSignal(json);
      },
      onDone: () {
        Future.delayed(const Duration(seconds: 3), () {
          if (ApiConfig.token != null && _chatId != null) {
            connectSignaling(ApiConfig.token!, _chatId!);
          }
        });
      },
    );
  }

  void disconnectSignaling() {
    _wsSubscription?.cancel();
    _channel?.sink.close();
  }

  void _handleSignal(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    final payload = msg['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    switch (type) {
      case 'call.incoming':
        _remoteUserId = payload['caller_id'] as String?;
        _remoteDisplayName = payload['caller_name'] as String?;
        _isVideo = payload['is_video'] as bool? ?? false;
        _status = CallStatus.ringing;
        notifyListeners();
        break;
      case 'call.answered':
        _status = CallStatus.connected;
        _startTimer();
        notifyListeners();
        break;
      case 'call.ended':
        _endCall();
        break;
    }
  }

  void startCall(String targetUserId, String chatId, bool video) {
    _isVideo = video;
    _remoteUserId = targetUserId;
    _chatId = chatId;
    _status = CallStatus.calling;
    notifyListeners();

    _sendSignal('call.offer', {
      'target_user_id': targetUserId,
      'chat_id': chatId,
      'is_video': video,
    });
  }

  void answerCall() {
    _status = CallStatus.connected;
    _startTimer();
    _sendSignal('call.answer', {'chat_id': _chatId});
    notifyListeners();
  }

  void rejectCall() {
    _sendSignal('call.reject', {'chat_id': _chatId});
    _reset();
  }

  void endCall() {
    _sendSignal('call.end', {'chat_id': _chatId});
    _endCall();
  }

  void _endCall() {
    _stopTimer();
    _status = CallStatus.ended;
    notifyListeners();
    Future.delayed(const Duration(seconds: 2), () {
      _reset();
    });
  }

  void _startTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _callDuration++;
      notifyListeners();
    });
  }

  void _stopTimer() {
    _callTimer?.cancel();
    _callTimer = null;
  }

  void _sendSignal(String type, Map<String, dynamic> payload) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({
        'type': type,
        'payload': payload,
      }));
    } catch (_) {}
  }

  void _reset() {
    _stopTimer();
    _callDuration = 0;
    _status = CallStatus.idle;
    _remoteUserId = null;
    _remoteDisplayName = null;
    notifyListeners();
  }

  @override
  void dispose() {
    endCall();
    disconnectSignaling();
    super.dispose();
  }
}
