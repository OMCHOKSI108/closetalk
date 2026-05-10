import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(String emoji)? onReact;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onEdit,
    this.onDelete,
    this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(message.createdAt);
    final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          if (message.replyToId != null)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('Replying...',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ),
          Container(
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
                if (message.contentType == 'text')
                  Text(message.content,
                      style: const TextStyle(fontSize: 15)),
                if (message.mediaUrl != null)
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
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time,
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[600])),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.status == 'sent'
                            ? Icons.check
                            : Icons.access_time,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                    ],
                  ],
                ),
                if (message.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 2,
                      children: message.reactions
                          .map((r) => Chip(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                label: Text(r.emoji,
                                    style:
                                        const TextStyle(fontSize: 12)),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
          if (isMe && (onEdit != null || onDelete != null))
            PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onSelected: (value) {
                if (value == 'edit') onEdit?.call();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (onDelete != null)
                  const PopupMenuItem(
                      value: 'delete', child: Text('Delete')),
              ],
              child: const Icon(Icons.more_horiz, size: 16),
            ),
        ],
      ),
    );
  }
}
