import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../../services/api_config.dart';

class ModerationScreen extends StatefulWidget {
  const ModerationScreen({super.key});

  @override
  State<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends State<ModerationScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/moderation/queue'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final messages = (data['messages'] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        if (mounted) setState(() => _items = messages);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _review(String messageId, String action) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/moderation/$messageId/review'),
        headers: ApiConfig.headers,
        body: jsonEncode({'action': action}),
      );
      setState(() => _items.removeWhere((m) => m['id'] == messageId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(action == 'approve' ? 'Approved' : 'Rejected')),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moderation Queue')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No flagged messages'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final m = _items[i];
                      final time = DateFormat('MM/dd HH:mm').format(
                        DateTime.parse(m['created_at'] as String),
                      );
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          title: Text(
                            m['content'] as String? ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'Chat: ${(m['chat_id'] as String).substring(0, 8)}...  $time',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600]),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle,
                                    color: Colors.green),
                                onPressed: () =>
                                    _review(m['id'] as String, 'approve'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.cancel,
                                    color: Colors.red),
                                onPressed: () =>
                                    _review(m['id'] as String, 'reject'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
