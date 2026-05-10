import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_config.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _displayNameCtl;
  late TextEditingController _usernameCtl;
  late TextEditingController _bioCtl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _displayNameCtl = TextEditingController(text: user?.displayName ?? '');
    _usernameCtl = TextEditingController(text: user?.username ?? '');
    _bioCtl = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _displayNameCtl.dispose();
    _usernameCtl.dispose();
    _bioCtl.dispose();
    super.dispose();
  }

  int get _remainingChanges {
    final auth = context.read<AuthProvider>();
    return 2 - (auth.user?.usernameChanges ?? 0);
  }

  bool get _isOnCooldown {
    final changedAt = context.read<AuthProvider>().user?.usernameChangedAt;
    if (changedAt == null) return false;
    return DateTime.now().difference(changedAt) < const Duration(days: 14);
  }

  String? _cooldownText() {
    final changedAt = context.read<AuthProvider>().user?.usernameChangedAt;
    if (changedAt == null) return null;
    final nextChange = changedAt.add(const Duration(days: 14));
    final remaining = nextChange.difference(DateTime.now());
    if (remaining.isNegative) return null;
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    return 'Can change again in $days days $hours hours';
  }

  Future<void> _save() async {
    final displayName = _displayNameCtl.text.trim();
    final username = _usernameCtl.text.trim();
    final bio = _bioCtl.text.trim();
    if (displayName.isEmpty) return;

    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final result = await auth.updateProfile(
      displayName: displayName,
      username: username != auth.user?.username ? username : null,
      bio: bio.isNotEmpty ? bio : '',
    );
    setState(() => _isLoading = false);

    if (!mounted) return;
    if (result['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'] as String)),
      );
    } else if (result['remaining_changes'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Profile updated (${result['remaining_changes']} username changes remaining)',
          ),
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return;

    setState(() => _isLoading = true);

    try {
      final client = HttpClient();
      try {
        final req = await client.putUrl(
          Uri.parse('${ApiConfig.authBaseUrl}/users/avatar'),
        );
        req.headers.set('Authorization', 'Bearer ${ApiConfig.token}');

        final bytes = await picked.readAsBytes();
        final boundary = 'boundary${DateTime.now().millisecondsSinceEpoch}';
        req.headers.set(
          'Content-Type',
          'multipart/form-data; boundary=$boundary',
        );

        final body = utf8.encode(
              '--$boundary\r\n'
              'Content-Disposition: form-data; name="avatar"; filename="avatar.jpg"\r\n'
              'Content-Type: image/jpeg\r\n\r\n',
            ) +
            bytes +
            utf8.encode('\r\n--$boundary--\r\n');

        req.contentLength = body.length;
        req.add(body);
        final resp = await req.close();
        final responseBody = await resp.transform(utf8.decoder).join();

        if (resp.statusCode == 200) {
          final data = jsonDecode(responseBody) as Map<String, dynamic>;
          final avatarUrl = data['avatar_url'] as String;
          final auth = context.read<AuthProvider>();
          await auth.updateProfile(avatarUrl: avatarUrl);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Avatar updated')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to upload avatar')),
            );
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundImage: user?.avatarUrl.isNotEmpty == true
                      ? NetworkImage(user!.avatarUrl)
                      : null,
                  child: user?.avatarUrl.isNotEmpty != true
                      ? Icon(Icons.person, size: 48, color: Colors.grey[400])
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: _pickAndUploadAvatar,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _displayNameCtl,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameCtl,
              decoration: InputDecoration(
                labelText: 'Username',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.alternate_email),
                helperText: _remainingChanges > 0 && !_isOnCooldown
                    ? '$_remainingChanges changes remaining'
                    : _cooldownText() ?? 'No changes remaining',
                helperMaxLines: 2,
              ),
              maxLength: 30,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bioCtl,
              decoration: const InputDecoration(
                labelText: 'Bio',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.info),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              maxLength: 500,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
            if (_isOnCooldown && _remainingChanges > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _cooldownText() ?? '',
                  style: TextStyle(color: Colors.orange[700], fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
