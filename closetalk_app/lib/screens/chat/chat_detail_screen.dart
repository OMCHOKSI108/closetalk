import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/message.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/chat_input_bar.dart';

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;

  const ChatDetailScreen({
    super.key,
    required this.chatId,
    this.chatTitle = '',
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _scrollController = ScrollController();
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    final chat = context.read<ChatProvider>();
    chat.fetchMessages(widget.chatId, refresh: true);
    chat.connectWebSocket(widget.chatId);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels <= 100 && !_isLoadingMore) {
        _loadMore();
      }
    });
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    await context.read<ChatProvider>().fetchMessages(widget.chatId);
    setState(() => _isLoadingMore = false);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatTitle.isEmpty ? 'Chat' : widget.chatTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (_, chat, __) {
                final messages = chat.getMessages(widget.chatId);
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('No messages yet'),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: messages.length + (_isLoadingMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == messages.length) {
                      return const Padding(
                        padding: EdgeInsets.all(8),
                        child: Center(
                            child: CircularProgressIndicator()),
                      );
                    }
                    final msg = messages[i];
                    return MessageBubble(
                      message: msg,
                      isMe: msg.senderId == userId,
                      onEdit: msg.senderId == userId
                          ? () => _editMessage(msg)
                          : null,
                      onDelete: msg.senderId == userId
                          ? () => _deleteMessage(msg)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          ChatInputBar(
            onSend: (text) {
              context
                  .read<ChatProvider>()
                  .sendMessage(chatId: widget.chatId, content: text);
            },
          ),
        ],
      ),
    );
  }

  void _editMessage(Message msg) {
    final controller = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context
                  .read<ChatProvider>()
                  .editMessage(msg.id, controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteMessage(Message msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<ChatProvider>().deleteMessage(msg.id);
              Navigator.pop(context);
            },
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
