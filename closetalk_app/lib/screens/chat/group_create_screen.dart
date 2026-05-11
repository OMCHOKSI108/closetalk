import 'package:flutter/material.dart';

import '../../models/group.dart';
import '../../services/group_service.dart';
import '../../theme/app_theme.dart';

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
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name is required')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await widget.groupService.createGroup(
        CreateGroupRequest(
          name: name,
          description: _descriptionController.text.trim(),
          isPublic: _isPublic,
          memberIds: _selectedMembers,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('HttpException: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nameLength = _nameController.text.trim().length;
    return Scaffold(
      appBar: AppBar(title: const Text('New Group')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 32,
                      backgroundColor: AppColors.surface,
                      child: Icon(Icons.groups_rounded,
                          color: AppColors.orange, size: 34),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Group name',
                        helperText: '$nameLength/100',
                        prefixIcon: const Icon(Icons.tag_rounded),
                      ),
                      maxLength: 100,
                      buildCounter: (
                        context, {
                        required currentLength,
                        required isFocused,
                        required maxLength,
                      }) =>
                          null,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'What is this group about?',
                        prefixIcon: Icon(Icons.notes_rounded),
                      ),
                      minLines: 3,
                      maxLines: 5,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: _isPublic,
                onChanged: (v) => setState(() => _isPublic = v),
                title: const Text('Public group'),
                subtitle: Text(
                  _isPublic
                      ? 'Anyone can discover and join this group.'
                      : 'Only people with an invite can join.',
                ),
                secondary: Icon(
                  _isPublic ? Icons.public_rounded : Icons.lock_rounded,
                  color: _isPublic ? AppColors.orange : AppColors.textSecondary,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              const SizedBox(height: 28),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [AppColors.glow(color: AppColors.orange)],
                ),
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded),
                  label: Text(_isLoading ? 'Creating...' : 'Create Group'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
