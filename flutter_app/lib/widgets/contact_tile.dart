import 'package:flutter/material.dart';

import '../models/contact.dart';
import 'verification_badge.dart';

class ContactTile extends StatelessWidget {
  final Contact contact;
  final int unreadCount;
  final VerificationStatus verification;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const ContactTile({
    super.key,
    required this.contact,
    required this.unreadCount,
    required this.verification,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          _initials(contact.displayName),
          style: TextStyle(color: scheme.onPrimaryContainer),
        ),
      ),
      title: Text(
        contact.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        contact.deviceId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          VerificationBadge(status: verification, compact: true),
          const SizedBox(width: 8),
          if (unreadCount > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}