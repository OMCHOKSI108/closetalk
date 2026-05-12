class ApiConfig {
  // Set to false to use production CloudFront URL.
  // For Android emulator: 10.0.2.2 maps to host machine's localhost.
  // For real device: replace 10.0.2.2 with your machine's LAN IP (e.g. 192.168.x.x).
  static const bool useLocal = true;
  static const String localHost = '10.0.2.2';

  static const String _prodHttp = 'https://d34etjxuah5cvp.cloudfront.net';
  static const String _prodWs = 'wss://d34etjxuah5cvp.cloudfront.net';

  static String get baseUrl =>
      useLocal ? 'http://$localHost:8082' : _prodHttp;
  static String get authBaseUrl =>
      useLocal ? 'http://$localHost:8081' : _prodHttp;
  static String get wsUrl =>
      useLocal ? 'ws://$localHost:8082' : _prodWs;

  static String? token;

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      };
}
