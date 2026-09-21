import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

/// Short, human-readable fingerprint of a public key. Not a security
/// boundary — it is a display aid. The authoritative check is the full
/// safety number.
///
/// Format: uppercase hex, grouped in fours: `A1B2 C3D4 E5F6 0718`
String shortFingerprint(Uint8List publicKey) {
  final digest = c.sha256.convert(publicKey).bytes;
  final hex = digest
      .take(8)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return hex
      .replaceAllMapped(RegExp(r'.{4}'), (m) => '${m.group(0)} ')
      .trim();
}

/// Longer fingerprint: full sha256 of the key, uppercase hex, grouped
/// in fours. Used on the details screen where there is room.
String longFingerprint(Uint8List publicKey) {
  final digest = c.sha256.convert(publicKey).bytes;
  final hex = digest
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  final buf = StringBuffer();
  for (var i = 0; i < hex.length; i += 4) {
    if (i > 0) buf.write(' ');
    buf.write(hex.substring(i, (i + 4).clamp(0, hex.length)));
  }
  return buf.toString();
}