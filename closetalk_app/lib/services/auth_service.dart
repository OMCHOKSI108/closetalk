import 'dart:convert';
import 'dart:io';

import '../models/device.dart';

class AuthService {
  final String baseUrl;
  final String Function() getToken;

  AuthService({required this.baseUrl, required this.getToken});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${getToken()}',
      };

  Future<LinkDeviceResponse> linkDevice({
    required String deviceName,
    required String deviceType,
    required String platform,
    String? devicePubKey,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.postUrl(Uri.parse('$baseUrl/devices/link'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({
        'device_name': deviceName,
        'device_type': deviceType,
        'platform': platform,
        'device_pub_key': devicePubKey ?? '',
      }));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 201) {
        return LinkDeviceResponse.fromJson(
            jsonDecode(body) as Map<String, dynamic>);
      }
      throw HttpException('Failed to link device: ${resp.statusCode}');
    } finally {
      client.close();
    }
  }

  Future<List<Device>> listDevices() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/devices'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        return (data['devices'] as List<dynamic>)
            .map((d) => Device.fromJson(d as Map<String, dynamic>))
            .toList();
      }
      throw HttpException('Failed to list devices: ${resp.statusCode}');
    } finally {
      client.close();
    }
  }

  Future<void> revokeDevice(String deviceId) async {
    final client = HttpClient();
    try {
      final req =
          await client.postUrl(Uri.parse('$baseUrl/devices/revoke'));
      _headers.forEach((k, v) => req.headers.set(k, v));
      req.write(jsonEncode({'device_id': deviceId}));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('Failed to revoke device: ${resp.statusCode}');
      }
    } finally {
      client.close();
    }
  }
}
