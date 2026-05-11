import 'package:flutter/material.dart';

import '../../models/group.dart';
import '../../services/group_service.dart';
import 'add_members_screen.dart';

class GroupInfoScreen extends StatefulWidget {
  final Group group;
  final GroupService groupService;

  const GroupInfoScreen({
    super.key,
    required this.group,
    required this.groupService,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late bool _isMuted;
  bool _isWorking = false;

  Group get group => widget.group;
  GroupService get groupService => widget.groupService;

  @override
  void initState() {
    super.initState();
    _isMuted = group.isMuted;
  }

  Future<void> _toggleMute() async {
    if (_isWorking) return;
    setState(() => _isWorking = true);
    try {
      if (_isMuted) {
        await groupService.unmuteGroup(group.id);
      } else {
        await groupService.muteGroup(group.id);
      }
      if (!mounted) return;
      setState(() => _isMuted = !_isMuted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isMuted ? 'Group muted' : 'Group unmuted')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _blockGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block group?'),
        content: const Text(
          'This removes the group from your list and hides it from discovery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isWorking = true);
    try {
      await groupService.blockGroup(group.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = group.role == 'admin';
    return Scaffold(
      appBar: AppBar(title: Text(group.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CircleAvatar(
            radius: 40,
            child: Text(group.name[0].toUpperCase()),
          ),
          const SizedBox(height: 8),
          Text(group.name,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center),
          if (group.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(group.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center),
            ),
          const SizedBox(height: 16),

          ListTile(
            leading: const Icon(Icons.people),
            title: Text('${group.memberCount} members'),
          ),
          if (isAdmin) ...[
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Add members'),
              onTap: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddMembersScreen(
                            groupService: groupService,
                      groupId: group.id,
                    ),
                  ),
                );
                if (result == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Members added successfully')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Share invite link'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        _InviteLinkScreen(groupService: groupService, groupId: group.id),
                  ),
                );
              },
            ),
          ],
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Group settings'),
            onTap: () {
              showModalBottomSheet(
                context: context,
                builder: (_) => _GroupSettingsSheet(
                  group: group,
                  groupService: groupService,
                ),
              );
            },
          ),
          ListTile(
            enabled: !_isWorking,
            leading: Icon(
              _isMuted ? Icons.notifications_active : Icons.notifications_off,
            ),
            title: Text(_isMuted ? 'Unmute group' : 'Mute group'),
            onTap: _toggleMute,
          ),
          ListTile(
            enabled: !_isWorking,
            leading: const Icon(Icons.block, color: Colors.red),
            title: const Text('Block group'),
            onTap: _blockGroup,
          ),
          if (isAdmin) ...[
            ListTile(
              leading: const Icon(Icons.exit_to_app),
              title: const Text('Leave group'),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Leave group?'),
                    content: const Text('This cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Leave',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (confirm == true) {
                  await groupService.leaveGroup(group.id);
                  if (context.mounted) Navigator.of(context).pop(true);
                }
              },
            ),
          ],

          const Divider(),
          const Text('Members',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ...group.members.map((m) => ListTile(
                leading: CircleAvatar(child: Text(m.displayName[0])),
                title: Text(m.displayName),
                subtitle: Text(m.role),
                trailing: isAdmin && m.role == 'member'
                    ? PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'remove') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Remove member?'),
                                content: Text('Remove ${m.displayName}?'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel')),
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Remove',
                                          style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await groupService.removeMember(group.id, m.userId);
                            }
                          } else if (action == 'make_admin') {
                            await groupService.updateRole(
                                group.id, m.userId, 'admin');
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'remove',
                              child: Text('Remove')),
                          const PopupMenuItem(
                              value: 'make_admin',
                              child: Text('Make admin')),
                        ],
                      )
                    : null,
              )),

          if (group.pinnedMessages.isNotEmpty) ...[
            const Divider(),
            const Text('Pinned messages',
                style: TextStyle(fontWeight: FontWeight.bold)),
            ...group.pinnedMessages.map((p) => ListTile(
                  leading: const Icon(Icons.push_pin),
                  title: Text('Message ${p.messageId}'),
                  subtitle: Text(p.pinnedAt.toString()),
                )),
          ],
        ],
      ),
    );
  }
}

class _InviteLinkScreen extends StatefulWidget {
  final GroupService groupService;
  final String groupId;

  const _InviteLinkScreen({
    required this.groupService,
    required this.groupId,
  });

  @override
  State<_InviteLinkScreen> createState() => _InviteLinkScreenState();
}

class _InviteLinkScreenState extends State<_InviteLinkScreen> {
  InviteResponse? _invite;
  bool _isLoading = false;

  Future<void> _generate() async {
    setState(() => _isLoading = true);
    try {
      final invite =
          await widget.groupService.generateInvite(widget.groupId);
      setState(() => _invite = invite);
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
      appBar: AppBar(title: const Text('Invite Link')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_invite != null) ...[
                const Icon(Icons.link, size: 64),
                const SizedBox(height: 16),
                SelectableText(
                  _invite!.url,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('Expires: ${_invite!.expiresAt}'),
                const SizedBox(height: 16),
              ],
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _generate,
                icon: _isLoading
                    ? const CircularProgressIndicator()
                    : const Icon(Icons.refresh),
                label: Text(_invite == null ? 'Generate Link' : 'Regenerate'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupSettingsSheet extends StatefulWidget {
  final Group group;
  final GroupService groupService;

  const _GroupSettingsSheet({
    required this.group,
    required this.groupService,
  });

  @override
  State<_GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends State<_GroupSettingsSheet> {
  late String _messageRetention;
  late String _disappearingMsg;

  @override
  void initState() {
    super.initState();
    _messageRetention = widget.group.messageRetention;
    _disappearingMsg = widget.group.disappearingMsg;
  }

  Future<void> _save() async {
    try {
      await widget.groupService.updateSettings(
        widget.group.id,
        UpdateGroupSettingsRequest(
          messageRetention: _messageRetention,
          disappearingMsg: _disappearingMsg,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Group Settings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _messageRetention,
            decoration: const InputDecoration(labelText: 'Message retention'),
            items: const [
              DropdownMenuItem(value: 'off', child: Text('Off')),
              DropdownMenuItem(value: '30d', child: Text('30 days')),
              DropdownMenuItem(value: '90d', child: Text('90 days')),
              DropdownMenuItem(value: '1yr', child: Text('1 year')),
            ],
            onChanged: (v) => setState(() => _messageRetention = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _disappearingMsg,
            decoration:
                const InputDecoration(labelText: 'Disappearing messages'),
            items: const [
              DropdownMenuItem(value: 'off', child: Text('Off')),
              DropdownMenuItem(value: '5s', child: Text('5 seconds')),
              DropdownMenuItem(value: '30s', child: Text('30 seconds')),
              DropdownMenuItem(value: '5m', child: Text('5 minutes')),
              DropdownMenuItem(value: '1h', child: Text('1 hour')),
              DropdownMenuItem(value: '24h', child: Text('24 hours')),
            ],
            onChanged: (v) => setState(() => _disappearingMsg = v!),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
