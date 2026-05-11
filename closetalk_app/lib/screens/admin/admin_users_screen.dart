import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/admin_provider.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().loadUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ap = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search users...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onSubmitted: (q) => ap.loadUsers(query: q.isNotEmpty ? q : null),
            ),
          ),
          Expanded(
            child: ap.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ap.users.isEmpty
                    ? const Center(child: Text('No users found'))
                    : ListView.builder(
                        itemCount: ap.users.length,
                        itemBuilder: (_, i) {
                          final u = ap.users[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: u.isActive
                                    ? Colors.green[100]
                                    : Colors.red[100],
                                child: Icon(
                                  Icons.person,
                                  color: u.isActive
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                              title: Text(u.displayName),
                              subtitle: Text(
                                  '@${u.username}\n${u.email}'),
                              isThreeLine: true,
                              trailing: Switch(
                                value: u.isActive,
                                onChanged: (_) =>
                                    ap.toggleUserDisabled(u.id),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
