import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/contact_provider.dart';
import 'providers/group_provider.dart';
import 'providers/bookmark_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/call_provider.dart';
import 'providers/story_provider.dart';
import 'providers/e2ee_provider.dart';
import 'providers/privacy_provider.dart';
import 'providers/broadcast_provider.dart';
import 'providers/channel_provider.dart';
import 'providers/schedule_provider.dart';
import 'providers/admin_provider.dart';
import 'providers/poll_provider.dart';
import 'providers/filter_provider.dart';
import 'services/auth_service.dart';
import 'services/group_service.dart';
import 'services/message_service.dart';
import 'services/notification_service.dart';
import 'services/api_config.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding/permissions_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    _reportFlutterError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    _reportError(error, stack, source: 'platform');
    return true;
  };

  runZonedGuarded(
    () async {
      try {
        await NotificationService().initialize();
      } catch (error, stack) {
        _reportError(error, stack, source: 'notification_init');
      }
      runApp(const CloseTalkApp());
    },
    (error, stack) => _reportError(error, stack, source: 'zone'),
  );
}

void _reportFlutterError(FlutterErrorDetails details) {
  _reportError(
    details.exception,
    details.stack ?? StackTrace.current,
    source: details.context?.toDescription() ?? 'flutter',
  );
}

void _reportError(
  Object error,
  StackTrace stack, {
  required String source,
}) {
  if (!kReleaseMode) {
    debugPrint('[app_error][$source] $error');
    debugPrintStack(stackTrace: stack);
  }
  // Production hook: send this to Crashlytics or Sentry before Play Store launch.
}

class CloseTalkApp extends StatelessWidget {
  const CloseTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => ContactProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => BookmarkProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CallProvider()),
        ChangeNotifierProvider(create: (_) => StoryProvider()),
        ChangeNotifierProvider(create: (_) => E2EEProvider()),
        ChangeNotifierProvider(create: (_) => PrivacyProvider()),
        ChangeNotifierProvider(create: (_) => BroadcastProvider()),
        ChangeNotifierProvider(create: (_) => ChannelProvider()),
        ChangeNotifierProvider(create: (_) => ScheduleProvider()),
        ChangeNotifierProvider(create: (_) => AdminProvider()),
        ChangeNotifierProvider(create: (_) => PollProvider()),
        ChangeNotifierProvider(create: (_) => FilterProvider()),
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
      child: Consumer2<AuthProvider, ThemeProvider>(
        builder: (context, auth, theme, _) {
          return MaterialApp(
            title: 'CloseTalk',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: theme.mode,
            home: _buildHome(auth, theme),
          );
        },
      ),
    );
  }

  Widget _buildHome(AuthProvider auth, ThemeProvider theme) {
    if (auth.status == AuthStatus.uninitialized) {
      theme.load();
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
