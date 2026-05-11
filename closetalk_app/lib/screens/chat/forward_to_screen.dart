import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/contact_provider.dart';

class ForwardToScreen extends StatefulWidget {
  final String messageId;
  final Future<bool> Function(String messageId, List<String> targetChatIds)
      onForward;

  const ForwardToScreen({
    super.key,
    required this.messageId,
    required this.onForward,
  });

  @override
  State<ForwardToScreen> createState() => _ForwardToScreenState();
}

class _ForwardToScreenState extends State<ForwardToScreen> {
  final Set<String> _selected = {};
  bool _isForwarding = false;

  @override
  void initState() {
    super.initState();
    final cp = context.read<ContactProvider>();
    if (cp.contacts.isEmpty) cp.loadContacts();
  }

  Future<void> _forward() async {
    if (_selected.isEmpty || _isForwarding) return;
    setState(() => _isForwarding = true);

    final ok = await widget.onForward(widget.messageId, _selected.toList());

    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message forwarded')),
        );
        Navigator.pop(context);
      } else {
        setState(() => _isForwarding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to forward message')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forward to...'),
      ),
      body: Consumer<ContactProvider>(
        builder: (_, cp, __) {
          if (cp.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final accepted =
              cp.contacts.where((c) => c.conversationId != null).toList();

          if (accepted.isEmpty) {
            return const Center(child: Text('No contacts yet'));
          }

          return ListView.builder(
            itemCount: accepted.length,
            itemBuilder: (_, i) {
              final contact = accepted[i];
              final isSelected = _selected.contains(contact.conversationId);
              return CheckboxListTile(
                value: isSelected,
                secondary: CircleAvatar(
                  backgroundColor: Colors.brown[100],
                  child: Text(
                    (contact.displayName.isNotEmpty
                            ? contact.displayName
                            : contact.username)
                        .substring(0, 1)
                        .toUpperCase(),
                    style: TextStyle(color: Colors.brown[800]),
                  ),
                ),
                title: Text(
                    contact.displayName.isNotEmpty
                        ? contact.displayName
                        : contact.username,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text('@${contact.username}'),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selected.add(contact.conversationId!);
                    } else {
                      _selected.remove(contact.conversationId);
                    }
                  });
                },
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: (_selected.isEmpty || _isForwarding) ? null : _forward,
            icon: _isForwarding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.forward),
            label: Text(
                _isForwarding ? 'Forwarding...' : 'Forward (${_selected.length})'),
          ),
        ),
      ),
    );
  }
}
