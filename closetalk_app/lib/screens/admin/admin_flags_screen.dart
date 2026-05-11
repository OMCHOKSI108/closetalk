import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/admin_provider.dart';

class AdminFlagsScreen extends StatefulWidget {
  const AdminFlagsScreen({super.key});

  @override
  State<AdminFlagsScreen> createState() => _AdminFlagsScreenState();
}

class _AdminFlagsScreenState extends State<AdminFlagsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().loadFlags();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ap = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Feature Flags')),
      body: ap.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ap.flags.isEmpty
              ? const Center(child: Text('No feature flags'))
              : RefreshIndicator(
                  onRefresh: () => ap.loadFlags(),
                  child: ListView.builder(
                    itemCount: ap.flags.length,
                    itemBuilder: (_, i) {
                      final f = ap.flags[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(f.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                  ),
                                  Switch(
                                    value: f.enabled,
                                    onChanged: (v) {
                                      ap.updateFlag(f.id, enabled: v);
                                      setState(() {});
                                    },
                                  ),
                                ],
                              ),
                              if (f.description.isNotEmpty)
                                Text(f.description,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600])),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('Rollout: ',
                                      style: TextStyle(fontSize: 13)),
                                  Expanded(
                                    child: Slider(
                                      value: f.rolloutPercent.toDouble(),
                                      min: 0,
                                      max: 100,
                                      divisions: 20,
                                      label: '${f.rolloutPercent}%',
                                      onChanged: (v) {
                                        setState(() =>
                                            f.rolloutPercent = v.toInt());
                                      },
                                      onChangeEnd: (v) {
                                        ap.updateFlag(f.id,
                                            rolloutPercent: v.toInt());
                                      },
                                    ),
                                  ),
                                  Text('${f.rolloutPercent}%',
                                      style: const TextStyle(fontSize: 13)),
                                ],
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
