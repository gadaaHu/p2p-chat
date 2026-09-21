import 'package:flutter/material.dart';

import '../models/outbound_message.dart';

/// Aggregate status for a group message. Renders "delivered/total" and
/// taps through to a details sheet.
class GroupMessageStatus extends StatelessWidget {
  final GroupDeliverySummary summary;
  final VoidCallback? onTap;

  const GroupMessageStatus({
    super.key,
    required this.summary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final total = summary.total;
    final delivered = summary.delivered;
    final read = summary.read;

    final (icon, color) = switch (summary) {
      GroupDeliverySummary(allRead: true) => (
          Icons.done_all,
          Colors.lightBlueAccent,
        ),
      GroupDeliverySummary(anyFailure: true) => (
          Icons.error_outline,
          Colors.red.shade200,
        ),
      GroupDeliverySummary(allDelivered: true) => (
          Icons.done_all,
          Colors.white70,
        ),
      _ => (
          Icons.schedule,
          Colors.white70,
        ),
    };

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              read > 0 ? '$read read · $delivered/$total' : '$delivered/$total',
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
      ),
    );
  }
}