import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/message.dart';
import '../services/api_config.dart';

class VoiceMessageContent extends StatefulWidget {
  final Message message;
  final bool isMe;

  const VoiceMessageContent({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  State<VoiceMessageContent> createState() => _VoiceMessageContentState();
}

class _VoiceMessageContentState extends State<VoiceMessageContent> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      if (widget.message.mediaUrl != null && widget.message.mediaUrl!.isNotEmpty) {
        final url = widget.message.mediaUrl!.startsWith('http')
            ? widget.message.mediaUrl!
            : '${ApiConfig.baseUrl}${widget.message.mediaUrl}';
        if (_position == Duration.zero || _position >= _duration) {
          await _player.stop();
          await _player.play(UrlSource(url));
        } else {
          await _player.resume();
        }
      }
    }
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final totalDuration = _duration.inSeconds > 0
        ? _duration
        : Duration(seconds: int.tryParse(widget.message.content) ?? 0);
    final progress = totalDuration.inSeconds > 0
        ? _position.inSeconds / totalDuration.inSeconds
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: widget.isMe ? Colors.blue[800] : Colors.blue[600],
            size: 36,
          ),
          onPressed: _togglePlay,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        SizedBox(
          width: 80,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.isMe ? Colors.blue[800]! : Colors.blue[600]!,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _isPlaying
              ? _formatDuration(_position)
              : _formatDuration(totalDuration),
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
