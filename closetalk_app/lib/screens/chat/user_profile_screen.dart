import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/contact_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/user_avatar.dart';
import 'chat_detail_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String displayName;
  final String avatarUrl;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.username,
    required this.displayName,
    this.avatarUrl = '',
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  String? _contactStatus;
  bool _isOnline = false;
  String? _bio;
  DateTime? _lastSeen;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final contactProvider = context.read<ContactProvider>();
    final profile = await contactProvider.getUserProfile(widget.userId);

    if (mounted) {
      setState(() {
        _contactStatus = profile?.contactStatus;
        _isOnline = profile?.isOnline ?? false;
        _bio = profile?.bio;
        _lastSeen = profile?.lastSeen;
        _isLoading = false;
      });
    }
  }

  String _lastSeenText() {
    if (_isOnline) return 'Online';
    if (_lastSeen == null) return '';
    final diff = DateTime.now().difference(_lastSeen!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _sendRequest() async {
    final cp = context.read<ContactProvider>();
    final result = await cp.sendContactRequest(widget.userId);
    if (mounted) {
      if (result['success'] == true) {
        setState(() => _contactStatus = 'sent');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request sent')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] as String? ?? 'Failed to send'),
          ),
        );
      }
    }
  }

  Future<void> _acceptRequest() async {
    final cp = context.read<ContactProvider>();
    final result = await cp.acceptContactRequest(widget.userId);
    if (mounted) {
      if (result['message'] != null || result['conversation_id'] != null) {
        setState(() => _contactStatus = 'accepted');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend request accepted')),
        );
      }
    }
  }

  Future<void> _rejectRequest() async {
    final cp = context.read<ContactProvider>();
    final result = await cp.rejectContactRequest(widget.userId);
    if (mounted) {
      if (result['success'] == true) {
        setState(() => _contactStatus = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request rejected')),
        );
      }
    }
  }

  Future<void> _removeFriend() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Friend'),
        content: Text('Remove ${widget.displayName} as a friend?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final cp = context.read<ContactProvider>();
      await cp.rejectContactRequest(widget.userId);
      if (mounted) {
        setState(() => _contactStatus = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend removed')),
        );
      }
    }
  }

  Future<void> _blockUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block User'),
        content: Text('Block ${widget.displayName}? They will not be able to contact you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final cp = context.read<ContactProvider>();
      await cp.blockUser(widget.userId);
      if (mounted) {
        setState(() => _contactStatus = 'blocked');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked')),
        );
      }
    }
  }

  Future<void> _reportUser() async {
    final reasonCtl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report User'),
        content: TextField(
          controller: reasonCtl,
          decoration: const InputDecoration(
            hintText: 'Why are you reporting this user?',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, reasonCtl.text.trim()),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    if (reason != null && reason.isNotEmpty) {
      final cp = context.read<ContactProvider>();
      await cp.reportUser(widget.userId, reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User reported')),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    final cp = context.read<ContactProvider>();
    final conv = await cp.createDirectConversation(widget.userId);
    if (mounted && conv != null) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            chatId: conv.chatId,
            chatTitle: widget.displayName,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwnProfile = widget.userId ==
        context.read<AuthProvider>().user?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.displayName),
        actions: [
          if (!isOwnProfile)
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'block':
                    _blockUser();
                  case 'report':
                    _reportUser();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block, size: 20),
                      SizedBox(width: 8),
                      Text('Block'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.flag, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Report'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  UserAvatar(
                    imageUrl: widget.avatarUrl,
                    name: widget.displayName,
                    radius: 48,
                    isOnline: _isOnline,
                  ),
                  const SizedBox(height: 8),
                  if (_isOnline || _lastSeen != null)
                    Text(
                      _lastSeenText(),
                      style: TextStyle(
                        color: _isOnline ? Colors.green : Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    widget.displayName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${widget.username}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  if (_bio != null && _bio!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      _bio!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (!isOwnProfile) ...[
                    if (_contactStatus == null)
                      _buildActionButton(
                        icon: Icons.person_add,
                        label: 'Add Friend',
                        onPressed: _sendRequest,
                      ),
                    if (_contactStatus == 'pending')
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildActionButton(
                            icon: Icons.check,
                            label: 'Accept',
                            onPressed: _acceptRequest,
                          ),
                          const SizedBox(width: 16),
                          _buildActionButton(
                            icon: Icons.close,
                            label: 'Reject',
                            onPressed: _rejectRequest,
                            isDestructive: true,
                          ),
                        ],
                      ),
                    if (_contactStatus == 'sent')
                      Column(
                        children: [
                          _buildActionButton(
                            icon: Icons.hourglass_empty,
                            label: 'Request Sent',
                            onPressed: null,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _rejectRequest,
                            child: const Text('Cancel Request'),
                          ),
                        ],
                      ),
                    if (_contactStatus == 'accepted')
                      Column(
                        children: [
                          _buildActionButton(
                            icon: Icons.message,
                            label: 'Send Message',
                            onPressed: _sendMessage,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _removeFriend,
                            child: Text(
                              'Remove Friend',
                              style: TextStyle(color: Colors.red[400]),
                            ),
                          ),
                        ],
                      ),
                    if (_contactStatus == 'blocked')
                      Text(
                        'User blocked',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
    bool isDestructive = false,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor:
            isDestructive ? Colors.red[50] : null,
        foregroundColor:
            isDestructive ? Colors.red : null,
        padding: const EdgeInsets.symmetric(
            horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
