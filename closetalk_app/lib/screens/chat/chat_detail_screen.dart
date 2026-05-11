import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/message.dart';
import '../../models/group.dart';
import '../../models/contact.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/call_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/e2ee_provider.dart';
import '../../providers/contact_provider.dart';
import '../../services/group_service.dart';
import '../../services/api_config.dart';
import '../../services/media_service.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/chat_input_bar.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/voice_recorder_sheet.dart';
import '../../widgets/sticker_picker_sheet.dart';
import '../../widgets/location_picker.dart';
import 'user_profile_screen.dart';
import '../../widgets/poll_creator_sheet.dart';
import '../../providers/poll_provider.dart';
import 'forward_to_screen.dart';
import 'group_info_screen.dart';
import 'call_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final String? groupId;
  final String? peerUserId;

  const ChatDetailScreen({
    super.key,
    required this.chatId,
    this.chatTitle = '',
    this.groupId,
    this.peerUserId,
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
  bool _e2eeEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadMuted();
    final chat = context.read<ChatProvider>();
    final e2ee = context.read<E2EEProvider>();
    chat.setE2EE(e2ee);
    final userId = context.read<AuthProvider>().user?.id;
    chat.currentUserId = userId;
    chat.fetchMessages(widget.chatId, refresh: true);
    chat.connectWebSocket(widget.chatId);
    chat.markChatRead(widget.chatId);
    _initE2EE();

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
    if (!mounted) return;
    setState(() => _isLoadingMore = true);
    final chatProvider = context.read<ChatProvider>();
    await chatProvider.fetchMessages(widget.chatId);
    if (!mounted) return;
    setState(() => _isLoadingMore = false);
  }

  Future<void> _initE2EE() async {
    try {
      final e2ee = context.read<E2EEProvider>();
      final contacts = context.read<ContactProvider>().contacts;
      await e2ee.init();
      if (e2ee.enabled) {
        String? peerId = widget.peerUserId;
        if (peerId == null && widget.groupId == null) {
          for (final c in contacts) {
            if (c.conversationId == widget.chatId) {
              peerId = c.contactId;
              break;
            }
          }
        }
        if (peerId != null && !e2ee.hasSessionKey(widget.chatId)) {
          await e2ee.getOrCreateSessionKey(peerId);
        }
        if (!mounted) return;
        setState(() =>
            _e2eeEnabled = e2ee.enabled && e2ee.hasSessionKey(widget.chatId));
      }
    } catch (_) {}
  }

  Future<void> _enableE2EE() async {
    try {
      final e2ee = context.read<E2EEProvider>();
      final contacts = context.read<ContactProvider>().contacts;
      await e2ee.init();
      final ok = await e2ee.enable();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to enable E2EE')),
        );
        return;
      }
      String? peerId = widget.peerUserId;
      if (peerId == null && widget.groupId == null) {
        for (final c in contacts) {
          if (c.conversationId == widget.chatId) {
            peerId = c.contactId;
            break;
          }
        }
      }
      if (peerId != null) {
        final key = await e2ee.getOrCreateSessionKey(peerId);
        if (key != null) {
          if (!mounted) return;
          setState(() => _e2eeEnabled = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End-to-end encryption enabled')),
          );
          return;
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact has not enabled E2EE yet')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not enable encryption')),
      );
    }
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
    if (!mounted) return;
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
    if (index >= 0 && _scrollController.hasClients) {
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
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      final fileName = file.name.isNotEmpty ? file.name : 'image.jpg';
      final ext = fileName.contains('.') ? fileName.split('.').last : 'jpg';
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';

      final result = await MediaService.uploadFile(
        filePath: file.path,
        fileName: 'image_${DateTime.now().millisecondsSinceEpoch}.$ext',
        contentType: mime,
        folder: 'uploads/images',
      );

      if (!mounted) return;

      if (result.isSuccess && result.mediaUrl != null) {
        context.read<ChatProvider>().sendMessage(
              chatId: widget.chatId,
              content: '[Image]',
              contentType: 'image',
              mediaUrl: result.mediaUrl,
            );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Upload failed: ${result.error ?? "unknown error"}')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open photo picker')),
      );
    }
  }

  void _createPoll() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => PollCreatorSheet(
        onSend: (jsonContent) async {
          try {
            Navigator.pop(context);
            final poll = jsonDecode(jsonContent) as Map<String, dynamic>;
            final question = poll['question'] as String;
            final options = (poll['options'] as List).cast<String>();

            final chatProvider = context.read<ChatProvider>();
            final pp = context.read<PollProvider>();
            final pollId = await pp.createPoll(
              chatId: widget.chatId,
              question: question,
              options: options,
            );

            if (!mounted) return;

            chatProvider.sendMessage(
                  chatId: widget.chatId,
                  content: jsonEncode({
                    'poll_id': pollId,
                    'question': question,
                    'options': options,
                  }),
                  contentType: 'poll',
                );
          } catch (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not create poll')),
            );
          }
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

  void _openPeerProfile() {
    final contact = _peerContact();
    final peerId = widget.peerUserId ?? contact?.contactId;
    if (peerId == null || peerId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(
          userId: peerId,
          username: contact?.username ?? '',
          displayName: contact?.displayName ?? widget.chatTitle,
          avatarUrl: contact?.avatarUrl ?? '',
        ),
      ),
    );
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
          builder: (_, gp, _) {
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

  Contact? _peerContact() {
    final contacts = context.read<ContactProvider>().contacts;
    for (final contact in contacts) {
      if (contact.conversationId == widget.chatId ||
          contact.contactId == widget.peerUserId) {
        return contact;
      }
    }
    return null;
  }

  PreferredSizeWidget _buildChatAppBar() {
    final scheme = Theme.of(context).colorScheme;
    final contact = _peerContact();
    final title = widget.chatTitle.isNotEmpty
        ? widget.chatTitle
        : contact?.displayName ?? 'Chat';
    final isTyping = context
        .watch<ChatProvider>()
        .typingUsers(widget.chatId)
        .where((uid) => uid != context.read<AuthProvider>().user?.id)
        .isNotEmpty;
    final status = isTyping
        ? 'typing...'
        : contact?.isOnline == true
            ? 'online'
            : widget.groupId != null
                ? 'group chat'
                : 'tap for profile';

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      leadingWidth: 42,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.maybePop(context),
      ),
      title: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.groupId != null ? _openGroupInfo : _openPeerProfile,
        child: Row(
          children: [
            UserAvatar(
              imageUrl: contact?.avatarUrl,
              name: title,
              radius: 18,
              isOnline: contact?.isOnline == true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isTyping ? scheme.primary : scheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.call_outlined),
          tooltip: 'Voice call',
          onPressed: _startVoiceCall,
        ),
        IconButton(
          icon: const Icon(Icons.videocam_outlined),
          tooltip: 'Video call',
          onPressed: _startVideoCall,
        ),
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: _toggleSearch,
          tooltip: 'Search',
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'mute') _toggleMute();
            if (value == 'e2ee') _enableE2EE();
            if (value == 'refresh') {
              context
                  .read<ChatProvider>()
                  .fetchMessages(widget.chatId, refresh: true);
            }
            if (value == 'info') _openGroupInfo();
          },
          itemBuilder: (_) => [
            if (widget.groupId != null)
              const PopupMenuItem(value: 'info', child: Text('Group info')),
            PopupMenuItem(
              value: 'mute',
              child: Text(_isMuted ? 'Unmute chat' : 'Mute chat'),
            ),
            if (widget.groupId == null)
              PopupMenuItem(
                value: 'e2ee',
                child: Text(_e2eeEnabled ? 'E2EE enabled' : 'Enable E2EE'),
              ),
            const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
          ],
        ),
      ],
    );
  }

  void _startVoiceCall() {
    final call = context.read<CallProvider>();
    call.startCall(widget.chatId, widget.chatId, false);
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
  }

  void _startVideoCall() {
    final call = context.read<CallProvider>();
    call.startCall(widget.chatId, widget.chatId, true);
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
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthProvider>().user?.id ?? '';

    return Scaffold(
      appBar: _isSearching ? AppBar(
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
            if (widget.groupId == null)
              IconButton(
                icon: Icon(
                  _e2eeEnabled ? Icons.lock : Icons.lock_open,
                  color: _e2eeEnabled ? Colors.green : Colors.grey,
                ),
                tooltip: _e2eeEnabled ? 'E2EE enabled' : 'Enable E2EE',
                onPressed: _enableE2EE,
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
      ) : _buildChatAppBar(),
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
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
      ),
      child: Column(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (_, chat, _) {
                final messages = chat.getMessages(widget.chatId);
                if (messages.isEmpty) {
                  return _EmptyChatState(title: widget.chatTitle);
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
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
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      color: isHighlighted
                          ? scheme.secondaryContainer.withValues(alpha: 0.55)
                          : Colors.transparent,
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
            builder: (_, chat, _) {
              final typing = chat
                  .typingUsers(widget.chatId)
                  .where((uid) => uid != userId)
                  .toList();
              if (typing.isEmpty) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 8,
                          height: 8,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          typing.length == 1
                              ? 'Typing...'
                              : '${typing.length} people typing...',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          ChatInputBar(
            onSticker: _showStickerPicker,
            onLocation: _shareLocation,
            onPoll: _createPoll,
            onSend: (text) async {
              final ok = await context.read<ChatProvider>().sendMessage(
                    chatId: widget.chatId,
                    content: text,
                    replyToId: _replyToMessageId,
                  );
              _cancelReply();
              _typingDebounce?.cancel();
              context.read<ChatProvider>().sendTyping(widget.chatId, false);
              _scrollToLatest();
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Message failed to send')),
                );
              }
            },
            onSendFormatted: (text) async {
              final ok = await context.read<ChatProvider>().sendMessage(
                    chatId: widget.chatId,
                    content: text,
                    contentType: 'formatted',
                    replyToId: _replyToMessageId,
                  );
              _cancelReply();
              _typingDebounce?.cancel();
              context.read<ChatProvider>().sendTyping(widget.chatId, false);
              _scrollToLatest();
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Message failed to send')),
                );
              }
            },
            onAttach: _pickAndSendImage,
            onRecord: _showVoiceRecorder,
            onTextChanged: _onTypingChanged,
            replyToName: _repliedMessage?.senderUsername,
            onCancelReply: _cancelReply,
          ),
        ],
      ),
    );
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _voteInPoll(Message msg, int optionIndex) {
    try {
      final poll = jsonDecode(msg.content) as Map<String, dynamic>;
      final pollId = poll['poll_id'] as String?;
      if (pollId == null) return;

      context.read<PollProvider>().votePoll(pollId, optionIndex);
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

class _EmptyChatState extends StatelessWidget {
  final String title;

  const _EmptyChatState({required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = title.trim().isEmpty ? 'this chat' : title.trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                Icons.chat_bubble_outline,
                color: scheme.onPrimaryContainer,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Start chatting with $name',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Send a message, voice note, photo, poll, sticker, or location.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
