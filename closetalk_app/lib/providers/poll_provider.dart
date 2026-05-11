import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';

class PollProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<String?> createPoll({
    required String chatId,
    required String question,
    required List<String> options,
    bool multipleChoice = false,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/polls'),
        headers: ApiConfig.headers,
        body: jsonEncode({
          'chat_id': chatId,
          'question': question,
          'options': options,
          'multiple_choice': multipleChoice,
        }),
      );
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['id'] as String;
      }
      _error = 'Failed to create poll';
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
    return null;
  }

  Future<bool> votePoll(String pollId, int optionIndex) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.authBaseUrl}/polls/$pollId/vote'),
        headers: ApiConfig.headers,
        body: jsonEncode({'option_index': optionIndex}),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getPollResults(String pollId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.authBaseUrl}/polls/$pollId/results'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
