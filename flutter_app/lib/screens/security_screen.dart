import 'package:flutter/material.dart';

import '../models/identity_pin.dart';
import '../services/peer_registry.dart';
import '../services/session_manager.dart';
import '../widgets/verification_badge.dart';
import 'identity_changed_screen.dart';
import 'identity_verification_screen.dart';

class SecurityScreen extends StatefulWidget {
  final SessionManager session;
  final PeerRegistry peers;

  const SecurityScreen({
    super.key,
    required this.session,
    required this.peers,
  });

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  List<IdentityPin> _pins = [];
  final _changedPeers = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
    widget.session.identityChanged.listen((id) {
      if (!mounted) return;
      setState(() => _changedPeers.add(id));
    });
  }

  Future<void> _load() async {
    final pins = await widget.session.pins.all();
    if (!mounted) return;
    setState(() => _pins = pins);
  }

  VerificationStatus _status(IdentityPin p) {
    if (_changedPeers.contains(p.deviceId)) {
      return VerificationStatus.changed;
    }
    return p.verified
        ? VerificationStatus.verified
        : VerificationStatus.unverified;
  }

  Future<void> _open(IdentityPin p) async {
    if (_changedPeers.contains(p.deviceId)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IdentityChangedScreen(
            session: widget.session,
            peerId: p.deviceId,
          ),
        ),
      );
      _changedPeers.remove(p.deviceId);
      await _load();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IdentityVerificationScreen(
          session: widget.session,
          peerId: p.deviceId,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _pins.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No contacts yet.')),
                ],
              )
            : ListView.separated(
                itemCount: _pins.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final p = _pins[i];
                  final contact = widget.peers.byId(p.deviceId);
                  return ListTile(
                    title: Text(
                      contact?.displayName ?? p.deviceId,
                    ),
                    subtitle: Text(
                      p.verified && p.verifiedAt != null
                          ? 'Verified ${_dateStr(p.verifiedAt!)}'
                          : 'Not verified',
                    ),
                    trailing: VerificationBadge(status: _status(p)),
                    onTap: () => _open(p),
                  );
                },
              ),
      ),
    );
  }

  String _dateStr(int unixSec) {
    final d = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    return d.toLocal().toString().split('.').first;
  }
}