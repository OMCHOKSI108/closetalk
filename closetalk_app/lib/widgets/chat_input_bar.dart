import 'dart:async';
import 'package:flutter/material.dart';

class ChatInputBar extends StatefulWidget {
  final void Function(String text) onSend;
  final void Function(String text)? onSendFormatted;
  final VoidCallback? onAttach;
  final VoidCallback? onRecord;
  final VoidCallback? onSticker;
  final VoidCallback? onLocation;
  final VoidCallback? onPoll;
  final void Function(String text)? onTextChanged;
  final String? replyToName;
  final VoidCallback? onCancelReply;
  final bool isLoading;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onSendFormatted,
    this.onAttach,
    this.onRecord,
    this.onSticker,
    this.onLocation,
    this.onPoll,
    this.onTextChanged,
    this.replyToName,
    this.onCancelReply,
    this.isLoading = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  Timer? _typingDebounce;
  bool _wasTyping = false;
  bool _richTextMode = false;

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;
    if (_richTextMode && widget.onSendFormatted != null) {
      widget.onSendFormatted!(text);
    } else {
      widget.onSend(text);
    }
    _controller.clear();
  }

  void _onChanged(String value) {
    widget.onTextChanged?.call(value);

    if (value.isNotEmpty && !_wasTyping) {
      _wasTyping = true;
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      if (_wasTyping) {
        _wasTyping = false;
      }
    });
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyToName != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.brown[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.reply, size: 14, color: Colors.brown[600]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Replying to @${widget.replyToName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.brown[800],
                          fontStyle: FontStyle.italic,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.onCancelReply != null)
                      GestureDetector(
                        onTap: widget.onCancelReply,
                        child: Icon(Icons.close, size: 16, color: Colors.brown[400]),
                      ),
                  ],
                ),
              ),
            if (widget.replyToName != null) const SizedBox(height: 4),
            Row(
              children: [
                if (widget.onAttach != null)
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: Colors.blue),
                    onPressed: widget.onAttach,
                  ),
                if (widget.onRecord != null)
                  IconButton(
                    icon: const Icon(Icons.mic, color: Colors.blue),
                    onPressed: widget.onRecord,
                  ),
                if (widget.onSticker != null)
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined,
                        color: Colors.orange),
                    onPressed: widget.onSticker,
                  ),
                if (widget.onLocation != null)
                  IconButton(
                    icon: const Icon(Icons.location_on,
                        color: Colors.green),
                    onPressed: widget.onLocation,
                  ),
                if (widget.onPoll != null)
                  IconButton(
                    icon: const Icon(Icons.poll,
                        color: Colors.purple),
                    onPressed: widget.onPoll,
                  ),
                if (widget.onSendFormatted != null)
                  IconButton(
                    icon: Icon(
                      _richTextMode ? Icons.format_bold : Icons.text_fields,
                      color: _richTextMode ? Colors.orange : Colors.grey,
                    ),
                    onPressed: () =>
                        setState(() => _richTextMode = !_richTextMode),
                    tooltip: _richTextMode ? 'Plain text' : 'Rich text',
                  ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    onChanged: _onChanged,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (_richTextMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.article,
                        size: 16, color: Colors.orange[300]),
                  ),
                IconButton(
                  icon: widget.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, color: Colors.blue),
                  onPressed: _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
