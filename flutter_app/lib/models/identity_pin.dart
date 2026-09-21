import 'dart:convert';
import 'dart:typed_data';

/// Outcome of evaluating a peer's presented identity against the pin.
enum PinState {
  /// Peer has never been seen. TOFU applies: pin on first contact.
  unknown,

  /// Presented key matches the pin exactly.
  match,

  /// Presented key differs. Requires explicit user action before trusting.
  changed,
}

/// A stored record of a peer's identity. `verified` is set only after the
/// user compares safety numbers out of band; it is reset on every key
/// change.
class IdentityPin {
  final String deviceId;
  final Uint8List ed25519Public;
  final Uint8List x25519Public;
  final int pinnedAt;

  /// True only after the user confirms the safety number in person.
  final bool verified;
  final int? verifiedAt;

  const IdentityPin({
    required this.deviceId,
    required this.ed25519Public,
    required this.x25519Public,
    required this.pinnedAt,
    required this.verified,
    this.verifiedAt,
  });

  IdentityPin copyWith({bool? verified, int? verifiedAt}) => IdentityPin(
        deviceId: deviceId,
        ed25519Public: ed25519Public,
        x25519Public: x25519Public,
        pinnedAt: pinnedAt,
        verified: verified ?? this.verified,
        verifiedAt: verifiedAt ?? this.verifiedAt,
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'ed': base64Encode(ed25519Public),
        'x': base64Encode(x25519Public),
        'pinned_at': pinnedAt,
        'verified': verified,
        if (verifiedAt != null) 'verified_at': verifiedAt,
      };

  /// Backwards-compatible with pins written before `verified` existed:
  /// missing fields default to unverified.
  static IdentityPin fromJson(Map<String, dynamic> j) => IdentityPin(
        deviceId: j['device_id'] as String,
        ed25519Public: base64Decode(j['ed'] as String),
        x25519Public: base64Decode(j['x'] as String),
        pinnedAt: j['pinned_at'] as int,
        verified: (j['verified'] as bool?) ?? false,
        verifiedAt: j['verified_at'] as int?,
      );
}