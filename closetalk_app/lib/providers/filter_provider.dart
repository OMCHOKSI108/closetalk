import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FilterProvider extends ChangeNotifier {
  List<String> _blockedWords = [];
  bool _isLoaded = false;

  List<String> get blockedWords => List.unmodifiable(_blockedWords);

  Future<void> load() async {
    if (_isLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _blockedWords = prefs.getStringList('blocked_words') ?? [];
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> addWord(String word) async {
    final trimmed = word.trim().toLowerCase();
    if (trimmed.isEmpty || _blockedWords.contains(trimmed)) return;
    _blockedWords.add(trimmed);
    await _save();
    notifyListeners();
  }

  Future<void> removeWord(String word) async {
    _blockedWords.remove(word);
    await _save();
    notifyListeners();
  }

  bool isFiltered(String content) {
    final lower = content.toLowerCase();
    for (final w in _blockedWords) {
      if (lower.contains(w)) return true;
    }
    return false;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blocked_words', _blockedWords);
  }
}
