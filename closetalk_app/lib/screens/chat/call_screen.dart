import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../../providers/call_provider.dart';

class CallScreen extends StatefulWidget {
  final String remoteUserId;
  final String? remoteDisplayName;
  final bool isVideo;

  const CallScreen({
    super.key,
    required this.remoteUserId,
    this.remoteDisplayName,
    this.isVideo = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _isMuted = false;
  bool _isSpeakerOn = false;

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();
    final webrtc = call.webrtc;

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            // Video area for video calls
            if (widget.isVideo && webrtc != null) ...[
              Expanded(
                child: Stack(
                  children: [
                    // Remote video
                    if (call.status == CallStatus.connected)
                      Container(
                        color: Colors.black,
                        child: RTCVideoView(webrtc.remoteRenderer, mirror: false),
                      )
                    else
                      const Center(child: CircularProgressIndicator(color: Colors.white)),
                    // Local preview (PiP)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: SizedBox(
                        width: 120,
                        height: 180,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: RTCVideoView(webrtc.localRenderer, mirror: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!widget.isVideo) const Spacer(),
            // Avatar for audio calls
            if (!widget.isVideo) ...[
              CircleAvatar(
                radius: 48,
                backgroundColor: Colors.brown[300],
                child: Text(
                  (widget.remoteDisplayName ?? widget.remoteUserId)[0]
                      .toUpperCase(),
                  style: const TextStyle(fontSize: 40, color: Colors.white),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              widget.remoteDisplayName ?? widget.remoteUserId,
              style: const TextStyle(
                  fontSize: 22,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              call.status == CallStatus.ringing
                  ? 'Incoming call...'
                  : call.status == CallStatus.calling
                      ? 'Calling...'
                      : call.status == CallStatus.connected
                          ? _formatDuration(call.callDuration)
                          : 'Call ended',
              style: TextStyle(fontSize: 16, color: Colors.grey[400]),
            ),
            const SizedBox(height: 40),
            if (call.status == CallStatus.ringing) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallActionButton(
                    icon: Icons.call,
                    color: Colors.green,
                    onPressed: () => call.answerCall(),
                  ),
                  const SizedBox(width: 48),
                  _CallActionButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    onPressed: () {
                      call.rejectCall();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ] else if (call.status == CallStatus.calling) ...[
              _CallActionButton(
                icon: Icons.call_end,
                color: Colors.red,
                size: 64,
                onPressed: () async {
                  await call.endCall();
                  Navigator.pop(context);
                },
              ),
            ] else if (call.status == CallStatus.connected) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallActionButton(
                    icon: _isMuted ? Icons.mic_off : Icons.mic,
                    color: _isMuted ? Colors.red : Colors.white54,
                    onPressed: () async {
                      await call.toggleMute();
                      setState(() => _isMuted = !_isMuted);
                    },
                  ),
                  const SizedBox(width: 32),
                  _CallActionButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    size: 64,
                    onPressed: () async {
                      await call.endCall();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 32),
                  _CallActionButton(
                    icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                    color: _isSpeakerOn ? Colors.blue : Colors.white54,
                    onPressed: () async {
                      await call.toggleSpeaker(!_isSpeakerOn);
                      setState(() => _isSpeakerOn = !_isSpeakerOn);
                    },
                  ),
                ],
              ),
            ] else if (call.status == CallStatus.ended) ...[
              _CallActionButton(
                icon: Icons.call_end,
                color: Colors.red,
                size: 64,
                onPressed: () => Navigator.pop(context),
              ),
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onPressed;

  const _CallActionButton({
    required this.icon,
    required this.color,
    this.size = 48,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color.withValues(alpha: 0.2),
      child: IconButton(
        icon: Icon(icon, color: color),
        iconSize: size * 0.45,
        onPressed: onPressed,
      ),
    );
  }
}
