import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/admin_provider.dart';

class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().loadAuditLog();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ap = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Audit Log')),
      body: ap.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ap.auditLog.isEmpty
              ? const Center(child: Text('No audit entries'))
              : RefreshIndicator(
                  onRefresh: () => ap.loadAuditLog(),
                  child: ListView.builder(
                    itemCount: ap.auditLog.length,
                    itemBuilder: (_, i) {
                      final e = ap.auditLog[i];
                      final time = DateTime.tryParse(e.createdAt) ??
                          DateTime.now();
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: _actionColor(e.action),
                            child: Text(
                              e.action.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                            ),
                          ),
                          title: Text(e.action,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Admin: ${e.adminId.substring(0, 8)}...'),
                              Text(
                                  'Target: ${e.targetType} ${e.targetId.isNotEmpty ? e.targetId.substring(0, 8) : ''}'),
                              if (e.details != '{}')
                                Text('Details: ${e.details}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              Text(DateFormat('MM/dd HH:mm').format(time),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500])),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'delete':
      case 'ban':
      case 'disable':
        return Colors.red;
      case 'update':
      case 'modify':
        return Colors.orange;
      case 'create':
      case 'approve':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }
}
