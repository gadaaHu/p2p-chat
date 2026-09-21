import 'dart:convert';
import 'dart:typed_data';

/// A peer the user has paired with. The cryptographic material is a
/// snapshot taken at pairing time; the live authoritative keys live in
/// `PinningPolicy`. `Contact` is for display and lookup.
class Contact {
  final String deviceId;
  final String displayName;
  final Uint8List ed25519Public;
  final Uint8List x25519Public;
  final int addedAt;
  final String? notes;

  const Contact({
    required this.deviceId,
    required this.displayName,
    required this.ed25519Public,
    required this.x25519Public,
    required this.addedAt,
    this.notes,
  });

  Contact copyWith({String? displayName, String? notes}) => Contact(
        deviceId: deviceId,
        displayName: displayName ?? this.displayName,
        ed25519Public: ed25519Public,
        x25519Public: x25519Public,
        addedAt: addedAt,
        notes: notes ?? this.notes,
      );

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'name': displayName,
        'ed': base64Encode(ed25519Public),
        'x': base64Encode(x25519Public),
        'added_at': addedAt,
        if (notes != null) 'notes': notes,
      };

  static Contact fromJson(Map<String, dynamic> j) => Contact(
        deviceId: j['device_id'] as String,
        displayName: j['name'] as String,
        ed25519Public: base64Decode(j['ed'] as String),
        x25519Public: base64Decode(j['x'] as String),
        addedAt: j['added_at'] as int,
        notes: j['notes'] as String?,
      );
}