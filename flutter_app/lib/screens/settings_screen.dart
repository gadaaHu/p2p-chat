import 'package:flutter/material.dart';

import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settings;

  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Send read receipts'),
            subtitle: const Text(
              'When off, contacts see "delivered" but never "read". '
              'Local unread counts still work.',
            ),
            value: widget.settings.readReceiptsEnabled,
            onChanged: (v) async {
              await widget.settings.setReadReceiptsEnabled(v);
              if (mounted) setState(() {});
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Message retention'),
            subtitle: Text(
              'Unlimited. Local records are kept until the conversation '
              'is deleted.',
            ),
            enabled: false,
          ),
          const Divider(),
          ListTile(
            title: const Text('Clear all local data'),
            subtitle: const Text(
              'Removes messages, contacts, and keys. Cannot be undone.',
            ),
            trailing: const Icon(Icons.warning_amber),
            onTap: () => _confirmWipe(context),
          ),
        ],
      ),
    );
  }

  void _confirmWipe(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear everything?'),
        content: const Text(
          'Every message, contact, and key will be erased. You will not '
          'be able to decrypt old messages and contacts will see you as '
          'a new device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () {
              Navigator.pop(context);
              // Implementation lives in main.dart; this triggers the
              // wipe callback passed via SettingsService if needed.
              widget.settings.requestFullWipe();
            },
            child: const Text('Erase'),
          ),
        ],
      ),
    );
  }
}