import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/group_provider.dart';

class GroupDiscoverScreen extends StatefulWidget {
  const GroupDiscoverScreen({super.key});

  @override
  State<GroupDiscoverScreen> createState() => _GroupDiscoverScreenState();
}

class _GroupDiscoverScreenState extends State<GroupDiscoverScreen> {
  static const Duration _debounce = Duration(milliseconds: 350);

  final _searchCtl = TextEditingController();
  Timer? _debounceTimer;
  int _seq = 0;
  bool _loading = true;
  String? _joiningId;
  List<DiscoverGroup> _groups = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load('');
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final mySeq = ++_seq;
    setState(() => _loading = true);
    final groups =
        await context.read<GroupProvider>().discoverGroups(query: query);
    if (!mounted || mySeq != _seq) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  void _onChanged(String value) {
    setState(() {});
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () => _load(value));
  }

  Future<void> _join(DiscoverGroup g) async {
    setState(() => _joiningId = g.id);
    final result = await context.read<GroupProvider>().joinPublicGroup(g.id);
    if (!mounted) return;
    setState(() => _joiningId = null);
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined ${g.name}')),
      );
      _load(_searchCtl.text);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not join')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover Groups')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                hintText: 'Search public groups…',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _searchCtl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtl.clear();
                          _onChanged('');
                        },
                      )
                    : null,
              ),
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _searchCtl.text.isEmpty
                ? 'No public groups yet — be the first to create one!'
                : 'No public groups match "${_searchCtl.text}"',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(_searchCtl.text),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: _groups.length,
        itemBuilder: (_, i) => _tile(_groups[i]),
      ),
    );
  }

  Widget _tile(DiscoverGroup g) {
    final isJoining = _joiningId == g.id;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage:
              g.avatarUrl.isNotEmpty ? NetworkImage(g.avatarUrl) : null,
          child: g.avatarUrl.isEmpty
              ? Text(g.name.isNotEmpty ? g.name[0].toUpperCase() : '?')
              : null,
        ),
        title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (g.description.isNotEmpty)
              Text(g.description,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              '${g.memberCount} member${g.memberCount == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        trailing: g.isMember
            ? const Chip(label: Text('Joined'))
            : SizedBox(
                width: 88,
                child: FilledButton(
                  onPressed: isJoining ? null : () => _join(g),
                  child: isJoining
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Join'),
                ),
              ),
      ),
    );
  }
}
