import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/privacy_provider.dart';
import '../../services/api_config.dart';
import '../auth/login_screen.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrivacyProvider>().loadSettings();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pp = context.watch<PrivacyProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: pp.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection(context, 'Who can see your personal info', [
                  _buildVisibilityTile(
                    context: context,
                    title: 'Last Seen',
                    subtitle: pp.settings.lastSeenVisibility,
                    icon: Icons.visibility,
                    options: const ['everyone', 'contacts', 'nobody'],
                    selected: pp.settings.lastSeenVisibility,
                    onChanged: (v) {
                      pp.updateSettings({'last_seen_visibility': v});
                      setState(() {});
                    },
                  ),
                  _buildVisibilityTile(
                    context: context,
                    title: 'Profile Photo',
                    subtitle: pp.settings.profilePhotoVisibility,
                    icon: Icons.photo_camera,
                    options: const ['everyone', 'contacts', 'nobody'],
                    selected: pp.settings.profilePhotoVisibility,
                    onChanged: (v) {
                      pp.updateSettings({'profile_photo_visibility': v});
                      setState(() {});
                    },
                  ),
                  _buildVisibilityTile(
                    context: context,
                    title: 'Status',
                    subtitle: pp.settings.statusPrivacy,
                    icon: Icons.info,
                    options: const ['contacts', 'close_friends', 'public'],
                    selected: pp.settings.statusPrivacy,
                    onChanged: (v) {
                      pp.updateSettings({'status_privacy': v});
                      setState(() {});
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                _buildSection(context, 'Messaging', [
                  SwitchListTile(
                    secondary: const Icon(Icons.done_all),
                    title: const Text('Read Receipts'),
                    subtitle: const Text(
                        'Let others know when you\'ve read their messages'),
                    value: pp.settings.readReceiptsGlobal,
                    onChanged: (v) {
                      pp.updateSettings({'read_receipts_global': v});
                      setState(() {});
                    },
                  ),
                  _buildVisibilityTile(
                    context: context,
                    title: 'Who can add you to groups',
                    subtitle: pp.settings.groupAddPermission,
                    icon: Icons.group_add,
                    options: const ['everyone', 'contacts', 'contacts_except'],
                    selected: pp.settings.groupAddPermission,
                    onChanged: (v) {
                      pp.updateSettings({'group_add_permission': v});
                      setState(() {});
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                _buildSection(context, 'Security', [
                  ListTile(
                    leading:
                        const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('Delete Account'),
                    subtitle: const Text(
                        'Permanently delete your account and all data'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showDeleteAccountDialog(context),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List<Widget> children) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600])),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildVisibilityTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(_visibilityLabel(subtitle)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showVisibilityPicker(
          context, title, options, selected, onChanged),
    );
  }

  String _visibilityLabel(String key) {
    switch (key) {
      case 'everyone':
        return 'Everyone';
      case 'contacts':
        return 'My Contacts';
      case 'nobody':
        return 'Nobody';
      case 'close_friends':
        return 'Close Friends';
      case 'public':
        return 'Public';
      case 'contacts_except':
        return 'Contacts Except...';
      default:
        return key;
    }
  }

  void _showVisibilityPicker(BuildContext context, String title,
      List<String> options, String selected, ValueChanged<String> onChanged) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...options.map((opt) => ListTile(
                  title: Text(_visibilityLabel(opt)),
                  trailing: opt == selected
                      ? const Icon(Icons.check, color: Colors.brown)
                      : null,
                  onTap: () {
                    onChanged(opt);
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
            'This will permanently delete your account, all messages, and all data. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _confirmDeleteAccount(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Type "DELETE" to confirm permanent account deletion.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'DELETE',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () async {
              if (controller.text.trim() != 'DELETE') return;
              final client = HttpClient();
              try {
                final req = await client.deleteUrl(
                  Uri.parse('${ApiConfig.authBaseUrl}/auth/account'),
                );
                req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');
                await req.close();
              } finally {
                client.close();
              }
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const LoginScreen()),
                  (_) => false,
                );
              }
            },
            child: const Text('Permanently Delete'),
          ),
        ],
      ),
    );
  }
}
