import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
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
        title: Text(widget.chatTitle.isEmpty ? 'Chat' : widget.chatTitle),
        actions: [
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
