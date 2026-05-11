import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/story.dart';
import '../../providers/story_provider.dart';
import '../../widgets/user_avatar.dart';

class StoriesRow extends StatefulWidget {
  const StoriesRow({super.key});

  @override
  State<StoriesRow> createState() => _StoriesRowState();
}

class _StoriesRowState extends State<StoriesRow> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StoryProvider>().loadStories();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sp = context.watch<StoryProvider>();
    final grouped = sp.groupedByUser;

    if (grouped.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 80,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          _StoryCreateButton(),
          ...grouped.entries.map((entry) {
            final userStories = entry.value;
            final first = userStories.first;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => _openViewer(context, entry.key, userStories),
                onLongPress: () => _muteUser(context, entry.key),
                child: Column(
                  children: [
                    UserAvatar(
                      imageUrl: first.avatarUrl,
                      name: first.displayName,
                      radius: 24,
                      hasStory: true,
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 50,
                      child: Text(
                        first.displayName.isNotEmpty
                            ? first.displayName
                            : first.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _muteUser(BuildContext context, String userId) async {
    final sp = context.read<StoryProvider>();
    final muted = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Mute Stories'),
        content: const Text('Stop seeing stories from this user?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Mute'),
          ),
        ],
      ),
    );
    if (muted == true) {
      final ok = await sp.muteUser(userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ok ? 'Stories muted' : 'Failed to mute')),
        );
      }
    }
  }

  void _openViewer(BuildContext context, String userId, List<Story> stories) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewerScreen(
          userId: userId,
          stories: stories,
        ),
      ),
    );
  }
}

class _StoryCreateButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: GestureDetector(
        onTap: () => _showCreateDialog(context),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.brown[400]!, width: 2),
                color: Colors.brown[50],
              ),
              child: const Icon(Icons.add, color: Colors.brown, size: 24),
            ),
            const SizedBox(height: 2),
            Text('Your Story',
                style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add to Story'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'What\'s on your mind?',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              final ok = await context.read<StoryProvider>().createStory(
                    content: text,
                    mediaType: 'text',
                  );
              if (context.mounted) Navigator.pop(context);
              if (context.mounted && ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Story posted!')),
                );
              }
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
}

class StoryViewerScreen extends StatefulWidget {
  final String userId;
  final List<Story> stories;

  const StoryViewerScreen({
    super.key,
    required this.userId,
    required this.stories,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late PageController _pageCtl;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageCtl = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StoryProvider>().viewStory(widget.stories.first.id);
    });
  }

  @override
  void dispose() {
    _pageCtl.dispose();
    super.dispose();
  }

  void _onPageChanged(int i) {
    setState(() => _currentIndex = i);
    context.read<StoryProvider>().viewStory(widget.stories[i].id);
  }

  Future<void> _showViewers(String storyId) async {
    final sp = context.read<StoryProvider>();
    final data = await sp.getStoryViews(storyId);
    final views = data['views'] as List<dynamic>;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${views.length} viewer${views.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            if (views.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No views yet'),
              )
            else
              SizedBox(
                height: 300,
                child: ListView.builder(
                  itemCount: views.length,
                  itemBuilder: (_, i) {
                    final v = views[i] as Map<String, dynamic>;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.brown[100],
                        child: Text(
                          ((v['display_name'] as String?)?.isNotEmpty == true
                                  ? v['display_name'] as String
                                  : '?')
                              .substring(0, 1)
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(v['display_name'] as String? ?? ''),
                      subtitle: Text('@${v['username'] as String? ?? ''}'),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _replyToStory(String storyId) async {
    final controller = TextEditingController();
    final replied = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reply to Story'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Send a direct message…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (replied != true) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final sp = context.read<StoryProvider>();
    final ok = await sp.replyToStory(storyId, text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Reply sent!' : 'Failed to send reply')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: PageView.builder(
          controller: _pageCtl,
          itemCount: widget.stories.length,
          onPageChanged: _onPageChanged,
          itemBuilder: (_, i) {
            final s = widget.stories[i];
            return Stack(
              children: [
                Center(
                  child: s.mediaType == 'text'
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            s.content,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : s.mediaUrl.isNotEmpty
                          ? Image.network(s.mediaUrl, fit: BoxFit.contain)
                          : Text(s.content,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 24),
                              textAlign: TextAlign.center),
                ),
                Positioned(
                  top: 48,
                  left: 16,
                  right: 16,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.brown[300],
                        child: Text(
                          (s.displayName.isNotEmpty
                                  ? s.displayName[0]
                                  : '?')
                              .toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.displayName.isNotEmpty
                              ? s.displayName
                              : s.username,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.visibility,
                            color: Colors.white70),
                        onPressed: () => _showViewers(s.id),
                        tooltip: 'Viewers',
                      ),
                      IconButton(
                        icon: const Icon(Icons.reply,
                            color: Colors.white70),
                        onPressed: () => _replyToStory(s.id),
                        tooltip: 'Reply via DM',
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                if (widget.stories.length > 1)
                  Positioned(
                    top: 40,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: List.generate(widget.stories.length,
                          (j) {
                        return Expanded(
                          child: Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 1),
                            height: 2,
                            decoration: BoxDecoration(
                              color: j <= _currentIndex
                                  ? Colors.white
                                  : Colors.white38,
                              borderRadius:
                                  BorderRadius.circular(1),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
