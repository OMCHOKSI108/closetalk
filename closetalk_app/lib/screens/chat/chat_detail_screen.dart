import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../models/message.dart';
import '../../models/group.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/group_provider.dart';
import '../../services/group_service.dart';
import '../../services/api_config.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/chat_input_bar.dart';
import 'group_info_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final String? groupId;

  const ChatDetailScreen({
    super.key,
    required this.chatId,
    this.chatTitle = '',
    this.groupId,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _scrollController = ScrollController();
  bool _isLoadingMore = false;

  bool _isSearching = false;
  final _searchCtl = TextEditingController();
  final _searchCtlFocus = FocusNode();
  Timer? _searchDebounce;
  List<SearchResult> _searchResults = [];
  bool _isSearchingMessages = false;
  String? _highlightMessageId;

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
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _searchCtlFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchCtl.clear();
        _searchResults = [];
        _searchDebounce?.cancel();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchCtlFocus.requestFocus();
        });
      }
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearchingMessages = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearchingMessages = true);
    final chat = context.read<ChatProvider>();
    final result = await chat.searchMessages(widget.chatId, query);
    if (mounted) {
      setState(() {
        _searchResults = result.results;
        _isSearchingMessages = false;
      });
    }
  }

  void _onSearchResultTap(SearchResult result) {
    setState(() {
      _highlightMessageId = result.messageId;
      _isSearching = false;
      _searchCtl.clear();
      _searchResults = [];
    });
    _searchCtlFocus.unfocus();

    // Try to scroll to the highlighted message
    final chat = context.read<ChatProvider>();
    final messages = chat.getMessages(widget.chatId);
    final index = messages.indexWhere((m) => m.id == result.messageId);
    if (index >= 0) {
      // ListView is reversed, so scroll to the calculated position
      final targetIndex = messages.length - 1 - index;
      _scrollController.animateTo(
        targetIndex * 72.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }

    // Clear highlight after 4 seconds
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          if (_highlightMessageId == result.messageId) {
            _highlightMessageId = null;
          }
        });
      }
    });
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final bytes = await File(file.path).readAsBytes();
    final b64 = base64Encode(bytes);

    final chat = context.read<ChatProvider>();
    await chat.sendMessage(
      chatId: widget.chatId,
      content: b64,
      contentType: 'image',
    );
  }

  Future<void> _pinMessage(Message msg) async {
    if (widget.groupId == null) return;
    try {
      final groupService = GroupService(
        baseUrl: ApiConfig.authBaseUrl,
        getToken: () => ApiConfig.token ?? '',
      );
      await groupService.pinMessage(widget.groupId!, msg.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message pinned')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pin: $e')),
        );
      }
    }
  }

  void _openGroupInfo() {
    if (widget.groupId == null) return;
    final groupService = GroupService(
      baseUrl: ApiConfig.authBaseUrl,
      getToken: () => ApiConfig.token ?? '',
    );
    final gp = context.read<GroupProvider>();
    gp.fetchGroup(widget.groupId!);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Consumer<GroupProvider>(
          builder: (_, gp, __) {
            final grp = gp.currentGroup;
            return GroupInfoScreen(
              group: grp ??
                  Group(
                    id: widget.groupId!,
                    name: widget.chatTitle,
                    createdBy: '',
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
              groupService: groupService,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchCtl,
                focusNode: _searchCtlFocus,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search messages…',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
              )
            : Text(widget.chatTitle.isEmpty ? 'Chat' : widget.chatTitle),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _toggleSearch,
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _toggleSearch,
              tooltip: 'Search',
            ),
            if (widget.groupId != null)
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: _openGroupInfo,
                tooltip: 'Group info',
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => context
                  .read<ChatProvider>()
                  .fetchMessages(widget.chatId, refresh: true),
              tooltip: 'Refresh',
            ),
          ],
        ],
      ),
      body: _isSearching ? _buildSearchResults() : _buildChat(userId),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearchingMessages) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Text(
          _searchCtl.text.trim().isEmpty
              ? 'Type a keyword to search messages'
              : 'No messages match "${_searchCtl.text.trim()}"',
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      itemBuilder: (_, i) {
        final r = _searchResults[i];
        final time = DateFormat('MM/dd HH:mm').format(r.createdAt);
        final isImage = r.contentType == 'image';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.brown[100],
            child: Text(
              (r.senderName.isNotEmpty ? r.senderName[0] : '?')
                  .toUpperCase(),
              style: TextStyle(
                color: Colors.brown[800],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            r.senderName.isNotEmpty ? r.senderName : r.senderId,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            isImage ? '[Image]' : r.snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            time,
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          onTap: () => _onSearchResultTap(r),
        );
      },
    );
  }

  Widget _buildChat(String userId) {
    return Column(
      children: [
        Expanded(
          child: Consumer<ChatProvider>(
            builder: (_, chat, __) {
              final messages = chat.getMessages(widget.chatId);
              if (messages.isEmpty) {
                return const Center(child: Text('No messages yet'));
              }
              return ListView.builder(
                controller: _scrollController,
                reverse: true,
                itemCount: messages.length + (_isLoadingMore ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == messages.length) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final msg = messages[i];
                  final isHighlighted = msg.id == _highlightMessageId;
                  return Container(
                    color: isHighlighted
                        ? Colors.brown.withValues(alpha: 0.12)
                        : null,
                    child: MessageBubble(
                      message: msg,
                      isMe: msg.senderId == userId,
                      senderUsername: msg.senderUsername,
                      onEdit: msg.senderId == userId
                          ? () => _editMessage(msg)
                          : null,
                      onDelete: msg.senderId == userId
                          ? () => _deleteMessage(msg)
                          : null,
                      onReact: (emoji) => context
                          .read<ChatProvider>()
                          .reactToMessage(msg.id, emoji),
                      onPin: widget.groupId != null
                          ? () => _pinMessage(msg)
                          : null,
                    ),
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
          onAttach: _pickAndSendImage,
        ),
      ],
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
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
