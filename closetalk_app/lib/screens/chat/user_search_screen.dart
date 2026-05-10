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
  final _searchCtl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    final contactProvider = context.read<ContactProvider>();
    final users = await contactProvider.searchUsers(query.trim());

    if (mounted) {
      setState(() {
        _results = users;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactProvider = context.watch<ContactProvider>();
    final searchHistory = contactProvider.searchHistory;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Friend'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                hintText: 'Search by username or display name...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _searchCtl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtl.clear();
                          _search('');
                        },
                      )
                    : null,
              ),
              onChanged: (v) {
                setState(() {});
                _search(v);
              },
              textInputAction: TextInputAction.search,
            ),
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else if (_hasSearched && _results.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No users found'),
            )
          else if (_hasSearched)
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final user = _results[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      backgroundImage: (user['avatar_url'] != null &&
                              (user['avatar_url'] as String).isNotEmpty)
                          ? NetworkImage(user['avatar_url'] as String)
                          : null,
                      child: (user['avatar_url'] == null ||
                              (user['avatar_url'] as String).isEmpty)
                          ? Text(
                              (user['display_name'] as String? ?? '?')[0]
                                  .toUpperCase(),
                              style: TextStyle(color: Colors.blue[800]),
                            )
                          : null,
                    ),
                    title: Text(user['display_name'] as String? ?? ''),
                    subtitle: Text('@${user['username'] as String? ?? ''}'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserProfileScreen(
                            userId: user['id'] as String,
                            username: user['username'] as String? ?? '',
                            displayName:
                                user['display_name'] as String? ?? '',
                            avatarUrl: user['avatar_url'] as String? ?? '',
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            )
          else if (searchHistory.isNotEmpty)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Recent Searches',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        TextButton(
                          onPressed: () =>
                              contactProvider.clearSearchHistory(),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: searchHistory.length,
                      itemBuilder: (_, i) {
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(searchHistory[i]),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () =>
                                contactProvider.removeFromSearchHistory(
                                    searchHistory[i]),
                          ),
                          onTap: () {
                            _searchCtl.text = searchHistory[i];
                            _search(searchHistory[i]);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          else
            const Expanded(
              child: Center(
                child: Text('Search for users to add as friends'),
              ),
            ),
        ],
      ),
    );
  }
}
