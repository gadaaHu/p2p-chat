import 'package:flutter/material.dart';

import '../utils/safety_number.dart';

/// Renders a 60-digit safety number as a 4x3 grid of 5-digit groups.
/// Selectable so a user can copy-paste it for a remote comparison.
class SafetyNumberView extends StatelessWidget {
  final String raw; // 60 digits, no spaces
  final TextStyle? style;

  const SafetyNumberView({
    super.key,
    required this.raw,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (raw.length != SafetyNumber.totalDigits) {
      return Text(
        'Invalid safety number (expected '
        '${SafetyNumber.totalDigits} digits, got ${raw.length})',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    final chunks = SafetyNumber.chunk(raw);
    final effectiveStyle = style ??
        const TextStyle(
          fontFamily: 'monospace',
          fontSize: 20,
          letterSpacing: 2,
        );

    // 3 rows of 4 groups.
    const groupsPerRow = 4;
    final rows = <Widget>[];
    for (var i = 0; i < chunks.length; i += groupsPerRow) {
      final end = (i + groupsPerRow).clamp(0, chunks.length);
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final c in chunks.sublist(i, end))
                SelectableText(c, style: effectiveStyle),
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }
}