import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import 'voice_message_content.dart';
import 'location_content.dart';
import 'poll_content.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final String? senderUsername;
  final Message? repliedMessage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(String emoji)? onReact;
  final void Function(String option)? onVote;
  final VoidCallback? onPin;
  final VoidCallback? onForward;
  final VoidCallback? onReply;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.senderUsername,
    this.repliedMessage,
    this.onEdit,
    this.onDelete,
    this.onReact,
    this.onVote,
    this.onPin,
    this.onForward,
    this.onReply,
  });

  Widget _buildStatusIcon() {
    switch (message.status) {
      case 'sending':
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Colors.grey[500],
          ),
        );
      case 'sent':
        return Icon(Icons.check, size: 14, color: Colors.grey[500]);
      case 'delivered':
        return Icon(Icons.done_all, size: 14, color: Colors.grey[500]);
      case 'read':
        return Icon(
          Icons.done_all,
          size: 14,
          color: Colors.blue[400],
        );
      default:
        return Icon(Icons.access_time, size: 14, color: Colors.grey[500]);
    }
  }

  void _showEmojiPicker(BuildContext context) {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add a reaction',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: emojis.map((e) {
                final alreadyReacted =
                    message.reactions.any((r) => r.emoji == e);
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    onReact?.call(e);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: alreadyReacted
                          ? Colors.blue[50]
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: alreadyReacted
                          ? Border.all(color: Colors.blue)
                          : null,
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 28)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationContent() {
    final parts = message.content.split(',');
    if (parts.length != 2) return const Text('Invalid location');
    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);
    if (lat == null || lng == null) return const Text('Invalid location');
    return LocationContent(latitude: lat, longitude: lng);
  }

  Widget _buildImageContent(String base64Str) {
    try {
      final bytes = base64Decode(base64Str);
      return Image.memory(
        bytes,
        height: 150,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image, size: 50),
      );
    } catch (_) {
      return const Icon(Icons.broken_image, size: 50);
    }
  }

  Widget _buildReplyPreview(Message replied) {
    final preview = replied.contentType == 'image'
        ? '[Image]'
        : replied.contentType == 'voice'
            ? '[Voice]'
            : replied.content.length > 80
                ? '${replied.content.substring(0, 80)}...'
                : replied.content;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue[50] : Colors.grey[200],
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.blue[400]! : Colors.grey[400]!,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '@${replied.senderUsername ?? replied.senderId}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isMe ? Colors.blue[800] : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(message.createdAt);
    final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          if (repliedMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _buildReplyPreview(repliedMessage!),
            ),
          InkWell(
            onLongPress: onReact != null
                ? () => _showEmojiPicker(context)
                : null,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue[100] : Colors.grey[100],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: alignment,
                children: [
                  if (!isMe && senderUsername != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('@$senderUsername',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500)),
                    ),
                  if (message.forwardedFrom != null &&
                      message.forwardedFrom!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.reply, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Text('Forwarded from @${message.forwardedFrom}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                  fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  if (message.contentType == 'text' ||
                      message.contentType.isEmpty)
                    Text(message.content,
                        style: const TextStyle(fontSize: 15)),
                  if (message.contentType == 'e2ee')
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Text('Encrypted message',
                            style: TextStyle(fontSize: 13, color: Colors.grey[500], fontStyle: FontStyle.italic)),
                      ],
                    ),
                  if (message.contentType == 'image' &&
                      message.content.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildImageContent(message.content),
                    )
                  else if (message.mediaUrl != null &&
                      message.mediaUrl!.isNotEmpty &&
                      message.contentType != 'voice')
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        message.mediaUrl!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 50),
                      ),
                    ),
                  if (message.contentType == 'voice')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: VoiceMessageContent(
                        message: message,
                        isMe: isMe,
                      ),
                    ),
                  if (message.contentType == 'location')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _buildLocationContent(),
                    ),
                  if (message.contentType == 'poll')
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: PollContent(
                        jsonContent: message.content,
                        myUserId: message.senderId,
                        onVote: (option) => onVote?.call(option),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.disappearedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.timer_outlined,
                              size: 12, color: Colors.grey[500]),
                        ),
                      Text(time,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600])),
                      if (message.editedAt != null) ...[
                        const SizedBox(width: 4),
                        Text('(edited)',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                                fontStyle: FontStyle.italic)),
                      ],
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        _buildStatusIcon(),
                      ],
                    ],
                  ),
                  if (message.reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 2,
                        children: message.reactions
                            .map((r) => InkWell(
                                  onTap: onReact != null
                                      ? () => onReact!(r.emoji)
                                      : null,
                                  child: Chip(
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    label: Text(r.emoji,
                                        style: const TextStyle(
                                            fontSize: 12)),
                                    padding: EdgeInsets.zero,
                                    visualDensity:
                                        VisualDensity.compact,
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onEdit != null || onDelete != null || onPin != null || onForward != null || onReply != null)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'delete') onDelete?.call();
                    if (value == 'pin') onPin?.call();
                    if (value == 'forward') onForward?.call();
                    if (value == 'reply') onReply?.call();
                  },
                  itemBuilder: (_) => [
                    if (onReply != null)
                      const PopupMenuItem(
                          value: 'reply', child: Text('Reply')),
                    if (onForward != null)
                      const PopupMenuItem(
                          value: 'forward', child: Text('Forward')),
                    if (onPin != null)
                      const PopupMenuItem(
                          value: 'pin', child: Text('Pin')),
                    if (onEdit != null)
                      const PopupMenuItem(
                          value: 'edit', child: Text('Edit')),
                    if (onDelete != null)
                      const PopupMenuItem(
                          value: 'delete', child: Text('Delete')),
                  ],
                  child: const Icon(Icons.more_horiz, size: 16),
                ),
              if (onReact != null)
                IconButton(
                  constraints: const BoxConstraints(
                      minWidth: 24, minHeight: 24),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.emoji_emotions_outlined,
                      size: 16, color: Colors.grey),
                  onPressed: () => _showEmojiPicker(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
