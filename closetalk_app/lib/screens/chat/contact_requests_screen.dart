import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/contact.dart';
import '../../providers/contact_provider.dart';

class ContactRequestsScreen extends StatefulWidget {
  const ContactRequestsScreen({super.key});

  @override
  State<ContactRequestsScreen> createState() => _ContactRequestsScreenState();
}

class _ContactRequestsScreenState extends State<ContactRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final Set<String> _working = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ContactProvider>().loadContacts();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _accept(Contact contact) async {
    await _runAction(
      contact,
      () => context.read<ContactProvider>().acceptContactRequest(contact.contactId),
      'Request accepted',
    );
  }

  Future<void> _reject(Contact contact) async {
    await _runAction(
      contact,
      () => context.read<ContactProvider>().rejectContactRequest(contact.contactId),
      'Request rejected',
    );
  }

  Future<void> _runAction(
    Contact contact,
    Future<Map<String, dynamic>> Function() action,
    String successMessage,
  ) async {
    if (_working.contains(contact.contactId)) return;
    setState(() => _working.add(contact.contactId));
    final result = await action();
    if (!mounted) return;
    setState(() => _working.remove(contact.contactId));

    final error = result['error']?.toString();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? successMessage)),
    );
    if (error == null && successMessage == 'Request accepted') {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Requests'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Incoming'),
            Tab(text: 'Sent'),
          ],
        ),
      ),
      body: Consumer<ContactProvider>(
        builder: (_, cp, _) {
          if (cp.isLoading &&
              cp.pendingRequests.isEmpty &&
              cp.sentRequests.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: cp.loadContacts,
            child: TabBarView(
              controller: _tabController,
              children: [
                _RequestList(
                  contacts: cp.pendingRequests,
                  emptyText: 'No incoming requests',
                  working: _working,
                  onAccept: _accept,
                  onReject: _reject,
                ),
                _RequestList(
                  contacts: cp.sentRequests,
                  emptyText: 'No sent requests',
                  working: _working,
                  sentOnly: true,
                  onAccept: _accept,
                  onReject: _reject,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  final List<Contact> contacts;
  final String emptyText;
  final Set<String> working;
  final bool sentOnly;
  final ValueChanged<Contact> onAccept;
  final ValueChanged<Contact> onReject;

  const _RequestList({
    required this.contacts,
    required this.emptyText,
    required this.working,
    required this.onAccept,
    required this.onReject,
    this.sentOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.28),
          Icon(Icons.person_add_alt_1_outlined,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Center(child: Text(emptyText)),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: contacts.length,
      separatorBuilder: (_, separatorIndex) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final contact = contacts[index];
        final busy = working.contains(contact.contactId);
        final displayName = contact.displayName.trim().isNotEmpty
            ? contact.displayName.trim()
            : 'Unknown user';
        final username = contact.username.trim().isNotEmpty
            ? contact.username.trim()
            : contact.contactId.substring(
                0,
                contact.contactId.length < 8 ? contact.contactId.length : 8,
              );
        final initial = displayName.isNotEmpty
            ? displayName.substring(0, 1).toUpperCase()
            : '?';

        return ListTile(
          leading: CircleAvatar(child: Text(initial)),
          title: Text(displayName),
          subtitle: Text('@$username'),
          trailing: sentOnly
              ? const Chip(label: Text('Pending'))
              : busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Accept',
                          icon: const Icon(Icons.check_circle_outline),
                          color: Colors.green,
                          onPressed: () => onAccept(contact),
                        ),
                        IconButton(
                          tooltip: 'Reject',
                          icon: const Icon(Icons.cancel_outlined),
                          color: Colors.red,
                          onPressed: () => onReject(contact),
                        ),
                      ],
                    ),
        );
      },
    );
  }
}
