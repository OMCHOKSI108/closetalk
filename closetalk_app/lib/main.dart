import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/group_provider.dart';
import 'providers/bookmark_provider.dart';
import 'services/auth_service.dart';
import 'services/group_service.dart';
import 'services/message_service.dart';
import 'services/notification_service.dart';
import 'services/api_config.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding/permissions_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NotificationService().initialize();
  runApp(const CloseTalkApp());
}

class CloseTalkApp extends StatelessWidget {
  const CloseTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => BookmarkProvider()),
        Provider(
          create: (_) => AuthService(
            baseUrl: ApiConfig.authBaseUrl,
            getToken: () => ApiConfig.token ?? '',
          ),
        ),
        Provider(
          create: (_) => GroupService(
            baseUrl: ApiConfig.authBaseUrl,
            getToken: () => ApiConfig.token ?? '',
          ),
        ),
        Provider(
          create: (_) => MessageService(
            baseUrl: ApiConfig.baseUrl,
            getToken: () => ApiConfig.token ?? '',
          ),
        ),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return MaterialApp(
            title: 'CloseTalk',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
              useMaterial3: true,
            ),
            home: _buildHome(auth),
          );
        },
      ),
    );
  }

  Widget _buildHome(AuthProvider auth) {
    if (auth.status == AuthStatus.uninitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (auth.status == AuthStatus.authenticated) {
      return FutureBuilder<bool>(
        future: _hasGrantedPermissions(),
        builder: (_, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.data == true
              ? const HomeScreen()
              : const PermissionsScreen();
        },
      );
    }

    return const LoginScreen();
  }

  Future<bool> _hasGrantedPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('permissions_granted') ?? false;
  }
}
