import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/schedule_provider.dart';

class ScheduledMessagesScreen extends StatefulWidget {
  const ScheduledMessagesScreen({super.key});

  @override
  State<ScheduledMessagesScreen> createState() =>
      _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScheduleProvider>().loadScheduled();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<ScheduleProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled Messages')),
      body: sp.isLoading
          ? const Center(child: CircularProgressIndicator())
          : sp.scheduled.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No scheduled messages',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => sp.loadScheduled(),
                  child: ListView.builder(
                    itemCount: sp.scheduled.length,
                    itemBuilder: (_, i) {
                      final m = sp.scheduled[i];
                      final sendTime = DateTime.tryParse(m.sendAt);
                      return Dismissible(
                        key: Key(m.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => sp.cancelScheduled(m.id),
                        child: Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.schedule),
                            title: Text(m.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              sendTime != null
                                  ? 'Scheduled for ${DateFormat.yMd().add_jm().format(sendTime)}'
                                  : m.sendAt,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.cancel,
                                  color: Colors.red),
                              onPressed: () async {
                                await sp.cancelScheduled(m.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Scheduled message cancelled')),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
