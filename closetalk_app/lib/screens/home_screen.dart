import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/contact_provider.dart';
import '../services/auth_service.dart';
import '../widgets/user_avatar.dart';
import 'auth/login_screen.dart';
import 'chat/chat_list_screen.dart';
import 'chat/contact_requests_screen.dart';
import 'chat/global_search_screen.dart';
import 'chat/group_list_screen.dart';
import 'chat/join_group_screen.dart';
import 'chat/user_profile_screen.dart';
import 'photos/photos_screen.dart';
import 'settings/bookmark_list_screen.dart';
import 'settings/device_management_screen.dart';
import 'settings/edit_profile_screen.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const List<String> _titles = [
    'CloseTalk',
    'Explore',
    'Groups',
    'Calls',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ContactProvider>().loadContacts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final authService = context.read<AuthService>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search all chats',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const GlobalSearchScreen()),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              currentAccountPicture: GestureDetector(
                onTap: () {
                  if (user == null) return;
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileScreen(
                        userId: user.id,
                        username: user.username,
                        displayName: user.displayName,
                        avatarUrl: user.avatarUrl,
                      ),
                    ),
                  );
                },
                child: UserAvatar(
                  imageUrl: user?.avatarUrl,
                  name: user?.displayName ?? '?',
                  radius: 30,
                ),
              ),
              accountName: Text(
                user?.displayName ?? 'User',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              accountEmail: Text('@${user?.username ?? ''}'),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('My Profile'),
              onTap: () {
                if (user == null) return;
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserProfileScreen(
                      userId: user.id,
                      username: user.username,
                      displayName: user.displayName,
                      avatarUrl: user.avatarUrl,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Profile'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EditProfileScreen(),
                  ),
                );
              },
            ),
            Consumer<ContactProvider>(
              builder: (_, cp, _) => ListTile(
                leading: const Icon(Icons.person_add_alt_1_outlined),
                title: const Text('Requests'),
                trailing: cp.pendingRequests.isEmpty
                    ? null
                    : Badge.count(count: cp.pendingRequests.length),
                onTap: () async {
                  final contacts = context.read<ContactProvider>();
                  Navigator.pop(context);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ContactRequestsScreen(),
                    ),
                  );
                  if (!mounted) return;
                  contacts.loadContacts();
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: const Text('Bookmarks'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BookmarkListScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: const Text('Linked Devices'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeviceManagementScreen(
                      authService: authService,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Join Group'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const JoinGroupScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Logout',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                await auth.logout();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginScreen(),
                    ),
                    (_) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
      extendBody: true,
      body: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: _buildCurrentScreen(user),
      ),
      bottomNavigationBar: _GlassNavBar(
        currentIndex: _currentIndex,
        onChanged: (i) => setState(() => _currentIndex = i),
      ),
    );
  }

  Widget _buildCurrentScreen(dynamic user) {
    switch (_currentIndex) {
      case 0:
        return const ChatListScreen();
      case 1:
        return const PhotosScreen();
      case 2:
        return const GroupListScreen();
      case 3:
        return const _CallsPlaceholder();
      case 4:
        if (user == null) return const Center(child: Text('Profile unavailable'));
        return UserProfileScreen(
          userId: user.id,
          username: user.username,
          displayName: user.displayName,
          avatarUrl: user.avatarUrl,
        );
      default:
        return const ChatListScreen();
    }
  }
}

class _GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const _GlassNavBar({
    required this.currentIndex,
    required this.onChanged,
  });

  static const _items = [
    (Icons.chat_bubble_rounded, 'Chats'),
    (Icons.explore_rounded, 'Explore'),
    (Icons.groups_rounded, 'Groups'),
    (Icons.call_rounded, 'Calls'),
    (Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              boxShadow: [AppColors.glow(opacity: 0.22)],
            ),
            child: Row(
              children: List.generate(_items.length, (index) {
                final selected = index == currentIndex;
                final item = _items[index];
                return Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => onChanged(index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: selected ? AppColors.primaryGradient : null,
                        color: selected
                            ? null
                            : Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: selected
                            ? [AppColors.glow(opacity: 0.30)]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.$1,
                            size: 21,
                            color: selected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: selected
                                      ? AppColors.textPrimary
                                      : AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallsPlaceholder extends StatelessWidget {
  const _CallsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [AppColors.glow(opacity: 0.16)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.call_rounded, size: 42, color: AppColors.coral),
            const SizedBox(height: 12),
            Text(
              'Calls',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Voice and video call history will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
