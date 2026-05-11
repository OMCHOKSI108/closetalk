import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class VoiceRecorderSheet extends StatefulWidget {
  final Future<Map<String, String>?> Function(String filePath, double durationSec) onUpload;
  final VoidCallback onCancel;

  const VoiceRecorderSheet({
    super.key,
    required this.onUpload,
    required this.onCancel,
  });

  @override
  State<VoiceRecorderSheet> createState() => _VoiceRecorderSheetState();
}

enum _SheetState { idle, recording, preview }

class _VoiceRecorderSheetState extends State<VoiceRecorderSheet> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  _SheetState _state = _SheetState.idle;
  String? _recordedPath;
  int _durationSec = 0;
  Timer? _timer;
  bool _isUploading = false;

  StreamSubscription? _playerStateSub;
  bool _isPlaying = false;

  @override
  void dispose() {
    _timer?.cancel();
    _playerStateSub?.cancel();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _requestMicPermission() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
      }
    }
    return;
  }

  Future<void> _startRecording() async {
    await _requestMicPermission();
    if (!(await Permission.microphone.isGranted)) return;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 32000,
        numChannels: 1,
      ),
      path: path,
    );

    _recordedPath = path;
    _durationSec = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _durationSec++);
    });

    setState(() => _state = _SheetState.recording);
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (path != null) _recordedPath = path;

    _playerStateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _isPlaying = s == PlayerState.playing);
    });

    setState(() => _state = _SheetState.preview);
  }

  void _togglePlayback() async {
    if (_recordedPath == null) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.stop();
      await _player.play(DeviceFileSource(_recordedPath!));
    }
  }

  Future<void> _send() async {
    if (_recordedPath == null || _isUploading) return;
    setState(() => _isUploading = true);

    final result = await widget.onUpload(_recordedPath!, _durationSec.toDouble());
    if (mounted) {
      Navigator.pop(context, result != null);
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send voice message')),
        );
      }
    }
  }

  String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Voice Message',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          if (_state == _SheetState.idle)
            _buildIdleState()
          else if (_state == _SheetState.recording)
            _buildRecordingState()
          else
            _buildPreviewState(),
        ],
      ),
    );
  }

  Widget _buildIdleState() {
    return Column(
      children: [
        const Text('Tap to start recording'),
        const SizedBox(height: 16),
        FloatingActionButton.large(
          heroTag: 'record_start',
          backgroundColor: Colors.blue,
          onPressed: _startRecording,
          child: const Icon(Icons.mic, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            widget.onCancel();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildRecordingState() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatTime(_durationSec),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FloatingActionButton.large(
          heroTag: 'record_stop',
          backgroundColor: Colors.red,
          onPressed: _stopRecording,
          child: const Icon(Icons.stop, color: Colors.white, size: 40),
        ),
      ],
    );
  }

  Widget _buildPreviewState() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                size: 48,
                color: Colors.blue,
              ),
              onPressed: _togglePlayback,
            ),
            const SizedBox(width: 16),
            Text(
              _formatTime(_durationSec),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            OutlinedButton.icon(
              onPressed: _isUploading
                  ? null
                  : () {
                      _player.stop();
                      Navigator.pop(context);
                      widget.onCancel();
                    },
              icon: const Icon(Icons.close),
              label: const Text('Discard'),
            ),
            FilledButton.icon(
              onPressed: _isUploading ? null : _send,
              icon: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(_isUploading ? 'Sending...' : 'Send'),
            ),
          ],
        ),
      ],
    );
  }
}
