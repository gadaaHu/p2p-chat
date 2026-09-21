import 'package:flutter/material.dart';

import '../services/session_manager.dart';
import '../utils/fingerprint_utils.dart';
import '../utils/safety_number.dart';
import '../widgets/safety_number_view.dart';
import '../widgets/verification_badge.dart';

class IdentityVerificationScreen extends StatefulWidget {
  final SessionManager session;
  final String peerId;

  const IdentityVerificationScreen({
    super.key,
    required this.session,
    required this.peerId,
  });

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> {
  String? _safetyNumber;
  String? _theirFingerprint;
  String? _ourFingerprint;
  bool _verified = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pins = widget.session.pins;
    final pin = await pins.pinFor(widget.peerId);
    if (pin == null) return;
    final sn = await SafetyNumber.derive(
      pin.ed25519Public,
      widget.session.identity.identity.ed25519Public,
    );
    final verified = await pins.isVerified(widget.peerId);
    if (!mounted) return;
    setState(() {
      _safetyNumber = sn;
      _theirFingerprint = shortFingerprint(pin.ed25519Public);
      _ourFingerprint = shortFingerprint(
        widget.session.identity.identity.ed25519Public,
      );
      _verified = verified;
    });
  }

  Future<void> _markVerified() async {
    setState(() => _busy = true);
    await widget.session.markVerified(widget.peerId);
    await _load();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact marked verified')),
    );
  }

  Future<void> _forget() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Forget identity?'),
        content: const Text(
          'The stored pin will be removed. The next message will re-pin '
          'via trust-on-first-use and show as unverified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.session.forgetPeer(widget.peerId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify identity')),
      body: _safetyNumber == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.peerId,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    VerificationBadge(
                      status: _verified
                          ? VerificationStatus.verified
                          : VerificationStatus.unverified,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Compare this safety number with your contact. It must '
                  'match on both devices. Read it aloud or compare '
                  'in person.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SafetyNumberView(raw: _safetyNumber!),
                  ),
                ),
                const SizedBox(height: 24),
                _FingerprintRow(label: 'Their key', value: _theirFingerprint),
                _FingerprintRow(label: 'Your key', value: _ourFingerprint),
                const SizedBox(height: 32),
                if (!_verified)
                  FilledButton.icon(
                    onPressed: _busy ? null : _markVerified,
                    icon: const Icon(Icons.verified_user),
                    label: const Text('I compared this in person'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _forget,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Forget identity'),
                  ),
              ],
            ),
    );
  }
}

class _FingerprintRow extends StatelessWidget {
  final String label;
  final String? value;

  const _FingerprintRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}