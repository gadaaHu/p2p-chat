import 'dart:convert';

/// What kind of manual signaling payload a [SignalingBlob] carries.
enum BlobKind {
  /// The initiator's SDP offer.
  offer,

  /// The responder's SDP answer.
  answer,

  /// A single ICE candidate, serialized as JSON.
  ice,
}

/// A single unit of manual signaling. Encodes to a compact string
/// suitable for a QR code or a copy-paste field, and decodes back to
/// the original payload.
///
/// Format: `p2p1:<kind>:<base64url(payload, no padding)>`
///
/// The `p2p1` version tag lets future formats coexist. The kind is one
/// of [BlobKind] values. The payload is the raw SDP text for offers and
/// answers, and a JSON object for ICE candidates.
class SignalingBlob {
  final BlobKind kind;
  final String payload;

  const SignalingBlob({required this.kind, required this.payload});

  /// Compact, URL-safe, QR-friendly representation.
  String encode() {
    final b64 = base64Url
        .encode(utf8.encode(payload))
        .replaceAll('=', '');
    return 'p2p1:${kind.name}:$b64';
  }

  /// Returns null when [s] is not a valid blob. Never throws.
  static SignalingBlob? tryDecode(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return null;

    final parts = trimmed.split(':');
    if (parts.length != 3) return null;
    if (parts[0] != 'p2p1') return null;

    final kind = _kindFromName(parts[1]);
    if (kind == null) return null;

    try {
      final raw = parts[2];
      final padLength = (4 - raw.length % 4) % 4;
      final padded = raw + ('=' * padLength);
      final payload = utf8.decode(base64Url.decode(padded));
      return SignalingBlob(kind: kind, payload: payload);
    } catch (_) {
      return null;
    }
  }

  /// Convenience for validating an ICE candidate payload. Returns the
  /// decoded map, or null if the payload is not a JSON object with the
  /// expected keys.
  Map<String, dynamic>? decodeIce() {
    if (kind != BlobKind.ice) return null;
    try {
      final j = jsonDecode(payload);
      if (j is! Map<String, dynamic>) return null;
      if (j['candidate'] is! String) return null;
      return j;
    } catch (_) {
      return null;
    }
  }

  /// Convenience for validating an SDP payload. Returns the decoded
  /// `{type, sdp}` map, or null.
  Map<String, dynamic>? decodeSdp() {
    if (kind == BlobKind.ice) return null;
    try {
      final j = jsonDecode(payload);
      if (j is! Map<String, dynamic>) return null;
      if (j['sdp'] is! String) return null;
      return j;
    } catch (_) {
      return null;
    }
  }

  static BlobKind? _kindFromName(String name) {
    for (final k in BlobKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  @override
  String toString() => 'SignalingBlob(${kind.name}, ${payload.length} chars)';

  @override
  bool operator ==(Object other) =>
      other is SignalingBlob &&
      other.kind == kind &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(kind, payload);
}