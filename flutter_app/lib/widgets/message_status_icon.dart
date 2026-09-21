import 'package:flutter/material.dart';

import '../models/outbound_message.dart';

class MessageStatusIcon extends StatelessWidget {
  final MessageState state;
  final String? lastError;

  const MessageStatusIcon({
    super.key,
    required this.state,
    this.lastError,
  });

  @override
  Widget build(BuildContext context) {
    final (icon, color, tooltip) = switch (state) {
      MessageState.queued => (
          Icons.schedule,
          Colors.grey,
          lastError == null ? 'Queued' : 'Queued — retrying: $lastError',
        ),
      MessageState.relayed => (
          Icons.done,
          Colors.grey.shade600,
          'Sent to relay, awaiting delivery',
        ),
      MessageState.delivered => (
          Icons.done_all,
          Colors.blue,
          'Delivered to peer',
        ),
      MessageState.read => (
          Icons.done_all,
          Colors.green,
          'Read by peer',
        ),
      MessageState.failed => (
          Icons.error_outline,
          Colors.red,
          lastError ?? 'Failed',
        ),
      MessageState.blocked => (
          Icons.block,
          Colors.red.shade900,
          'Identity rejected — messages are not being delivered',
        ),
    };

    return Tooltip(
      message: tooltip,
      child: Icon(icon, size: 16, color: color),
    );
  }
}