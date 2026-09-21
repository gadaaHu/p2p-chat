import 'package:flutter/material.dart';

import '../models/message.dart';
import '../models/outbound_message.dart';
import 'message_status_icon.dart';

class MessageBubble extends StatelessWidget {
  final Message message;

  /// Non-null for messages this device sent. Drives the status icon.
  final MessageState? outboundState;
  final String? outboundError;

  const MessageBubble({
    super.key,
    required this.message,
    this.outboundState,
    this.outboundError,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? scheme.primary
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isMe ? scheme.onPrimary : scheme.onSurface,
              ),
            ),
            if (isMe && outboundState != null) ...[
              const SizedBox(height: 4),
              MessageStatusIcon(
                state: outboundState!,
                lastError: outboundError,
              ),
            ],
          ],
        ),
      ),
    );
  }
}