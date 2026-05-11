import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';
import '../services/e2ee_service.dart';

class E2EEProvider extends ChangeNotifier {

  final E2EEService _e2ee = E2EEService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _keyPrivateKey = 'e2ee_private_key';
  static const _keyPublicKey = 'e2ee_public_key';
  static const _keyEnabled = 'e2ee_enabled';

  SimpleKeyPair? _keyPair;
  bool _isInitialized = false;
  bool _enabled = false;

  final Map<String, SecretKey> _sessionKeys = {};

  bool get isInitialized => _isInitialized;
  bool get enabled => _enabled;

  Future<void> init() async {
    if (_isInitialized) return;

    final enabledStr = await _storage.read(key: _keyEnabled);
    if (enabledStr == 'true') {
      final privKeyB64 = await _storage.read(key: _keyPrivateKey);
      final pubKeyB64 = await _storage.read(key: _keyPublicKey);
      if (privKeyB64 != null && pubKeyB64 != null) {
        final privBytes = base64Decode(privKeyB64);
        final pubBytes = base64Decode(pubKeyB64);
        _keyPair = SimpleKeyPairData(
          privBytes,
          publicKey: SimplePublicKey(pubBytes, type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );
        _enabled = true;
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  Future<bool> enable() async {
    if (_enabled) return true;

    _keyPair = await _e2ee.generateKeyPair();
    final publicKey = await _e2ee.extractPublicKey(_keyPair!);
    final pubBytes = publicKey.bytes;
    final privBytes = await _keyPair!.extract();

    await _storage.write(key: _keyPrivateKey, value: base64Encode(privBytes.bytes));
    await _storage.write(key: _keyPublicKey, value: base64Encode(pubBytes));
    await _storage.write(key: _keyEnabled, value: 'true');

    final ok = await _uploadPublicKey(base64Encode(pubBytes));
    if (!ok) return false;

    _enabled = true;
    notifyListeners();
    return true;
  }

  Future<void> disable() async {
    _enabled = false;
    _sessionKeys.clear();
    await _storage.write(key: _keyEnabled, value: 'false');
    notifyListeners();
  }

  Future<bool> _uploadPublicKey(String b64PublicKey) async {
    try {
      final client = http.Client();
      try {
        final response = await client.post(
          Uri.parse('${ApiConfig.authBaseUrl}/e2ee/keys'),
          headers: ApiConfig.headers,
          body: jsonEncode({'public_key': b64PublicKey}),
        );
        return response.statusCode == 200 || response.statusCode == 201;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<String?> _fetchPublicKey(String userId) async {
    try {
      final client = http.Client();
      try {
        final response = await client.get(
          Uri.parse('${ApiConfig.authBaseUrl}/e2ee/keys/$userId'),
          headers: ApiConfig.headers,
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return data['public_key'] as String?;
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }

  Future<SecretKey?> getOrCreateSessionKey(String userId) async {
    if (_sessionKeys.containsKey(userId)) {
      return _sessionKeys[userId];
    }
    if (_keyPair == null) return null;

    final pubKeyB64 = await _fetchPublicKey(userId);
    if (pubKeyB64 == null) return null;

    final remotePublicKey = SimplePublicKey(
      base64Decode(pubKeyB64),
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _e2ee.computeSharedSecret(
      myKeyPair: _keyPair!,
      remotePublicKey: remotePublicKey,
    );
    final sessionKey = await _e2ee.deriveSessionKey(sharedSecret);
    _sessionKeys[userId] = sessionKey;
    return sessionKey;
  }

  bool hasSessionKey(String key) => _sessionKeys.containsKey(key);

  Future<String?> encrypt({required String plaintext, required String chatId}) async {
    if (!_enabled || _keyPair == null) return null;
    final sessionKey = _sessionKeys[chatId];
    if (sessionKey == null) return null;
    return _e2ee.encryptMessage(plaintext: plaintext, sessionKey: sessionKey);
  }

  Future<String?> decrypt({required String encryptedBase64, required String chatId}) async {
    if (!_enabled) return null;
    final sessionKey = _sessionKeys[chatId];
    if (sessionKey == null) return null;
    return _e2ee.decryptMessage(encryptedBase64: encryptedBase64, sessionKey: sessionKey);
  }
}
