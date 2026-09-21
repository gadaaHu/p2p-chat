import 'package:flutter/material.dart';

import '../models/identity_pin.dart';
import '../services/peer_registry.dart';
import '../services/session_manager.dart';
import '../widgets/contact_tile.dart';
import '../widgets/verification_badge.dart';
import 'chat_screen.dart';
import 'identity_verification_screen.dart';

class ContactsScreen extends StatelessWidget {
  final SessionManager session;
  final PeerRegistry peers;

  const ContactsScreen({
    super.key,
    required this.session,
    required this.peers,
  });


  @override
  Widget build(BuildContext context) {
    final list = peers.all();
    if (list.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Contacts')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No contacts yet.\nPair a device from the home screen.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      body: ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = list[i];
          return FutureBuilder<IdentityPin?>(
            future: session.pins.pinFor(c.deviceId),
            builder: (_, pinSnap) {
              final status = pinSnap.data == null
                  ? VerificationStatus.unknown
                  : (pinSnap.data!.verified
                      ? VerificationStatus.verified
                      : VerificationStatus.unverified);
              return ContactTile(
                contact: c,
                unreadCount: session.unreadFor(c.deviceId),
                verification: status,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(
                      session: session,
                      peerDeviceId: c.deviceId,
                    ),
                  ),
                ),
                onLongPress: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => IdentityVerificationScreen(
                      session: session,
                      peerId: c.deviceId,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}