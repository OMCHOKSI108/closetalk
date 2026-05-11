import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/broadcast_provider.dart';
import '../../providers/contact_provider.dart';

class BroadcastListScreen extends StatefulWidget {
  const BroadcastListScreen({super.key});

  @override
  State<BroadcastListScreen> createState() => _BroadcastListScreenState();
}

class _BroadcastListScreenState extends State<BroadcastListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BroadcastProvider>().loadBroadcasts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bp = context.watch<BroadcastProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Broadcast Lists')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context),
        child: const Icon(Icons.add),
      ),
      body: bp.isLoading
          ? const Center(child: CircularProgressIndicator())
          : bp.broadcasts.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.campaign, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No broadcast lists',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => bp.loadBroadcasts(),
                  child: ListView.builder(
                    itemCount: bp.broadcasts.length,
                    itemBuilder: (_, i) {
                      final b = bp.broadcasts[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          title: Text(b.name),
                          subtitle: const Text('Tap to send'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showSendDialog(context, b),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameController = TextEditingController();
    final searchController = TextEditingController();
    final selectedIds = <String>{};
    final selectedNames = <String>[];
    final contacts = context.read<ContactProvider>().contacts;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('New Broadcast List'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'List Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search contacts...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                if (selectedNames.isNotEmpty)
                  Wrap(
                    spacing: 4,
                    children: selectedNames
                        .map((n) => Chip(
                              label: Text(n, style: const TextStyle(fontSize: 12)),
                              onDeleted: () => setDialogState(() {
                                selectedNames.remove(n);
                              }),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: contacts
                        .where((c) => c.displayName
                            .toLowerCase()
                            .contains(searchController.text.toLowerCase()))
                        .map((c) => CheckboxListTile(
                              title: Text(c.displayName),
                              subtitle: Text('@${c.username}'),
                              value: selectedIds.contains(c.id),
                              onChanged: (v) => setDialogState(() {
                                if (v == true) {
                                  selectedIds.add(c.id);
                                  selectedNames.add(c.displayName);
                                } else {
                                  selectedIds.remove(c.id);
                                  selectedNames.remove(c.displayName);
                                }
                              }),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty || selectedIds.isEmpty) return;
                context
                    .read<BroadcastProvider>()
                    .createBroadcast(name, selectedIds.toList());
                Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSendDialog(BuildContext context, dynamic broadcast) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Send to ${broadcast.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Type your message...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              context
                  .read<BroadcastProvider>()
                  .sendBroadcast(broadcast.id, text);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Broadcast sent!')),
              );
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
