import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChatInputBar extends StatefulWidget {
  final FutureOr<void> Function(String text) onSend;
  final FutureOr<void> Function(String text)? onSendFormatted;
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
  bool _hasText = false;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.isLoading) return;
    HapticFeedback.selectionClick();
    _controller.clear();
    setState(() => _hasText = false);
    if (_richTextMode && widget.onSendFormatted != null) {
      await widget.onSendFormatted!(text);
    } else {
      await widget.onSend(text);
    }
  }

  void _onChanged(String value) {
    final nextHasText = value.trim().isNotEmpty;
    if (nextHasText != _hasText) {
      setState(() => _hasText = nextHasText);
    }
    widget.onTextChanged?.call(value);

    if (value.isNotEmpty && !_wasTyping) {
      _wasTyping = true;
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      if (_wasTyping) _wasTyping = false;
    });
  }

  void _showAttachmentSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
              children: [
                _AttachmentAction(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  color: Colors.purple,
                  onTap: widget.onAttach,
                ),
                _AttachmentAction(
                  icon: Icons.photo_camera_outlined,
                  label: 'Camera',
                  color: Colors.blue,
                  onTap: widget.onAttach,
                ),
                _AttachmentAction(
                  icon: Icons.description_outlined,
                  label: 'Document',
                  color: scheme.primary,
                ),
                _AttachmentAction(
                  icon: Icons.headphones_outlined,
                  label: 'Audio',
                  color: Colors.deepOrange,
                  onTap: widget.onRecord,
                ),
                _AttachmentAction(
                  icon: Icons.location_on_outlined,
                  label: 'Location',
                  color: Colors.green,
                  onTap: widget.onLocation,
                ),
                _AttachmentAction(
                  icon: Icons.poll_outlined,
                  label: 'Poll',
                  color: Colors.indigo,
                  onTap: widget.onPoll,
                ),
                const _AttachmentAction(
                  icon: Icons.person_outline,
                  label: 'Contact',
                  color: Colors.teal,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.replyToName != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.reply, size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Replying to @${widget.replyToName}',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.onCancelReply != null)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: widget.onCancelReply,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child:
                                Icon(Icons.close, size: 16, color: scheme.primary),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _ComposerIconButton(
                    icon: Icons.add,
                    tooltip: 'Attach',
                    onPressed: _showAttachmentSheet,
                  ),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 46),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _ComposerIconButton(
                            icon: Icons.emoji_emotions_outlined,
                            tooltip: 'Emoji',
                            onPressed: widget.onSticker,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.newline,
                              keyboardType: TextInputType.multiline,
                              onChanged: _onChanged,
                              decoration: const InputDecoration(
                                hintText: 'Message',
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 13),
                              ),
                            ),
                          ),
                          if (widget.onSendFormatted != null)
                            _ComposerIconButton(
                              icon: _richTextMode
                                  ? Icons.format_bold
                                  : Icons.text_fields,
                              tooltip:
                                  _richTextMode ? 'Plain text' : 'Rich text',
                              selected: _richTextMode,
                              onPressed: () => setState(
                                () => _richTextMode = !_richTextMode,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: _hasText ? scheme.primary : scheme.primaryContainer,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _hasText ? _send : widget.onRecord,
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(
                            scale: animation,
                            child:
                                FadeTransition(opacity: animation, child: child),
                          ),
                          child: widget.isLoading
                              ? SizedBox(
                                  key: const ValueKey('loading'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onPrimary,
                                  ),
                                )
                              : Icon(
                                  _hasText ? Icons.send_rounded : Icons.mic,
                                  key: ValueKey(_hasText ? 'send' : 'mic'),
                                  color: _hasText
                                      ? scheme.onPrimary
                                      : scheme.onPrimaryContainer,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  const _ComposerIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      icon: Icon(
        icon,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      onPressed: onPressed,
    );
  }
}

class _AttachmentAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _AttachmentAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap == null
          ? null
          : () {
              Navigator.pop(context);
              onTap!();
            },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
