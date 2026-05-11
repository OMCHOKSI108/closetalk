import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/contact_provider.dart';
import 'user_profile_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  static const Duration _debounce = Duration(milliseconds: 350);

  final _searchCtl = TextEditingController();
  Timer? _debounceTimer;
  int _requestSeq = 0;

  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  String? _errorMessage;
  String _activeQuery = '';

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounceTimer?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _errorMessage = null;
        _activeQuery = '';
        _isSearching = false;
      });
      return;
    }
    _debounceTimer = Timer(_debounce, () => _search(trimmed));
  }

  Future<void> _search(String query) async {
    final mySeq = ++_requestSeq;
    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _errorMessage = null;
      _activeQuery = query;
    });

    final contactProvider = context.read<ContactProvider>();
    final result = await contactProvider.searchUsersDetailed(query);

    if (!mounted || mySeq != _requestSeq) return;
    setState(() {
      _isSearching = false;
      _results = result.users;
      _errorMessage = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final contactProvider = context.watch<ContactProvider>();
    final searchHistory = contactProvider.searchHistory;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Friend')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by username or display name…',
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
              onSubmitted: (v) {
                _debounceTimer?.cancel();
                final trimmed = v.trim();
                if (trimmed.isNotEmpty) _search(trimmed);
              },
            ),
          ),
          Expanded(child: _buildResults(searchHistory, contactProvider)),
        ],
      ),
    );
  }

  Widget _buildResults(
      List<String> searchHistory, ContactProvider contactProvider) {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.red),
            const SizedBox(height: 12),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _search(_activeQuery),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_hasSearched && _results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('No users match "$_activeQuery"'),
        ),
      );
    }

    if (_hasSearched) {
      return ListView.builder(
        itemCount: _results.length,
        itemBuilder: (_, i) => _userTile(_results[i]),
      );
    }

    if (searchHistory.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Searches',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                TextButton(
                  onPressed: contactProvider.clearSearchHistory,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: searchHistory.length,
              itemBuilder: (_, i) {
                final term = searchHistory[i];
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(term),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        contactProvider.removeFromSearchHistory(term),
                  ),
                  onTap: () {
                    _searchCtl.text = term;
                    _debounceTimer?.cancel();
                    _search(term);
                  },
                );
              },
            ),
          ),
        ],
      );
    }

    return const Center(
      child: Text('Search for users to add as friends'),
    );
  }

  Widget _userTile(Map<String, dynamic> user) {
    final avatarUrl = user['avatar_url'] as String? ?? '';
    final displayName = user['display_name'] as String? ?? '';
    final username = user['username'] as String? ?? '';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue[100],
        backgroundImage:
            avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
        child: avatarUrl.isEmpty
            ? Text(
                (displayName.isNotEmpty ? displayName[0] : '?').toUpperCase(),
                style: TextStyle(color: Colors.blue[800]),
              )
            : null,
      ),
      title: Text(displayName),
      subtitle: Text('@$username'),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserProfileScreen(
              userId: user['id'] as String,
              username: username,
              displayName: displayName,
              avatarUrl: avatarUrl,
            ),
          ),
        );
      },
    );
  }
}
