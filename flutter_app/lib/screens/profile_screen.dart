import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../repositories/identity_repository.dart';
import '../services/identity_service.dart';
import '../utils/fingerprint_utils.dart';

class ProfileScreen extends StatefulWidget {
  final IdentityRepository profileRepo;
  final IdentityService identity;

  const ProfileScreen({
    super.key,
    required this.profileRepo,
    required this.identity,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await widget.profileRepo.load();
    if (!mounted) return;
    setState(() {
      _profile = p;
      _name.text = p.displayName;
    });
  }

  Future<void> _save() async {
    await widget.profileRepo.setDisplayName(_name.text.trim());
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.identity.identity;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: _profile == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),
                _InfoRow(label: 'Device ID', value: id.deviceId),
                _InfoRow(
                  label: 'Identity key',
                  value: shortFingerprint(id.ed25519Public),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Your device ID is how contacts find you when '
                          'pairing. Share the invite QR, not this string, '
                          'unless you have already established a trusted '
                          'channel.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}