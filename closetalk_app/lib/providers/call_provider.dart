import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/api_config.dart';
import '../services/webrtc_service.dart';

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
  WebRTCService? _webrtc;
  StreamSubscription? _signalSub;

  CallStatus get status => _status;
  String? get remoteUserId => _remoteUserId;
  String? get remoteDisplayName => _remoteDisplayName;
  bool get isVideo => _isVideo;
  int get callDuration => _callDuration;
  WebRTCService? get webrtc => _webrtc;

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
    _signalSub?.cancel();
    _wsSubscription?.cancel();
    _channel?.sink.close();
  }

  Future<void> _handleSignal(Map<String, dynamic> msg) async {
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
      case 'call.offer':
        if (_webrtc == null) await _initWebRTC();
        await _webrtc!.setRemoteDescription(payload['sdp'] as Map<String, dynamic>);
        _webrtc!.applyPendingCandidates();
        final answer = await _webrtc!.createAnswer();
        _sendSignal('call.answer', {'chat_id': _chatId, 'sdp': answer});
        _status = CallStatus.connected;
        _startTimer();
        notifyListeners();
        break;
      case 'call.answer':
        if (_webrtc != null) {
          await _webrtc!.setRemoteDescription(payload['sdp'] as Map<String, dynamic>);
          _webrtc!.applyPendingCandidates();
          _status = CallStatus.connected;
          _startTimer();
          notifyListeners();
        }
        break;
      case 'call.ice':
        if (_webrtc != null) {
          await _webrtc!.addIceCandidate(payload['candidate'] as Map<String, dynamic>);
        }
        break;
      case 'call.ended':
        _endCall();
        break;
      case 'call.reject':
        _endCall();
        break;
    }
  }

  Future<void> startCall(String targetUserId, String chatId, bool video) async {
    if (_channel == null && ApiConfig.token != null) {
      connectSignaling(ApiConfig.token!, chatId);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _isVideo = video;
    _remoteUserId = targetUserId;
    _chatId = chatId;
    _status = CallStatus.calling;
    notifyListeners();

    await _initWebRTC();
    if (video) {
      final stream = await _webrtc!.startLocalVideo();
      if (stream == null) {
        _endCall();
        return;
      }
    } else {
      final stream = await _webrtc!.startLocalAudio();
      if (stream == null) {
        _endCall();
        return;
      }
    }

    final offer = await _webrtc!.createOffer();
    _sendSignal('call.offer', {
      'target_user_id': targetUserId,
      'chat_id': chatId,
      'is_video': video,
      'sdp': offer,
    });
  }

  Future<void> answerCall() async {
    if (_channel == null && ApiConfig.token != null && _chatId != null) {
      connectSignaling(ApiConfig.token!, _chatId!);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    await _initWebRTC();
    final isVideoCall = _isVideo;
    if (isVideoCall) {
      final stream = await _webrtc!.startLocalVideo();
      if (stream == null) {
        rejectCall();
        return;
      }
    } else {
      final stream = await _webrtc!.startLocalAudio();
      if (stream == null) {
        rejectCall();
        return;
      }
    }
    final answer = await _webrtc!.createAnswer();
    _status = CallStatus.connected;
    _startTimer();
    _sendSignal('call.answer', {'chat_id': _chatId, 'sdp': answer});
    notifyListeners();
  }

  void rejectCall() {
    _sendSignal('call.reject', {'chat_id': _chatId});
    _reset();
  }

  Future<void> endCall() async {
    _sendSignal('call.end', {'chat_id': _chatId});
    await _webrtc?.dispose();
    _webrtc = null;
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

  Future<void> _initWebRTC() async {
    if (_webrtc != null) return;
    _webrtc = WebRTCService();
    await _webrtc!.init();
    _signalSub = _webrtc!.signalStream.listen((signal) {
      if (signal['type'] == 'call.ice') {
        _sendSignal('call.ice', {
          'chat_id': _chatId,
          'target_user_id': _remoteUserId,
          'candidate': signal['candidate'],
        });
      } else if (signal['type'] == 'call.ended') {
        _endCall();
      }
    });
  }

  Future<void> toggleMute() async {
    await _webrtc?.toggleMute();
  }

  Future<void> toggleSpeaker(bool on) async {
    await _webrtc?.toggleSpeaker(on);
  }

  void _reset() {
    _stopTimer();
    _callDuration = 0;
    _status = CallStatus.idle;
    _remoteUserId = null;
    _remoteDisplayName = null;
  }

  @override
  void dispose() {
    _webrtc?.dispose();
    disconnectSignaling();
    super.dispose();
  }
}
