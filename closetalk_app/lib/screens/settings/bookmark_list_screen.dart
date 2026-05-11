import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/bookmark_provider.dart';
import '../chat/chat_detail_screen.dart';

class BookmarkListScreen extends StatefulWidget {
  const BookmarkListScreen({super.key});

  @override
  State<BookmarkListScreen> createState() => _BookmarkListScreenState();
}

class _BookmarkListScreenState extends State<BookmarkListScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bp = context.read<BookmarkProvider>();
      if (bp.bookmarks.isEmpty) bp.fetchBookmarks(refresh: true);
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200) {
        context.read<BookmarkProvider>().fetchBookmarks();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: Consumer<BookmarkProvider>(
        builder: (_, bp, _) {
          if (bp.isLoading && bp.bookmarks.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (bp.bookmarks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bookmark_border, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No bookmarks yet'),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => bp.fetchBookmarks(refresh: true),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: bp.bookmarks.length + (bp.hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i == bp.bookmarks.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final b = bp.bookmarks[i];
                final time =
                    DateFormat('MM/dd HH:mm').format(b.createdAt);
                return Dismissible(
                  key: ValueKey(b.messageId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    child:
                        const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => bp.removeBookmark(b.messageId),
                  child: ListTile(
                    leading: const Icon(Icons.bookmark),
                    title: Text(
                      b.preview.isNotEmpty ? b.preview : '(no preview)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Chat: ${b.chatId.substring(0, 8)}... · $time',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(
                          chatId: b.chatId,
                          chatTitle:
                              'Chat ${b.chatId.substring(0, 8)}...',
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
