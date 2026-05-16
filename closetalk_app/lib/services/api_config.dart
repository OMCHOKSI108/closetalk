class ApiConfig {
  // Defaults to production CloudFront. To use a local backend during dev, run:
  //   flutter run --dart-define=USE_LOCAL=true
  // (Android emulator: 10.0.2.2 maps to host's localhost. Real device: use LAN IP.)
  static const bool useLocal = bool.fromEnvironment(
    'USE_LOCAL',
    defaultValue: false,
  );
  static const String localHost = '10.0.2.2';

  static const String _prodHttp = 'https://d34etjxuah5cvp.cloudfront.net';
  static const String _prodWs = 'wss://d34etjxuah5cvp.cloudfront.net';

  static String get baseUrl => useLocal ? 'http://$localHost:8082' : _prodHttp;
  static String get authBaseUrl =>
      useLocal ? 'http://$localHost:8081' : _prodHttp;
  static String get wsUrl => useLocal ? 'ws://$localHost:8082' : _prodWs;

  static String? token;

  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}
