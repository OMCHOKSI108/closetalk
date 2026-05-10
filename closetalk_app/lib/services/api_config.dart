class ApiConfig {
  static const String baseUrl = 'http://10.0.2.2:8082';
  static const String authBaseUrl = 'http://10.0.2.2:8081';
  static const String wsUrl = 'ws://10.0.2.2:8082';

  static String? _token;

  static String? get token => _token;
  static set token(String? t) => _token = t;

  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };
}
