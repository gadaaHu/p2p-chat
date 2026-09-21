import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Signal-style safety numbers. Deterministic, symmetric, and 60 digits
/// long. Two devices that hold the same pair of identity keys will
/// compute the same string; two devices holding different keys will not.
///
/// The derivation is:
///   1. Sort the two Ed25519 public keys lexicographically.
///   2. Concatenate them.
///   3. For each of 12 groups, hash `concat || counter` with SHA-512 and
///      take the first 5 bytes, mod 100000.
///
/// Sorting is what makes the derivation symmetric: it does not matter
/// which side computes it.
class SafetyNumber {
  SafetyNumber._();

  static const groups = 12;
  static const digitsPerGroup = 5;
  static const totalDigits = groups * digitsPerGroup;

  static Future<String> derive(
    Uint8List ed25519A,
    Uint8List ed25519B,
  ) async {
    final (a, b) = _sorted(ed25519A, ed25519B);
    final concat = Uint8List.fromList([...a, ...b]);

    final hasher = Sha512();
    final out = StringBuffer();

    for (var i = 0; i < groups; i++) {
      final digest = await hasher.hash([...concat, i]);
      final bytes = digest.bytes;
      var v = 0;
      for (var j = 0; j < 5; j++) {
        v = (v << 8) | bytes[j];
      }
      v = v % 100000;
      out.write(v.toString().padLeft(digitsPerGroup, '0'));
    }

    return out.toString();
  }

  /// Inserts spaces every [perGroup] digits for display.
  static String format(String raw, {int perGroup = digitsPerGroup}) {
    final buf = StringBuffer();
    for (var i = 0; i < raw.length; i += perGroup) {
      if (i > 0) buf.write(' ');
      buf.write(raw.substring(i, (i + perGroup).clamp(0, raw.length)));
    }
    return buf.toString();
  }

  /// Splits the raw 60-digit string into [groups] chunks of 5 digits.
  /// Used by the display widget.
  static List<String> chunk(String raw) {
    final list = <String>[];
    for (var i = 0; i < raw.length; i += digitsPerGroup) {
      list.add(raw.substring(i, (i + digitsPerGroup).clamp(0, raw.length)));
    }
    return list;
  }

  static (Uint8List, Uint8List) _sorted(Uint8List a, Uint8List b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] < b[i]) return (a, b);
      if (a[i] > b[i]) return (b, a);
    }
    return a.length <= b.length ? (a, b) : (b, a);
  }
}