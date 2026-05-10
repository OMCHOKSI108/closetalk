import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/sync_service.dart';
import '../../services/api_config.dart';
import '../chat/chat_detail_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final List<_Conversation> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final convMap = <String, _Conversation>{};
    final sync = SyncService(
      baseUrl: ApiConfig.baseUrl,
      getToken: () => ApiConfig.token ?? '',
    );

    await sync.fullSync(
      onBatch: (messages) {
        for (final msg in messages) {
          final existing = convMap[msg.chatId];
          if (existing == null ||
              msg.createdAt.isAfter(existing.lastTime)) {
            convMap[msg.chatId] = _Conversation(
              chatId: msg.chatId,
              lastMessage: msg.content,
              lastTime: msg.createdAt,
              senderName: msg.senderId,
            );
          }
        }
      },
    );

    if (mounted) {
      setState(() {
        _conversations
          ..clear()
          ..addAll(convMap.values);
        _conversations
            .sort((a, b) => b.lastTime.compareTo(a.lastTime));
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_conversations.isEmpty) {
      return const Center(child: Text('No conversations yet'));
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      child: ListView.builder(
        itemCount: _conversations.length,
        itemBuilder: (_, i) {
          final conv = _conversations[i];
          final time =
              DateFormat('MM/dd HH:mm').format(conv.lastTime);
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue[100],
              child: Text(
                conv.chatId.isNotEmpty
                    ? conv.chatId[0].toUpperCase()
                    : '?',
                style: TextStyle(color: Colors.blue[800]),
              ),
            ),
            title: Text(
                'Chat ${conv.chatId.substring(0, 8)}...',
                style:
                    const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(conv.lastMessage,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(time,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600])),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatDetailScreen(
                  chatId: conv.chatId,
                  chatTitle:
                      'Chat ${conv.chatId.substring(0, 8)}...',
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Conversation {
  final String chatId;
  final String lastMessage;
  final DateTime lastTime;
  final String senderName;

  _Conversation({
    required this.chatId,
    required this.lastMessage,
    required this.lastTime,
    required this.senderName,
  });
}
