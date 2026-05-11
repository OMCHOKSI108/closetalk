import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/message.dart';
import '../../models/group.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/call_provider.dart';
import '../../providers/group_provider.dart';
import '../../services/group_service.dart';
import '../../services/api_config.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/chat_input_bar.dart';
import '../../widgets/voice_recorder_sheet.dart';
import '../../widgets/sticker_picker_sheet.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/poll_creator_sheet.dart';
import 'forward_to_screen.dart';
import 'group_info_screen.dart';
import 'call_screen.dart';

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

  String? _replyToMessageId;
  Message? _repliedMessage;

  Timer? _typingDebounce;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _loadMuted();
    final chat = context.read<ChatProvider>();
    final userId = context.read<AuthProvider>().user?.id;
    chat.currentUserId = userId;
    chat.fetchMessages(widget.chatId, refresh: true);
    chat.connectWebSocket(widget.chatId);
    chat.markChatRead(widget.chatId);

    _scrollController.addListener(() {
      if (_scrollController.position.pixels <= 100 && !_isLoadingMore) {
        _loadMore();
      }
      // Auto-mark visible messages as read when scrolling near bottom
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        _markVisibleAsRead();
      }
    });
  }

  void _markVisibleAsRead() {
    final chat = context.read<ChatProvider>();
    final messages = chat.getMessages(widget.chatId);
    if (messages.isEmpty) return;

    // Mark the oldest visible message as seen (batched via WS)
    final oldest = messages.last;
    if (oldest.senderId != (context.read<AuthProvider>().user?.id ?? '') &&
        oldest.status != 'read') {
      chat.markRead(oldest.id);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    await context.read<ChatProvider>().fetchMessages(widget.chatId);
    setState(() => _isLoadingMore = false);
  }

  Future<void> _loadMuted() async {
    final prefs = await SharedPreferences.getInstance();
    final muted = prefs.getStringList('muted_chats') ?? [];
    if (mounted) setState(() => _isMuted = muted.contains(widget.chatId));
  }

  Future<void> _toggleMute() async {
    final prefs = await SharedPreferences.getInstance();
    final muted = (prefs.getStringList('muted_chats') ?? []).toList();
    if (_isMuted) {
      muted.remove(widget.chatId);
    } else {
      muted.add(widget.chatId);
    }
    await prefs.setStringList('muted_chats', muted);
    setState(() => _isMuted = !_isMuted);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isMuted ? 'Chat muted' : 'Chat unmuted'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
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

  void _createPoll() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => PollCreatorSheet(
        onSend: (jsonContent) {
          Navigator.pop(context);
          context.read<ChatProvider>().sendMessage(
                chatId: widget.chatId,
                content: jsonContent,
                contentType: 'poll',
              );
        },
      ),
    );
  }

  void _shareLocation() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => LocationPickerSheet(
        onSelected: (lat, lng) {
          Navigator.pop(context);
          context.read<ChatProvider>().sendMessage(
                chatId: widget.chatId,
                content: '$lat,$lng',
                contentType: 'location',
              );
        },
      ),
    );
  }

  void _showStickerPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StickerPickerSheet(
        onSelected: (emoji) {
          Navigator.pop(context);
          context.read<ChatProvider>().sendMessage(
                chatId: widget.chatId,
                content: emoji,
                contentType: 'sticker',
              );
        },
        onGifSelected: (gifUrl) {
          Navigator.pop(context);
          context.read<ChatProvider>().sendMessage(
                chatId: widget.chatId,
                content: gifUrl,
                contentType: 'image',
                mediaUrl: gifUrl,
              );
        },
      ),
    );
  }

  void _showVoiceRecorder() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => VoiceRecorderSheet(
        onUpload: (path, duration) async {
          final chat = context.read<ChatProvider>();
          final result = await chat.uploadVoice(path, duration);
          if (result != null) {
            await chat.sendMessage(
              chatId: widget.chatId,
              content: result['duration'] ?? duration.toStringAsFixed(1),
              contentType: 'voice',
              mediaUrl: result['media_url'],
            );
            return result;
          }
          return null;
        },
        onCancel: () {},
      ),
    );
  }

  void _forwardMessage(Message msg) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardToScreen(
          messageId: msg.id,
          onForward: (messageId, targetChatIds) async {
            final chat = context.read<ChatProvider>();
            return chat.forwardMessage(
              messageId: messageId,
              targetChatIds: targetChatIds,
            );
          },
        ),
      ),
    );
  }

  Message? _findMessageById(String id) {
    final messages =
        context.read<ChatProvider>().getMessages(widget.chatId);
    for (final m in messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _replyToMessage(Message msg) {
    setState(() {
      _replyToMessageId = msg.id;
      _repliedMessage = msg;
    });
  }

  void _onTypingChanged(String value) {
    _typingDebounce?.cancel();
    final chat = context.read<ChatProvider>();
    if (value.isNotEmpty) {
      chat.sendTyping(widget.chatId, true);
      _typingDebounce = Timer(const Duration(seconds: 3), () {
        chat.sendTyping(widget.chatId, false);
      });
    } else {
      chat.sendTyping(widget.chatId, false);
    }
  }

  void _cancelReply() {
    setState(() {
      _replyToMessageId = null;
      _repliedMessage = null;
    });
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
              icon: const Icon(Icons.phone, color: Colors.green),
              tooltip: 'Voice call',
              onPressed: () {
                final call = context.read<CallProvider>();
                call.startCall(
                  widget.chatId,
                  widget.chatId,
                  false,
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      remoteUserId: widget.chatId,
                      remoteDisplayName: widget.chatTitle,
                      isVideo: false,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.videocam, color: Colors.blue),
              tooltip: 'Video call',
              onPressed: () {
                final call = context.read<CallProvider>();
                call.startCall(
                  widget.chatId,
                  widget.chatId,
                  true,
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      remoteUserId: widget.chatId,
                      remoteDisplayName: widget.chatTitle,
                      isVideo: true,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
              tooltip: _isMuted ? 'Unmute' : 'Mute',
              onPressed: _toggleMute,
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
                  final replied = msg.replyToId != null
                      ? _findMessageById(msg.replyToId!)
                      : null;
                  return Container(
                    color: isHighlighted
                        ? Colors.brown.withValues(alpha: 0.12)
                        : null,
                    child: MessageBubble(
                      message: msg,
                      isMe: msg.senderId == userId,
                      senderUsername: msg.senderUsername,
                      repliedMessage: replied,
                      onEdit: msg.senderId == userId
                          ? () => _editMessage(msg)
                          : null,
                      onDelete: msg.senderId == userId
                          ? () => _deleteMessage(msg)
                          : null,
                      onReact: (emoji) => context
                          .read<ChatProvider>()
                          .reactToMessage(msg.id, emoji),
                      onVote: msg.contentType == 'poll'
                          ? (option) => _voteInPoll(msg, option)
                          : null,
                      onPin: widget.groupId != null
                          ? () => _pinMessage(msg)
                          : null,
                      onForward: () => _forwardMessage(msg),
                      onReply: () => _replyToMessage(msg),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Consumer<ChatProvider>(
          builder: (_, chat, __) {
            final typing = chat.typingUsers(widget.chatId)
                .where((uid) => uid != userId)
                .toList();
            if (typing.isEmpty) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.brown[400],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    typing.length == 1
                        ? 'Someone is typing...'
                        : '${typing.length} people are typing...',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            );
          },
        ),
          ChatInputBar(
            onSticker: _showStickerPicker,
            onLocation: _shareLocation,
            onPoll: _createPoll,
            onSend: (text) {
            context
                .read<ChatProvider>()
                .sendMessage(
                  chatId: widget.chatId,
                  content: text,
                  replyToId: _replyToMessageId,
                );
            _cancelReply();
            _typingDebounce?.cancel();
            context.read<ChatProvider>().sendTyping(widget.chatId, false);
          },
          onAttach: _pickAndSendImage,
          onRecord: _showVoiceRecorder,
          onTextChanged: _onTypingChanged,
          replyToName: _repliedMessage?.senderUsername,
          onCancelReply: _cancelReply,
        ),
      ],
    );
  }

  void _voteInPoll(Message msg, String option) {
    try {
      final poll = jsonDecode(msg.content) as Map<String, dynamic>;
      final votes = poll['votes'] as Map<String, dynamic>;
      final userId = context.read<AuthProvider>().user?.id ?? '';

      for (final key in votes.keys) {
        final voters = (votes[key] as List<dynamic>).cast<String>();
        voters.remove(userId);
        votes[key] = voters;
      }

      final voters = (votes[option] as List<dynamic>).cast<String>();
      voters.add(userId);
      votes[option] = voters;
      poll['votes'] = votes;

      context.read<ChatProvider>().editMessage(msg.id, jsonEncode(poll));
    } catch (_) {}
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
