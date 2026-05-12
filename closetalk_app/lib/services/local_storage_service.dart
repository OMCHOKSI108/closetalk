import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

class LocalStorageService {
  static const String _messagesPrefix = 'messages_';
  static const String _imageCachePrefix = 'img_';

  static Future<void> cacheMessages(String chatId, List<Message> messages) async {
    if (messages.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _messagesPrefix + chatId;
    final existing = prefs.getStringList(key) ?? [];
    final encoded = messages.map((m) => jsonEncode(m.toJson())).toList();
    final merged = _deduplicate(existing + encoded);
    final trimmed = merged.length > 200 ? merged.sublist(0, 200) : merged;
    await prefs.setStringList(key, trimmed);
  }

  static Future<List<Message>> getCachedMessages(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _messagesPrefix + chatId;
    final raw = prefs.getStringList(key) ?? [];
    return raw.map((s) {
      try {
        return Message.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<Message>().toList();
  }

  static Future<void> clearChatCache(String chatId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_messagesPrefix + chatId);
  }

  static Future<void> cacheImageUrl(String messageId, String localPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_imageCachePrefix + messageId, localPath);
  }

  static Future<String?> getCachedImagePath(String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_imageCachePrefix + messageId);
  }

  static List<String> _deduplicate(List<String> items) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in items.reversed) {
      try {
        final id = jsonDecode(item)['id'] as String?;
        if (id != null && seen.add(id)) result.insert(0, item);
      } catch (_) {
        result.insert(0, item);
      }
    }
    return result;
  }
}
