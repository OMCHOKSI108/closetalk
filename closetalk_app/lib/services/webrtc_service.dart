import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _candidates = [];

  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;

  final StreamController<Map<String, dynamic>> _signalController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get signalStream => _signalController.stream;

  Function(Map<String, dynamic> signal)? onSendSignal;
  Function(MediaStream stream)? onRemoteStream;

  Future<bool> init() async {
    try {
      await _localRenderer.initialize();
      await _remoteRenderer.initialize();
      final config = {
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
        ],
      };
      _pc = await createPeerConnection(config);
      _pc!.onIceCandidate = (c) {
        _signalController.add({'type': 'call.ice', 'candidate': c.toMap()});
      };
      _pc!.onTrack = (event) {
        if (event.track.kind == 'video' || event.track.kind == 'audio') {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
          onRemoteStream?.call(_remoteStream!);
        }
      };
      _pc!.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          _signalController.add({'type': 'call.ended'});
        }
      };
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<MediaStream?> startLocalVideo() async {
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': true,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (_localStream == null) return null;
    final stream = _localStream!;
    _localRenderer.srcObject = stream;
    for (final track in stream.getTracks()) {
      await _pc?.addTrack(track, stream);
    }
    return stream;
  }

  Future<MediaStream?> startLocalAudio() async {
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (_localStream == null) return null;
    final stream = _localStream!;
    for (final track in stream.getTracks()) {
      await _pc?.addTrack(track, stream);
    }
    return stream;
  }

  Future<Map<String, dynamic>> createOffer() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    return {'sdp': offer.sdp, 'type': offer.type};
  }

  Future<Map<String, dynamic>> createAnswer() async {
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    return {'sdp': answer.sdp, 'type': answer.type};
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdp) async {
    final type = sdp['type'] as String;
    final session = RTCSessionDescription(
      sdp['sdp'] as String,
      type == 'offer' ? 'offer' : 'answer',
    );
    await _pc!.setRemoteDescription(session);
  }

  Future<void> addIceCandidate(Map<String, dynamic> candidateData) async {
    final candidate = RTCIceCandidate(
      candidateData['candidate'] as String? ?? '',
      candidateData['sdpMid'] as String? ?? '',
      candidateData['sdpMLineIndex'] as int? ?? 0,
    );
    try {
      await _pc!.addCandidate(candidate);
    } catch (_) {
      _candidates.add(candidate);
    }
  }

  void applyPendingCandidates() {
    for (final c in _candidates) {
      _pc?.addCandidate(c);
    }
    _candidates.clear();
  }

  Future<void> toggleMute() async {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !track.enabled;
    }
  }

  Future<void> toggleSpeaker(bool on) async {
    await Helper.setSpeakerphoneOn(on);
  }

  Future<void> dispose() async {
    await _signalController.close();
    for (final track in (_localStream?.getTracks() ?? [])) {
      track.stop();
    }
    _localStream = null;
    _remoteStream = null;
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    await _localRenderer.dispose();
    await _remoteRenderer.dispose();
    await _pc?.close();
    _pc = null;
  }
}
