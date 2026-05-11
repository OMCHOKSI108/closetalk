import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/chat_provider.dart';
import '../../providers/contact_provider.dart';
import '../../services/sync_service.dart';
import 'stories_screen.dart';
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
  int _filterIndex = 0;
  Set<String> _mutedChats = {};

  Future<void> _loadMuted() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _mutedChats = (prefs.getStringList('muted_chats') ?? []).toSet());
  }

  static const _filters = ['All', 'Unread', 'Personal', 'Groups'];

  @override
  void initState() {
    super.initState();
    _loadMuted();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
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

  bool _isContactOnline(String chatId) {
    final contacts = context.read<ContactProvider>().contacts;
    for (final c in contacts) {
      if (c.conversationId == chatId) return c.isOnline;
    }
    return false;
  }

  bool _isGroupChat(String chatId) {
    final contacts = context.read<ContactProvider>().contacts;
    for (final c in contacts) {
      if (c.conversationId == chatId) return false;
    }
    return true;
  }

  List<_Conversation> _filtered() {
    final chatProvider = context.read<ChatProvider>();
    final pinnedIds = chatProvider.pinnedChatIds;

    var result = List<_Conversation>.from(_conversations);

    switch (_filterIndex) {
      case 1: // Unread
        result = result.where((c) => chatProvider.hasUnread(c.chatId)).toList();
      case 2: // Personal
        result = result.where((c) => !_isGroupChat(c.chatId)).toList();
      case 3: // Groups
        result = result.where((c) => _isGroupChat(c.chatId)).toList();
    }

    result.sort((a, b) {
      final aPinned = pinnedIds.contains(a.chatId);
      final bPinned = pinnedIds.contains(b.chatId);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return b.lastTime.compareTo(a.lastTime);
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ContactProvider>();
    context.watch<ChatProvider>();

    final filtered = _filtered();

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        Column(
          children: [
            const StoriesRow(),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: List.generate(_filters.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(_filters[i]),
                      selected: _filterIndex == i,
                      onSelected: (_) =>
                          setState(() => _filterIndex = i),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No conversations'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final conv = filtered[i];
                          final time = DateFormat('MM/dd HH:mm')
                              .format(conv.lastTime);
                          final title =
                              _resolveName(conv.chatId, conv.senderId);
                          final avatarUrl =
                              _resolveAvatar(conv.chatId);
                          final isOnline =
                              _isContactOnline(conv.chatId);
                          final isPinned = context
                              .read<ChatProvider>()
                              .isChatPinned(conv.chatId);
                          final isMuted = _mutedChats.contains(conv.chatId);

                          return ListTile(
                            leading: UserAvatar(
                              imageUrl: avatarUrl,
                              name: title,
                              radius: 24,
                              isOnline: isOnline,
                            ),
                            title: Row(
                              children: [
                                  if (isPinned)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(right: 4),
                                      child: Icon(Icons.push_pin,
                                          size: 14,
                                          color: Colors.brown[400]),
                                    ),
                                  if (isMuted)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(right: 4),
                                      child: Icon(Icons.volume_off,
                                          size: 14,
                                          color: Colors.grey[400]),
                                    ),
                                Expanded(
                                  child: Text(title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                ),
                              ],
                            ),
                            subtitle: Text(conv.lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(time,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600])),
                                if (context
                                    .read<ChatProvider>()
                                    .hasUnread(conv.chatId))
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.brown[400],
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '${context.read<ChatProvider>().unreadCount(conv.chatId)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () {
                              String? peerId;
                              final contacts = context.read<ContactProvider>().contacts;
                              for (final c in contacts) {
                                if (c.conversationId == conv.chatId) {
                                  peerId = c.contactId;
                                  break;
                                }
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatDetailScreen(
                                    chatId: conv.chatId,
                                    chatTitle: title,
                                    peerUserId: peerId,
                                  ),
                                ),
                              );
                            },
                            onLongPress: () {
                              final cp =
                                  context.read<ChatProvider>();
                              cp.togglePinned(conv.chatId);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(isPinned
                                      ? 'Unpinned'
                                      : 'Pinned'),
                                  duration:
                                      const Duration(seconds: 1),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
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
