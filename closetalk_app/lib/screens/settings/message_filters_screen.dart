import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/filter_provider.dart';

class MessageFiltersScreen extends StatefulWidget {
  const MessageFiltersScreen({super.key});

  @override
  State<MessageFiltersScreen> createState() => _MessageFiltersScreenState();
}

class _MessageFiltersScreenState extends State<MessageFiltersScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<FilterProvider>().load();
  }

  void _addWord() {
    final word = _controller.text.trim();
    if (word.isEmpty) return;
    context.read<FilterProvider>().addWord(word);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final fp = context.watch<FilterProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Message Filters')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Add blocked word…',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _addWord(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.blue),
                  onPressed: _addWord,
                ),
              ],
            ),
          ),
          if (fp.blockedWords.isEmpty)
            const Expanded(
              child: Center(
                child: Text('No blocked words yet',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: fp.blockedWords.length,
                itemBuilder: (_, i) {
                  final word = fp.blockedWords[i];
                  return ListTile(
                    leading: const Icon(Icons.block, color: Colors.red),
                    title: Text(word),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.grey),
                      onPressed: () => fp.removeWord(word),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
