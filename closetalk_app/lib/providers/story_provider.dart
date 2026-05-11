import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/story.dart';
import '../services/api_config.dart';

class StoryProvider extends ChangeNotifier {
  List<Story> _stories = [];
  bool _isLoading = false;
  String? _error;

  List<Story> get stories => _stories;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Map<String, List<Story>> get groupedByUser {
    final map = <String, List<Story>>{};
    for (final s in _stories) {
      map.putIfAbsent(s.userId, () => []);
      map[s.userId]!.add(s);
    }
    return map;
  }

  Future<void> loadStories() async {
    setStateLoading();
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/stories'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (data['stories'] as List<dynamic>)
            .map((e) => Story.fromJson(e as Map<String, dynamic>))
            .toList();
        _stories = list;
      } else {
        _error = 'Failed to load stories';
      }
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<bool> createStory({
    required String content,
    String? mediaUrl,
    String mediaType = 'text',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/stories'),
        headers: ApiConfig.headers,
        body: jsonEncode({
          'content': content,
          ?(mediaUrl == null ? null : 'media_url'): mediaUrl!,
          'media_type': mediaType,
        }),
      );
      if (response.statusCode == 201) {
        await loadStories();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> deleteStory(String storyId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.authBaseUrl}/stories/$storyId'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        _stories.removeWhere((s) => s.id == storyId);
        notifyListeners();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> viewStory(String storyId) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/stories/$storyId/view'),
        headers: ApiConfig.headers,
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getStoryViews(String storyId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/stories/$storyId/views'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {'views': <dynamic>[]};
  }

  Future<bool> replyToStory(String storyId, String content) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/stories/$storyId/reply'),
        headers: ApiConfig.headers,
        body: jsonEncode({'content': content}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> muteUser(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/stories/mute/$userId'),
        headers: ApiConfig.headers,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unmuteUser(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/stories/unmute/$userId'),
        headers: ApiConfig.headers,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void setStateLoading() {
    _isLoading = true;
    _error = null;
    notifyListeners();
  }
}
