import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';

class Channel {
  final String id;
  final String name;
  final String description;
  final String avatarUrl;
  final bool isPublic;
  final int subscriberCount;
  final String createdBy;
  final String createdAt;
  final String myRole;

  Channel({
    required this.id,
    required this.name,
    this.description = '',
    this.avatarUrl = '',
    required this.isPublic,
    this.subscriberCount = 0,
    required this.createdBy,
    required this.createdAt,
    this.myRole = '',
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      isPublic: json['is_public'] as bool? ?? false,
      subscriberCount: (json['subscriber_count'] as num?)?.toInt() ?? 0,
      createdBy: json['created_by'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      myRole: json['my_role'] as String? ?? '',
    );
  }
}

class ChannelSubscriber {
  final String userId;
  final String role;
  final String displayName;
  final String username;
  final String avatarUrl;
  final String subscribedAt;

  ChannelSubscriber({
    required this.userId,
    required this.role,
    required this.displayName,
    required this.username,
    this.avatarUrl = '',
    required this.subscribedAt,
  });

  factory ChannelSubscriber.fromJson(Map<String, dynamic> json) {
    return ChannelSubscriber(
      userId: json['user_id'] as String? ?? '',
      role: json['role'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      username: json['username'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      subscribedAt: json['subscribed_at'] as String? ?? '',
    );
  }
}

class ChannelProvider extends ChangeNotifier {
  List<Channel> _channels = [];
  List<Channel> _discoverable = [];
  List<ChannelSubscriber> _subscribers = [];
  bool _isLoading = false;
  String? _error;

  List<Channel> get channels => _channels;
  List<Channel> get discoverable => _discoverable;
  List<ChannelSubscriber> get subscribers => _subscribers;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadChannels() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/channels'),
        headers: ApiConfig.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _channels = (data['channels'] as List<dynamic>)
            .map((e) => Channel.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _error = 'Failed to load channels';
      }
    } catch (e) {
      _error = 'Network error: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> discoverChannels() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/channels/discover'),
        headers: ApiConfig.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _discoverable = (data['channels'] as List<dynamic>)
            .map((e) => Channel.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        _error = 'Failed to discover channels';
      }
    } catch (e) {
      _error = 'Network error: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<String?> createChannel(String name, {String description = '', bool isPublic = true}) async {
    _error = null;
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/channels'),
        headers: ApiConfig.headers,
        body: jsonEncode({'name': name, 'description': description, 'is_public': isPublic}),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await loadChannels();
        return data['id'] as String?;
      }
      _error = 'Failed to create channel';
      return null;
    } catch (e) {
      _error = 'Network error: $e';
      return null;
    }
  }

  Future<bool> subscribe(String channelId) async {
    _error = null;
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/channels/$channelId/subscribe'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        await loadChannels();
        return true;
      }
      _error = 'Failed to subscribe';
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      return false;
    }
  }

  Future<bool> unsubscribe(String channelId) async {
    _error = null;
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/channels/$channelId/unsubscribe'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        await loadChannels();
        return true;
      }
      _error = 'Failed to unsubscribe';
      return false;
    } catch (e) {
      _error = 'Network error: $e';
      return false;
    }
  }

  Future<void> loadSubscribers(String channelId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/channels/$channelId/subscribers'),
        headers: ApiConfig.headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _subscribers = (data['subscribers'] as List<dynamic>)
            .map((e) => ChannelSubscriber.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
