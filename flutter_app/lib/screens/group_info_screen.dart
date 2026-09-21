import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/session_manager.dart';

class GroupInfoScreen extends StatefulWidget {
  final SessionManager session;
  final String groupId;

  const GroupInfoScreen({
    super.key,
    required this.session,
    required this.groupId,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  Group? _group;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _group = widget.session.groupById(widget.groupId));
  }

  Future<void> _addMember(GroupMember member) async {
    await widget.session.addGroupMember(widget.groupId, member);
    _load();
  }

  Future<void> _removeMember(String deviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove member?'),
        content: const Text(
          'They will no longer receive messages from this group. '
          'Messages they have already received cannot be recalled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.session.removeGroupMember(widget.groupId, deviceId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final g = _group;
    if (g == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: const Center(child: Text('Group not found.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(g.name)),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Group ID'),
            subtitle: Text(g.groupId),
            trailing: Text('epoch ${g.epoch}'),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Members (${g.members.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final m in g.members)
            ListTile(
              title: Text(
                m.deviceId == widget.session.selfDeviceId
                    ? '${m.deviceId} (you)'
                    : m.deviceId,
              ),
              subtitle: Text(
                'Added ${DateTime.fromMillisecondsSinceEpoch(m.addedAt).toLocal()}',
              ),
              trailing: m.deviceId == widget.session.selfDeviceId
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _removeMember(m.deviceId),
                    ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () => _showAddMemberSheet(g),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add member'),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMemberSheet(Group current) {
    final contacts = widget.session.peers.all().where(
          (c) => !current.contains(c.deviceId),
        );
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView(
        children: [
          for (final c in contacts)
            ListTile(
              title: Text(c.displayName),
              subtitle: Text(c.deviceId),
              onTap: () async {
                Navigator.pop(context);
                await _addMember(GroupMember(
                  deviceId: c.deviceId,
                  ed25519Public: c.ed25519Public,
                  addedAt: DateTime.now().millisecondsSinceEpoch,
                ));
              },
            ),
          if (contacts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No contacts available to add.'),
            ),
        ],
      ),
    );
  }
}