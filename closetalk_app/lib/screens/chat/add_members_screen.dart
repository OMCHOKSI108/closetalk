import 'package:flutter/material.dart';
import '../../services/group_service.dart';

class AddMembersScreen extends StatefulWidget {
  final GroupService groupService;
  final String groupId;

  const AddMembersScreen({
    super.key,
    required this.groupService,
    required this.groupId,
  });

  @override
  State<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends State<AddMembersScreen> {
  final _memberIds = <String>[];
  final _userIdController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _userIdController.dispose();
    super.dispose();
  }

  void _addUserId() {
    final id = _userIdController.text.trim();
    if (id.isNotEmpty && !_memberIds.contains(id)) {
      setState(() => _memberIds.add(id));
      _userIdController.clear();
    }
  }

  Future<void> _addMembers() async {
    if (_memberIds.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await widget.groupService.addMembers(widget.groupId, _memberIds);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Members added')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Members')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _userIdController,
                    decoration: const InputDecoration(
                      labelText: 'User ID',
                      border: OutlineInputBorder(),
                      hintText: 'Enter user ID',
                    ),
                    onSubmitted: (_) => _addUserId(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.blue),
                  onPressed: _addUserId,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_memberIds.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _memberIds.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(_memberIds[i]),
                    trailing: IconButton(
                      icon:
                          const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () =>
                          setState(() => _memberIds.removeAt(i)),
                    ),
                  ),
                ),
              )
            else
              const Expanded(
                child: Center(
                  child: Text('No members added yet'),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_memberIds.isEmpty || _isLoading) ? null : _addMembers,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Add ${_memberIds.length} member(s)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
