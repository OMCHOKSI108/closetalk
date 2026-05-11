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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  static const List<Widget> _screens = [
    ChatListScreen(),
    GroupListScreen(),
    PhotosScreen(),
  ];

  static const List<String> _titles = ['CloseTalk', 'Groups', 'Photos'];

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
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ContactRequestsScreen(),
                    ),
                  );
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
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.group), label: 'Groups'),
          NavigationDestination(icon: Icon(Icons.photo_library), label: 'Photos'),
        ],
      ),
    );
  }
}
