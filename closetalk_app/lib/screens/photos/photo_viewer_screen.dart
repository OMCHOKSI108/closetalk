import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
import '../../services/media_service.dart';
import '../chat/chat_picker_screen.dart';

class PhotoViewerScreen extends StatefulWidget {
  final AssetEntity asset;

  const PhotoViewerScreen({super.key, required this.asset});

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  bool _sending = false;

  Future<void> _sendToChat() async {
    final picked = await Navigator.push<PickedChat?>(
      context,
      MaterialPageRoute(builder: (_) => const ChatPickerScreen()),
    );
    if (picked == null || !mounted) return;

    setState(() => _sending = true);
    try {
      final bytes = await widget.asset.thumbnailDataWithSize(
        const ThumbnailSize.square(1280),
      );
      if (bytes == null) throw 'Could not read image bytes';

      final dir = await getTemporaryDirectory();
      final tempFile = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(bytes);

      final result = await MediaService.uploadFile(
        filePath: tempFile.path,
        fileName: tempFile.uri.pathSegments.last,
        contentType: 'image/jpeg',
        folder: 'uploads/images',
      );

      if (result.mediaUrl == null) {
        throw result.error ?? 'Upload failed';
      }

      if (!mounted) return;
      final chat = context.read<ChatProvider>();
      final sent = await chat.sendMessage(
        chatId: picked.chatId,
        content: '📷 Photo',
        contentType: 'image',
        mediaUrl: result.mediaUrl,
      );

      await tempFile.delete();

      if (mounted) {
        if (sent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sent to ${picked.title}')),
          );
        }
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Send to chat',
            onPressed: _sending ? null : _sendToChat,
            icon: _sending
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
      body: Center(
        child: FutureBuilder<Uint8List?>(
          future: widget.asset.originBytes,
          builder: (_, snap) {
            if (!snap.hasData || snap.data == null) {
              return const CircularProgressIndicator();
            }
            return InteractiveViewer(
              child: Image.memory(snap.data!, fit: BoxFit.contain),
            );
          },
        ),
      ),
    );
  }
}
