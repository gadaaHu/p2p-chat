import 'package:flutter/material.dart';

import '../services/session_manager.dart';
import '../utils/safety_number.dart';
import '../widgets/safety_number_view.dart';

class IdentityChangedScreen extends StatefulWidget {
  final SessionManager session;
  final String peerId;

  const IdentityChangedScreen({
    super.key,
    required this.session,
    required this.peerId,
  });

  @override
  State<IdentityChangedScreen> createState() =>
      _IdentityChangedScreenState();
}

class _IdentityChangedScreenState extends State<IdentityChangedScreen> {
  String? _oldSn;
  String? _newSn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _derive();
  }

  Future<void> _derive() async {
    final pending = widget.session.pendingRotation(widget.peerId);
    if (pending == null) return;

    final selfEd = widget.session.identity.identity.ed25519Public;
    final oldSn = await SafetyNumber.derive(
      pending.previousEd25519,
      selfEd,
    );
    final newSn = await SafetyNumber.derive(
      pending.ed25519Public,
      selfEd,
    );
    if (!mounted) return;
    setState(() {
      _oldSn = oldSn;
      _newSn = newSn;
    });
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    await widget.session.acceptRotation(widget.peerId);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    await widget.session.rejectRotation(widget.peerId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.session.pendingRotation(widget.peerId);
    return Scaffold(
      appBar: AppBar(title: const Text('Identity changed')),
      body: pending == null
          ? const Center(child: Text('No pending change.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Icon(
                  Icons.warning_amber,
                  size: 64,
                  color: Colors.red.shade700,
                ),
                const SizedBox(height: 12),
                const Text(
                  'This contact\'s identity key has changed.\n\n'
                  'This happens if they reinstalled the app. It can also '
                  'mean someone is intercepting your messages.\n\n'
                  'Only accept if you have confirmed the new safety number '
                  'with them in person or over a channel you trust.',
                  style: TextStyle(fontSize: 15, height: 1.4),
                ),
                const SizedBox(height: 24),
                _Section(
                  title: 'Previous safety number',
                  child: _oldSn == null
                      ? const LinearProgressIndicator()
                      : SafetyNumberView(raw: _oldSn!),
                ),
                _Section(
                  title: 'New safety number',
                  child: _newSn == null
                      ? const LinearProgressIndicator()
                      : SafetyNumberView(raw: _newSn!),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _accept,
                  child: const Text('I verified the new identity'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade900,
                  ),
                  child: const Text('Reject — this is not them'),
                ),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}