import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/group_provider.dart';
import '../../services/group_service.dart';
import '../../services/api_config.dart';
import '../chat/group_create_screen.dart';
import '../chat/group_discover_screen.dart';
import '../chat/chat_detail_screen.dart';

class GroupListScreen extends StatefulWidget {
  const GroupListScreen({super.key});

  @override
  State<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends State<GroupListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<GroupProvider>().fetchGroups();
    });
  }

  Future<void> _refresh() async {
    await context.read<GroupProvider>().fetchGroups();
  }

  @override
  Widget build(BuildContext context) {
    final groupService = GroupService(
      baseUrl: ApiConfig.authBaseUrl,
      getToken: () => ApiConfig.token ?? '',
    );

    return Scaffold(
      body: Consumer<GroupProvider>(
        builder: (_, gp, _) {
          if (gp.isLoading && gp.groups.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (gp.groups.isEmpty) {
            return const Center(child: Text('No groups yet'));
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: gp.groups.length,
              itemBuilder: (_, i) {
                final g = gp.groups[i];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        g.name.isNotEmpty ? g.name[0].toUpperCase() : '?',
                      ),
                    ),
                    title: Text(g.name),
                    subtitle: Text('${g.memberCount} members'),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (g.isMuted)
                          const Icon(Icons.notifications_off, size: 18),
                        Chip(label: Text(g.role)),
                      ],
                    ),
                    onTap: () {
                      final chatId = g.conversationId ?? g.id;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatDetailScreen(
                            chatId: chatId,
                            chatTitle: g.name,
                            groupId: g.id,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'discoverGroupsFab',
            tooltip: 'Discover public groups',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GroupDiscoverScreen(),
                ),
              );
              _refresh();
            },
            child: const Icon(Icons.explore),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'createGroupFab',
            onPressed: () async {
              final created = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupCreateScreen(
                    groupService: groupService,
                  ),
                ),
              );
              if (created == true) _refresh();
            },
            child: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
