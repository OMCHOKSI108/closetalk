import 'dart:convert';
import 'package:flutter/material.dart';

class PollCreatorSheet extends StatefulWidget {
  final void Function(String jsonContent) onSend;

  const PollCreatorSheet({super.key, required this.onSend});

  @override
  State<PollCreatorSheet> createState() => _PollCreatorSheetState();
}

class _PollCreatorSheetState extends State<PollCreatorSheet> {
  final _questionCtl = TextEditingController();
  final _optionCtls = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];

  @override
  void dispose() {
    _questionCtl.dispose();
    for (final c in _optionCtls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    setState(() => _optionCtls.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_optionCtls.length <= 2) return;
    setState(() {
      _optionCtls[i].dispose();
      _optionCtls.removeAt(i);
    });
  }

  void _send() {
    final question = _questionCtl.text.trim();
    if (question.isEmpty) return;
    final options = _optionCtls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (options.length < 2) return;

    final poll = {
      'question': question,
      'options': options,
      'votes': {for (final o in options) o: <String>[]},
    };

    widget.onSend(jsonEncode(poll));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Create Poll',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _questionCtl,
            decoration: const InputDecoration(
              labelText: 'Question',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(_optionCtls.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _optionCtls[i],
                      decoration: InputDecoration(
                        labelText: 'Option ${i + 1}',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  if (_optionCtls.length > 2)
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () => _removeOption(i),
                    ),
                ],
              ),
            );
          }),
          TextButton.icon(
            onPressed: _addOption,
            icon: const Icon(Icons.add),
            label: const Text('Add Option'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _send,
            child: const Text('Send Poll'),
          ),
        ],
      ),
    );
  }
}
