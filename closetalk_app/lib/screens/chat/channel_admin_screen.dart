import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/channel_provider.dart';
import '../../widgets/user_avatar.dart';

class ChannelAdminScreen extends StatefulWidget {
  final dynamic channel;

  const ChannelAdminScreen({super.key, required this.channel});

  @override
  State<ChannelAdminScreen> createState() => _ChannelAdminScreenState();
}

class _ChannelAdminScreenState extends State<ChannelAdminScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChannelProvider>().loadSubscribers(widget.channel.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<ChannelProvider>();

    return Scaffold(
      appBar: AppBar(title: Text('Manage ${widget.channel.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Channel Info',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _infoRow('Name', widget.channel.name),
                  _infoRow('Description', widget.channel.description ?? 'None'),
                  _infoRow(
                      'Type', widget.channel.isPublic ? 'Public' : 'Private'),
                  _infoRow(
                      'Subscribers', '${widget.channel.subscriberCount}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Subscribers (${cp.subscribers.length})',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (cp.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (cp.subscribers.isEmpty)
            const Text('No subscribers')
          else
            ...cp.subscribers.map((s) => ListTile(
                  leading: UserAvatar(
                    imageUrl: s.avatarUrl,
                    name: s.displayName,
                    radius: 20,
                  ),
                  title: Text(s.displayName),
                  subtitle: Text('@${s.username}  ·  ${s.role}'),
                )),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.grey[600])),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
