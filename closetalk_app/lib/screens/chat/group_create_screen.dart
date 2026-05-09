import 'package:flutter/material.dart';

import '../../models/group.dart';
import '../../services/group_service.dart';

class GroupCreateScreen extends StatefulWidget {
  final GroupService groupService;

  const GroupCreateScreen({super.key, required this.groupService});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _selectedMembers = <String>[];
  bool _isPublic = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (_nameController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await widget.groupService.createGroup(CreateGroupRequest(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        isPublic: _isPublic,
        memberIds: _selectedMembers,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Group')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Group name',
                border: OutlineInputBorder(),
              ),
              maxLength: 100,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Public group'),
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createGroup,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Create Group'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
