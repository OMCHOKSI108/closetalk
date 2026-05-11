import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/contact_provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';
import '../settings/edit_profile_screen.dart';
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
    final cp = context.read<ContactProvider>();
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
    if (!mounted) return;
    if (confirmed != true) return;
    await cp.rejectContactRequest(widget.userId);
    if (!mounted) return;
    setState(() => _contactStatus = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend removed')),
    );
  }

  Future<void> _blockUser() async {
    final cp = context.read<ContactProvider>();
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
    if (!mounted) return;
    if (confirmed != true) return;
    await cp.blockUser(widget.userId);
    if (!mounted) return;
    setState(() => _contactStatus = 'blocked');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User blocked')),
    );
  }

  Future<void> _reportUser() async {
    final cp = context.read<ContactProvider>();
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
    if (!mounted) return;
    if (reason == null || reason.isEmpty) return;
    await cp.reportUser(widget.userId, reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User reported')),
    );
  }

  Future<void> _sendMessage() async {
    final cp = context.read<ContactProvider>();
    final result = await cp.createDirectConversation(widget.userId);
    if (!mounted) return;
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not start chat')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          chatId: result.conv!.chatId,
          chatTitle: widget.displayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwnProfile = widget.userId ==
        context.read<AuthProvider>().user?.id;

    final authUser = context.watch<AuthProvider>().user;
    final displayName = isOwnProfile
        ? authUser?.displayName ?? widget.displayName
        : widget.displayName;
    final username =
        isOwnProfile ? authUser?.username ?? widget.username : widget.username;
    final avatarUrl =
        isOwnProfile ? authUser?.avatarUrl ?? widget.avatarUrl : widget.avatarUrl;
    final bio = (_bio != null && _bio!.trim().isNotEmpty)
        ? _bio!.trim()
        : isOwnProfile && (authUser?.bio.trim().isNotEmpty ?? false)
            ? authUser!.bio.trim()
            : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(isOwnProfile ? 'Profile' : displayName),
        actions: [
          if (isOwnProfile)
            IconButton(
              tooltip: 'Edit Profile',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              ),
            ),
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
          : LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 110),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 134,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.warmGradient,
                          boxShadow: [AppColors.glow(color: AppColors.orange)],
                        ),
                        child: UserAvatar(
                          imageUrl: avatarUrl,
                          name: displayName,
                          radius: 54,
                          isOnline: _isOnline,
                        ),
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
                    displayName,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@$username',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHigh.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Text(
                      bio.isEmpty ? 'No bio added yet.' : bio,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: bio.isEmpty
                                ? AppColors.textMuted
                                : AppColors.textPrimary,
                          ),
                    ),
                  ),
                  if (isOwnProfile) ...[
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EditProfileScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Edit Profile'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
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
                    if (_contactStatus == 'rejected')
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Friend request was rejected',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                          _buildActionButton(
                            icon: Icons.refresh,
                            label: 'Send Again',
                            onPressed: _sendRequest,
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
