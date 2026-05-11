import 'dart:convert';
import 'package:flutter/material.dart';

class PollContent extends StatefulWidget {
  final String jsonContent;
  final String myUserId;
  final void Function(int optionIndex) onVote;

  const PollContent({
    super.key,
    required this.jsonContent,
    required this.myUserId,
    required this.onVote,
  });

  @override
  State<PollContent> createState() => _PollContentState();
}

class _PollContentState extends State<PollContent> {
  late Map<String, dynamic> _poll;

  @override
  void initState() {
    super.initState();
    _poll = jsonDecode(widget.jsonContent) as Map<String, dynamic>;
  }

  String get _question => _poll['question'] as String;
  List<String> get _options => (_poll['options'] as List).cast<String>();
  Map<String, dynamic> get _votes => _poll['votes'] as Map<String, dynamic>;

  int _votesFor(String option) {
    final voters = _votes[option] as List<dynamic>?;
    return voters?.length ?? 0;
  }

  int get _totalVotes {
    int total = 0;
    for (final o in _options) {
      total += _votesFor(o);
    }
    return total;
  }

  bool _hasVoted(String option) {
    final voters = _votes[option] as List<dynamic>?;
    return voters?.contains(widget.myUserId) ?? false;
  }

  bool get _iVoted {
    for (final o in _options) {
      if (_hasVoted(o)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalVotes;

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_question,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ..._options.map((option) {
            final votes = _votesFor(option);
            final ratio = total > 0 ? votes / total : 0.0;
            final voted = _hasVoted(option);

            final optIndex = _options.indexOf(option);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: _iVoted ? null : () => widget.onVote(optIndex),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: voted ? Colors.blue : Colors.grey[300]!,
                      width: voted ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      if (total > 0)
                        Positioned.fill(
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: ratio,
                            child: Container(
                              decoration: BoxDecoration(
                                color: voted
                                    ? Colors.blue.withValues(alpha: 0.12)
                                    : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              option,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    voted ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          Text(
                            total > 0
                                ? '${(ratio * 100).toStringAsFixed(0)}%'
                                : '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          Text(
            '${total} vote${total == 1 ? '' : 's'}${_iVoted ? ' · You voted' : ''}',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
