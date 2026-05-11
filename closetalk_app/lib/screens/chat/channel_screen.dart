import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/message_service.dart';
import '../../services/api_config.dart';
import 'channel_admin_screen.dart';

class ChannelScreen extends StatefulWidget {
  final dynamic channel;

  const ChannelScreen({super.key, required this.channel});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  final _messages = <Map<String, dynamic>>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final msgService = context.read<MessageService>();
      final result = await msgService.getMessages(
        chatId: widget.channel.id as String,
      );
      final msgs = (result['messages'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      if (mounted) {
        setState(() {
          _messages.addAll(msgs);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channel.name as String? ?? 'Channel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (_) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.channel.name as String? ?? '',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(widget.channel.description as String? ??
                            'No description'),
                        const SizedBox(height: 8),
                        Text(
                            '${widget.channel.subscriberCount} subscribers'),
                        const SizedBox(height: 16),
                        if (widget.channel.myRole == 'admin')
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChannelAdminScreen(
                                      channel: widget.channel),
                                ),
                              );
                            },
                            child: const Text('Manage Channel'),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? const Center(child: Text('No messages yet'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final time = DateTime.tryParse(
                              m['created_at'] as String? ?? '') ??
                          DateTime.now();
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.brown[100],
                          child: Text(
                            ((m['sender_username'] as String?)
                                            ?.isNotEmpty ==
                                        true
                                    ? m['sender_username'] as String
                                    : '?')
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        title: Text(m['sender_username'] as String? ?? ''),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m['content'] as String? ?? ''),
                            Text(
                              DateFormat('MM/dd HH:mm').format(time),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
