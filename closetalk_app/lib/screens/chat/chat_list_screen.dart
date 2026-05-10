import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/contact_provider.dart';
import '../../services/sync_service.dart';
import '../../services/api_config.dart';
import '../../widgets/user_avatar.dart';
import 'chat_detail_screen.dart';
import 'user_search_screen.dart';

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
    _load();
  }

  Future<void> _load() async {
    final contactProvider = context.read<ContactProvider>();
    await Future.wait([
      _loadConversations(),
      contactProvider.loadContacts(),
    ]);
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
          if (existing == null || msg.createdAt.isAfter(existing.lastTime)) {
            convMap[msg.chatId] = _Conversation(
              chatId: msg.chatId,
              lastMessage: msg.content,
              lastTime: msg.createdAt,
              senderId: msg.senderId,
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

  String _resolveName(String chatId, String senderId) {
    final contacts = context.read<ContactProvider>().contacts;
    for (final c in contacts) {
      if (c.conversationId == chatId) {
        return c.displayName;
      }
    }
    if (senderId.isNotEmpty && senderId.length >= 8) {
      return '${senderId.substring(0, 8)}...';
    }
    return 'Chat ${chatId.substring(0, 8)}...';
  }

  String? _resolveAvatar(String chatId) {
    final contacts = context.read<ContactProvider>().contacts;
    for (final c in contacts) {
      if (c.conversationId == chatId && c.avatarUrl.isNotEmpty) {
        return c.avatarUrl;
      }
    }
    return null;
  }

  bool _isContactOnline(String chatId) {
    final contacts = context.read<ContactProvider>().contacts;
    for (final c in contacts) {
      if (c.conversationId == chatId) {
        return c.isOnline;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ContactProvider>();

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        if (_conversations.isEmpty)
          const Center(child: Text('No conversations yet'))
        else
          RefreshIndicator(
            onRefresh: _load,
            child: ListView.builder(
              itemCount: _conversations.length,
              itemBuilder: (_, i) {
                final conv = _conversations[i];
                final time =
                    DateFormat('MM/dd HH:mm').format(conv.lastTime);
                final title = _resolveName(conv.chatId, conv.senderId);
                final avatarUrl = _resolveAvatar(conv.chatId);
                final isOnline = _isContactOnline(conv.chatId);

                return ListTile(
                  leading: UserAvatar(
                    imageUrl: avatarUrl,
                    name: title,
                    radius: 24,
                    isOnline: isOnline,
                  ),
                  title: Text(title,
                      style:
                          const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(conv.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: Text(time,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[600])),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatDetailScreen(
                        chatId: conv.chatId,
                        chatTitle: title,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const UserSearchScreen(),
                ),
              );
              _load();
            },
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class _Conversation {
  final String chatId;
  final String lastMessage;
  final DateTime lastTime;
  final String senderId;
  final String senderName;

  _Conversation({
    required this.chatId,
    required this.lastMessage,
    required this.lastTime,
    required this.senderId,
    required this.senderName,
  });
}
