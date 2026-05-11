import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';
import '../home_screen.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _notificationsGranted = false;
  bool _storageGranted = false;
  bool _locationGranted = false;
  bool _isDone = false;

  Future<void> _requestNotifications() async {
    final granted = await NotificationService().requestPermission();
    if (mounted) setState(() => _notificationsGranted = granted);
  }

  Future<void> _requestStorage() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (mounted) setState(() => _storageGranted = permission.hasAccess);
  }

  Future<void> _requestLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final granted = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    if (mounted) setState(() => _locationGranted = granted);
  }

  Future<void> _finish() async {
    setState(() => _isDone = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_granted', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Icon(Icons.security, size: 72, color: Colors.blue[400]),
              const SizedBox(height: 16),
              const Text(
                'Almost done!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Grant a few permissions to get the most out of CloseTalk.',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              _PermissionTile(
                icon: Icons.notifications,
                title: 'Notifications',
                subtitle: 'Get notified of new messages',
                granted: _notificationsGranted,
                onRequest: _requestNotifications,
              ),
              const SizedBox(height: 12),
              _PermissionTile(
                icon: Icons.photo_library,
                title: 'Storage',
                subtitle: 'Send photos and media',
                granted: _storageGranted,
                onRequest: _requestStorage,
              ),
              const SizedBox(height: 12),
              _PermissionTile(
                icon: Icons.location_on_outlined,
                title: 'Location',
                subtitle: 'Share your current place in chats',
                granted: _locationGranted,
                onRequest: _requestLocation,
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isDone ? null : _finish,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Continue', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onRequest;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: granted ? Colors.green : Colors.grey),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: granted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : TextButton(
                onPressed: onRequest,
                child: const Text('Grant'),
              ),
      ),
    );
  }
}
