import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class MediaUploadResult {
  final String? uploadUrl;
  final String? mediaUrl;
  final String? error;

  MediaUploadResult({this.uploadUrl, this.mediaUrl, this.error});

  bool get isSuccess => uploadUrl != null && mediaUrl != null;
}

class MediaService {
  static Future<MediaUploadResult> requestUpload({
    required String fileName,
    String contentType = 'application/octet-stream',
    String folder = 'uploads',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/media/upload'),
        headers: ApiConfig.headers,
        body: jsonEncode({
          'file_name': fileName,
          'content_type': contentType,
          'folder': folder,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return MediaUploadResult(
          uploadUrl: data['upload_url'] as String?,
          mediaUrl: data['media_url'] as String?,
        );
      }
      return MediaUploadResult(error: 'Upload request failed: ${response.statusCode}');
    } catch (e) {
      return MediaUploadResult(error: 'Network error: $e');
    }
  }

  static Future<MediaUploadResult> uploadFile({
    required String filePath,
    required String fileName,
    String contentType = 'application/octet-stream',
    String folder = 'uploads',
  }) async {
    final request = await requestUpload(
      fileName: fileName,
      contentType: contentType,
      folder: folder,
    );
    if (!request.isSuccess || request.uploadUrl == null) {
      return request;
    }

    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();

      final uploadResponse = await http.put(
        Uri.parse(request.uploadUrl!),
        headers: {'Content-Type': contentType},
        body: bytes,
      );

      if (uploadResponse.statusCode == 200) {
        return MediaUploadResult(mediaUrl: request.mediaUrl);
      }
      return MediaUploadResult(error: 'Upload failed: ${uploadResponse.statusCode}');
    } catch (e) {
      return MediaUploadResult(error: 'Upload error: $e');
    }
  }

  static Future<MediaUploadResult> requestAvatarUpload() async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/media/upload-avatar'),
        headers: ApiConfig.headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return MediaUploadResult(
          uploadUrl: data['upload_url'] as String?,
          mediaUrl: data['media_url'] as String?,
        );
      }
      return MediaUploadResult(error: 'Avatar upload request failed: ${response.statusCode}');
    } catch (e) {
      return MediaUploadResult(error: 'Network error: $e');
    }
  }
}
