import 'package:flutter/material.dart';

enum VerificationStatus {
  /// No pin exists for this peer yet.
  unknown,

  /// Pinned but the user has not compared safety numbers.
  unverified,

  /// User compared safety numbers and marked verified.
  verified,

  /// A new key has been presented that differs from the pin.
  changed,
}

/// Compact or full status indicator for a contact's identity.
class VerificationBadge extends StatelessWidget {
  final VerificationStatus status;
  final bool compact;

  const VerificationBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      VerificationStatus.verified => (
          Icons.verified_user,
          'Verified',
          Colors.green,
        ),
      VerificationStatus.unverified => (
          Icons.shield_outlined,
          'Unverified',
          Colors.orange,
        ),
      VerificationStatus.changed => (
          Icons.warning_amber,
          'Identity changed',
          Colors.red,
        ),
      VerificationStatus.unknown => (
          Icons.help_outline,
          'Unknown',
          Colors.grey,
        ),
    };

    if (compact) {
      return Tooltip(
        message: label,
        child: Icon(icon, color: color, size: 20),
      );
    }

    return Chip(
      avatar: Icon(icon, color: color, size: 18),
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}