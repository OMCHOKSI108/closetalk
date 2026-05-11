import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/contact_provider.dart';
import '../../services/api_config.dart';

class ContactDiscoveryScreen extends StatefulWidget {
  const ContactDiscoveryScreen({super.key});

  @override
  State<ContactDiscoveryScreen> createState() => _ContactDiscoveryScreenState();
}

class _ContactDiscoveryScreenState extends State<ContactDiscoveryScreen> {
  bool _isSearching = false;
  List<Map<String, dynamic>> _matches = [];
  String? _error;

  Future<void> _discover() async {
    setState(() {
      _isSearching = true;
      _error = null;
    });

    final client = HttpClient();
    try {
      final req = await client.postUrl(
        Uri.parse('${ApiConfig.authBaseUrl}/contacts/discover'),
      );
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
      req.write(jsonEncode({'hashes': _generateDummyHashes()}));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();

      if (resp.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        setState(() {
          _matches = (data['matches'] as List<dynamic>?)
                  ?.cast<Map<String, dynamic>>() ??
              [];
        });
      } else {
        setState(() => _error = 'Discovery failed');
      }
    } catch (e) {
      setState(() => _error = 'Network error: $e');
    } finally {
      client.close();
    }

    setState(() => _isSearching = false);
  }

  List<String> _generateDummyHashes() {
    final hashes = <String>[];
    final rng = Random();
    for (int i = 0; i < 10; i++) {
      final bytes = List.generate(32, (_) => rng.nextInt(256));
      hashes.add(base64Encode(bytes));
    }
    return hashes;
  }


  @override
  Widget build(BuildContext context) {
    final cp = context.watch<ContactProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Find Contacts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.contacts, size: 48, color: Colors.brown),
                  const SizedBox(height: 12),
                  const Text(
                    'Discover which of your contacts use CloseTalk',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your contacts are never shared with our server. Only hashed phone numbers are sent.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isSearching ? null : _discover,
                    icon: _isSearching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.search),
                    label: Text(_isSearching ? 'Searching...' : 'Find Contacts'),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_matches.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Found ${_matches.length} contacts',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._matches.map((m) => ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.brown[100],
                    child: Text(
                      ((m['display_name'] as String?)?.isNotEmpty == true
                              ? m['display_name'] as String
                              : '?')
                          .substring(0, 1)
                          .toUpperCase(),
                    ),
                  ),
                  title: Text(m['display_name'] as String? ?? ''),
                  subtitle: Text('@${m['username'] as String? ?? ''}'),
                  trailing: TextButton(
                    onPressed: () {
                      cp.sendContactRequest(m['user_id'] as String);
                    },
                    child: const Text('Add'),
                  ),
                )),
          ],
          const SizedBox(height: 32),
          Card(
            child: ListTile(
              leading: const Icon(Icons.contacts),
              title: const Text('Contact Requests'),
              subtitle: Text('${cp.pendingRequests.length} pending'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showRequests(context, cp),
            ),
          ),
        ],
      ),
    );
  }

  void _showRequests(BuildContext context, ContactProvider cp) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Contact Requests',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (cp.pendingRequests.isEmpty && cp.sentRequests.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No pending requests'),
              ),
            if (cp.pendingRequests.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Incoming',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
              ),
              ...cp.pendingRequests.map((c) => ListTile(
                    title: Text(c.displayName),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () => cp.acceptContactRequest(c.id),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () => cp.rejectContactRequest(c.id),
                        ),
                      ],
                    ),
                  )),
            ],
            if (cp.sentRequests.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Sent',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
              ),
              ...cp.sentRequests.map((c) => ListTile(
                    title: Text(c.displayName),
                    subtitle: const Text('Pending'),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
