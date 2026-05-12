import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/contact_provider.dart';
import '../../services/api_config.dart';
import '../../services/sync_service.dart';
import '../../widgets/user_avatar.dart';

class PickedChat {
  final String chatId;
  final String title;
  const PickedChat({required this.chatId, required this.title});
}

class ChatPickerScreen extends StatefulWidget {
  const ChatPickerScreen({super.key});

  @override
  State<ChatPickerScreen> createState() => _ChatPickerScreenState();
}

class _ChatPickerScreenState extends State<ChatPickerScreen> {
  final List<_Conv> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final convMap = <String, _Conv>{};

    try {
      final sync = SyncService(
        baseUrl: ApiConfig.baseUrl,
        getToken: () => ApiConfig.token ?? '',
      );
      await sync.fullSync(
        onBatch: (messages) {
          for (final msg in messages) {
            final existing = convMap[msg.chatId];
            if (existing == null || msg.createdAt.isAfter(existing.lastTime)) {
              convMap[msg.chatId] = _Conv(
                chatId: msg.chatId,
                lastMessage: msg.content,
                lastTime: msg.createdAt,
                senderId: msg.senderId,
              );
            }
          }
        },
      );
    } catch (_) {}

    // Fallback: add contacts with conversationId that aren't already in the map
    try {
      final contacts = context.read<ContactProvider>();
      if (contacts.contacts.isEmpty) await contacts.loadContacts();
      for (final c in contacts.contacts) {
        if (c.conversationId != null && !convMap.containsKey(c.conversationId)) {
          convMap[c.conversationId!] = _Conv(
            chatId: c.conversationId!,
            lastMessage: '',
            lastTime: c.createdAt,
            senderId: c.contactId,
          );
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _conversations
        ..clear()
        ..addAll(convMap.values);
      _conversations.sort((a, b) => b.lastTime.compareTo(a.lastTime));
      _loading = false;
    });
  }

  String _resolveTitle(String chatId, String senderId) {
    final contacts = context.read<ContactProvider>().contacts;
    for (final c in contacts) {
      if (c.conversationId == chatId) return c.displayName;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send to...')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? const Center(child: Text('No conversations yet'))
              : ListView.builder(
                  itemCount: _conversations.length,
                  itemBuilder: (_, i) {
                    final conv = _conversations[i];
                    final title = _resolveTitle(conv.chatId, conv.senderId);
                    return ListTile(
                      leading: UserAvatar(
                        imageUrl: _resolveAvatar(conv.chatId),
                        name: title,
                        radius: 22,
                      ),
                      title: Text(title),
                      subtitle: Text(
                        conv.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        PickedChat(chatId: conv.chatId, title: title),
                      ),
                    );
                  },
                ),
    );
  }
}

class _Conv {
  final String chatId;
  final String lastMessage;
  final DateTime lastTime;
  final String senderId;

  _Conv({
    required this.chatId,
    required this.lastMessage,
    required this.lastTime,
    required this.senderId,
  });
}
