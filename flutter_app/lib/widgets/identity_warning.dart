import 'package:flutter/material.dart';

/// Inline banner shown when a peer's identity has changed. The user
/// must act (accept or reject the rotation); the banner is not
/// dismissible.
class IdentityWarning extends StatelessWidget {
  final String peerId;
  final String? peerName;
  final VoidCallback onReview;

  const IdentityWarning({
    super.key,
    required this.peerId,
    required this.onReview,
    this.peerName,
  });

  @override
  Widget build(BuildContext context) {
    final title = peerName ?? peerId;
    return Material(
      color: Colors.red.shade50,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.red.shade900),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Identity changed for $title',
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Messages are blocked until you review.',
                      style: TextStyle(color: Colors.red.shade900),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onReview,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade900,
                ),
                child: const Text('Review'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}