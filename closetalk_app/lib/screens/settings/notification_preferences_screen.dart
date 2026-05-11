import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _doNotDisturb = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 23, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 8, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _soundEnabled = prefs.getBool('notif_sound') ?? true;
      _vibrationEnabled = prefs.getBool('notif_vibrate') ?? true;
      _doNotDisturb = prefs.getBool('notif_dnd') ?? false;
      final startH = prefs.getInt('quiet_start_hour') ?? 23;
      final startM = prefs.getInt('quiet_start_minute') ?? 0;
      final endH = prefs.getInt('quiet_end_hour') ?? 8;
      final endM = prefs.getInt('quiet_end_minute') ?? 0;
      _quietStart = TimeOfDay(hour: startH, minute: startM);
      _quietEnd = TimeOfDay(hour: endH, minute: endM);
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveQuietHours() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('quiet_start_hour', _quietStart.hour);
    await prefs.setInt('quiet_start_minute', _quietStart.minute);
    await prefs.setInt('quiet_end_hour', _quietEnd.hour);
    await prefs.setInt('quiet_end_minute', _quietEnd.minute);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.volume_up),
            title: const Text('Sound'),
            subtitle: const Text('Play sound for new messages'),
            value: _soundEnabled,
            onChanged: (v) {
              setState(() => _soundEnabled = v);
              _save('notif_sound', v);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibrate'),
            subtitle: const Text('Vibrate on new messages'),
            value: _vibrationEnabled,
            onChanged: (v) {
              setState(() => _vibrationEnabled = v);
              _save('notif_vibrate', v);
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.do_not_disturb),
            title: const Text('Do Not Disturb'),
            subtitle: const Text('Mute notifications during quiet hours'),
            value: _doNotDisturb,
            onChanged: (v) {
              setState(() => _doNotDisturb = v);
              _save('notif_dnd', v);
            },
          ),
          if (_doNotDisturb) ...[
            ListTile(
              leading: const Icon(Icons.bedtime),
              title: const Text('Quiet Hours'),
              subtitle: Text(
                '${_quietStart.format(context)} - ${_quietEnd.format(context)}',
              ),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _quietStart,
                  helpText: 'Select quiet hours start',
                );
                if (picked != null) {
                  final pickedEnd = await showTimePicker(
                    context: context,
                    initialTime: _quietEnd,
                    helpText: 'Select quiet hours end',
                  );
                  if (pickedEnd != null) {
                    setState(() {
                      _quietStart = picked;
                      _quietEnd = pickedEnd;
                    });
                    _saveQuietHours();
                  }
                }
              },
            ),
          ],
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Message Preview'),
            subtitle: const Text('Show message content in notifications'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Configure in system notification settings')),
              );
            },
          ),
        ],
      ),
    );
  }
}
