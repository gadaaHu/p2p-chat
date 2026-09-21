import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/peer_registry.dart';
import '../services/session_manager.dart';

class GroupCreateScreen extends StatefulWidget {
  final SessionManager session;
  final PeerRegistry peers;

  const GroupCreateScreen({
    super.key,
    required this.session,
    required this.peers,
  });

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  final _name = TextEditingController();
  final _selected = <String>{};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Group name is required');
      return;
    }
    if (_selected.isEmpty) {
      _snack('Select at least one member');
      return;
    }
    setState(() => _busy = true);
    try {
      final contacts = widget.peers.all();
      final members = <GroupMember>[];
      for (final id in _selected) {
        final c = contacts.firstWhere((c) => c.deviceId == id);
        members.add(GroupMember(
          deviceId: c.deviceId,
          ed25519Public: c.ed25519Public,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
      final group = await widget.session.createGroup(
        name: name,
        members: members,
      );
      if (!mounted) return;
      Navigator.pop(context, group);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('Failed: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final contacts = widget.peers.all();
    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _create,
            child: const Text('Create'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Group name',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: contacts.isEmpty
                ? const Center(child: Text('Pair a contact first.'))
                : ListView.builder(
                    itemCount: contacts.length,
                    itemBuilder: (_, i) {
                      final c = contacts[i];
                      final checked = _selected.contains(c.deviceId);
                      return CheckboxListTile(
                        value: checked,
                        title: Text(c.displayName),
                        subtitle: Text(c.deviceId),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(c.deviceId);
                            } else {
                              _selected.remove(c.deviceId);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}