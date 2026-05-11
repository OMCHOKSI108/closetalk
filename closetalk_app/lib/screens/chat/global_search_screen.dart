import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../../providers/contact_provider.dart';
import '../../providers/group_provider.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  bool _isSearching = false;
  List<SearchResult> _results = [];

  List<String> _allChatIds(BuildContext context) {
    final ids = <String>{};
    for (final c in context.read<ContactProvider>().contacts) {
      final cid = c.conversationId;
      if (cid != null && cid.isNotEmpty) ids.add(cid);
    }
    for (final g in context.read<GroupProvider>().groups) {
      ids.add(g.id);
    }
    return ids.toList();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(trimmed);
    });
  }

  Future<void> _search(String query) async {
    setState(() => _isSearching = true);
    final chat = context.read<ChatProvider>();
    final chatIds = _allChatIds(context);
    final allResults = <SearchResult>[];
    for (final chatId in chatIds) {
      final resp = await chat.searchMessages(chatId, query);
      allResults.addAll(resp.results);
    }
    allResults.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (mounted) {
      setState(() {
        _results = allResults;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          focusNode: _focus,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search all chats...',
            border: InputBorder.none,
            filled: false,
          ),
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
        ),
        actions: [
          if (_ctl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctl.clear();
                setState(() {
                  _results = [];
                  _isSearching = false;
                });
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty && _ctl.text.trim().isNotEmpty) {
      return Center(
        child: Text('No results for "${_ctl.text.trim()}"'),
      );
    }

    if (_results.isEmpty) {
      return const Center(child: Text('Search across all your chats'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final r = _results[i];
        final time = DateFormat('MM/dd HH:mm').format(r.createdAt);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.brown[100],
            child: Text(
              (r.senderName.isNotEmpty ? r.senderName[0] : '?').toUpperCase(),
            ),
          ),
          title: Text(r.senderName.isNotEmpty ? r.senderName : r.senderId),
          subtitle: Text(
            r.snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(time,
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          onTap: () => Navigator.pop(context),
        );
      },
    );
  }
}
