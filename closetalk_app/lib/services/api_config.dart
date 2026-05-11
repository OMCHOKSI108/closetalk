class ApiConfig {
  // Production: CloudFront → ALB routes by path to auth-service / message-service.
  // Local dev: flip _useLocal to true (auth-service:8081, message-service:8082 on host).
  static const bool _useLocal = false;

  static const String _prodHttp = 'https://d34etjxuah5cvp.cloudfront.net';
  static const String _prodWs = 'wss://d34etjxuah5cvp.cloudfront.net';

  static const String baseUrl = _useLocal ? 'http://10.0.2.2:8082' : _prodHttp;
  static const String authBaseUrl =
      _useLocal ? 'http://10.0.2.2:8081' : _prodHttp;
  static const String wsUrl = _useLocal ? 'ws://10.0.2.2:8082' : _prodWs;

  static String? token;

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      };
}
