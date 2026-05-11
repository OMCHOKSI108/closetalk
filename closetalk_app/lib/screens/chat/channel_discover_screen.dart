import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/channel_provider.dart';
import '../../widgets/user_avatar.dart';
import 'channel_screen.dart';
import 'channel_admin_screen.dart';

class ChannelDiscoverScreen extends StatefulWidget {
  const ChannelDiscoverScreen({super.key});

  @override
  State<ChannelDiscoverScreen> createState() => _ChannelDiscoverScreenState();
}

class _ChannelDiscoverScreenState extends State<ChannelDiscoverScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChannelProvider>().discoverChannels();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<ChannelProvider>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Channels'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'My Channels'),
              Tab(text: 'Discover'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showCreateDialog(context),
          child: const Icon(Icons.add),
        ),
        body: TabBarView(
          children: [
            _MyChannelsTab(cp: cp),
            _DiscoverTab(cp: cp),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isPublic = true;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Create Channel'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Channel Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Public'),
                subtitle: Text(isPublic ? 'Anyone can find and join' : 'Only invited users'),
                value: isPublic,
                onChanged: (v) => setDialogState(() => isPublic = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                context
                    .read<ChannelProvider>()
                    .createChannel(name, description: descController.text.trim(), isPublic: isPublic);
                Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyChannelsTab extends StatelessWidget {
  final ChannelProvider cp;
  const _MyChannelsTab({required this.cp});

  @override
  Widget build(BuildContext context) {
    if (cp.isLoading && cp.channels.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cp.channels.isEmpty) {
      return const Center(child: Text('No channels yet'));
    }
    return RefreshIndicator(
      onRefresh: () => cp.loadChannels(),
      child: ListView.builder(
        itemCount: cp.channels.length,
        itemBuilder: (_, i) {
          final ch = cp.channels[i];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: UserAvatar(
                imageUrl: ch.avatarUrl,
                name: ch.name,
                radius: 24,
              ),
              title: Text(ch.name),
              subtitle: Text('${ch.subscriberCount} subscribers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChannelScreen(channel: ch),
                ),
              ),
              onLongPress: ch.myRole == 'admin'
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChannelAdminScreen(channel: ch),
                        ),
                      )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _DiscoverTab extends StatelessWidget {
  final ChannelProvider cp;
  const _DiscoverTab({required this.cp});

  @override
  Widget build(BuildContext context) {
    if (cp.isLoading && cp.discoverable.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cp.discoverable.isEmpty) {
      return const Center(child: Text('No public channels found'));
    }
    return RefreshIndicator(
      onRefresh: () => cp.discoverChannels(),
      child: ListView.builder(
        itemCount: cp.discoverable.length,
        itemBuilder: (_, i) {
          final ch = cp.discoverable[i];
          final isSubscribed = cp.channels.any((c) => c.id == ch.id);
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: UserAvatar(
                imageUrl: ch.avatarUrl,
                name: ch.name,
                radius: 24,
              ),
              title: Text(ch.name),
              subtitle: Text('${ch.subscriberCount} subscribers'),
              trailing: isSubscribed
                  ? OutlinedButton(
                      onPressed: () => cp.unsubscribe(ch.id),
                      child: const Text('Leave'),
                    )
                  : ElevatedButton(
                      onPressed: () => cp.subscribe(ch.id),
                      child: const Text('Join'),
                    ),
            ),
          );
        },
      ),
    );
  }
}
