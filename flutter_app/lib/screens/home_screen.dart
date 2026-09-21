import 'package:flutter/material.dart';

import '../services/peer_registry.dart';
import '../services/session_manager.dart';
import '../services/settings_service.dart';
import '../services/webrtc_manager.dart';
import 'contacts_screen.dart';
import 'pair_screen.dart';
import 'security_screen.dart';
import 'settings_screen.dart';

/// The landing screen. Three actions: see contacts, pair a new device,
/// or open the security overview.
class HomeScreen extends StatelessWidget {
  final SessionManager session;
  final PeerRegistry peers;
  final SettingsService settings;
  final WebRTCManager webrtc;

  const HomeScreen({
    super.key,
    required this.session,
    required this.peers,
    required this.settings,
    required this.webrtc,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('p2p_chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(settings: settings),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SecurityScreen(
                  session: session,
                  peers: peers,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 96,
              color: scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'End-to-end encrypted.\nNo server.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 48),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ContactsScreen(
                    session: session,
                    peers: peers,
                  ),
                ),
              ),
              icon: const Icon(Icons.people_outline),
              label: const Text('Contacts'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PairScreen(),
                ),
              ),
              icon: const Icon(Icons.qr_code),
              label: const Text('Pair a device'),
            ),
          ],
        ),
      ),
    );
  }
}
