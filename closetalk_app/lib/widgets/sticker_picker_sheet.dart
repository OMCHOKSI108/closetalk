import 'package:flutter/material.dart';

class StickerPickerSheet extends StatefulWidget {
  final void Function(String emoji) onSelected;
  final void Function(String gifUrl) onGifSelected;

  const StickerPickerSheet({
    super.key,
    required this.onSelected,
    required this.onGifSelected,
  });

  @override
  State<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<StickerPickerSheet> {
  int _tabIndex = 0;

  static const _categories = [
    _StickerCategory('Smileys', ['😀', '😂', '🥹', '😍', '🤩', '😎', '🤗', '🥳', '😊', '🤔', '😴', '🥶', '🤯', '🥺', '😈', '🤡', '💀', '👻']),
    _StickerCategory('Gestures', ['👍', '👎', '👊', '✌️', '🤞', '🖖', '🤘', '🤙', '👋', '✋', '🙌', '👏', '💪', '🫶', '🙏', '🤝']),
    _StickerCategory('Hearts', ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💕', '💗', '💖', '💘', '💝', '❣️', '💔', '🔥']),
    _StickerCategory('Animals', ['🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦']),
    _StickerCategory('Food', ['🍎', '🍕', '🍔', '🌮', '🍦', '🍩', '☕', '🧃', '🍺', '🍷', '🎂', '🍿', '🥑', '🥦', '🌶️', '🧀']),
    _StickerCategory('Objects', ['🎉', '🎊', '🎁', '🎈', '🏆', '⭐', '🌈', '⚡', '🔥', '💯', '✅', '❌', '🆒', '🆕', '🚀', '👑', '🎶', '📸']),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => setState(() => _tabIndex = 0),
                  child: Text('Stickers',
                      style: TextStyle(
                          fontWeight: _tabIndex == 0 ? FontWeight.bold : FontWeight.normal,
                          color: _tabIndex == 0 ? Colors.brown : Colors.grey)),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () => setState(() => _tabIndex = 1),
                  child: Text('GIFs',
                      style: TextStyle(
                          fontWeight: _tabIndex == 1 ? FontWeight.bold : FontWeight.normal,
                          color: _tabIndex == 1 ? Colors.brown : Colors.grey)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _tabIndex == 0 ? _buildStickers() : _buildGifPlaceholder(),
          ),
        ],
      ),
    );
  }

  Widget _buildStickers() {
    return DefaultTabController(
      length: _categories.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: _categories
                .map((c) => Tab(text: c.name))
                .toList(),
          ),
          Expanded(
            child: TabBarView(
              children: _categories.map((cat) {
                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: cat.emojis.length,
                  itemBuilder: (_, i) {
                    return GestureDetector(
                      onTap: () => widget.onSelected(cat.emojis[i]),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(cat.emojis[i], style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGifPlaceholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gif_box, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text('GIF search coming soon',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _StickerCategory {
  final String name;
  final List<String> emojis;
  const _StickerCategory(this.name, this.emojis);
}
