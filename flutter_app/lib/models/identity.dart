import 'dart:convert';
import 'dart:typed_data';

/// A device's long-lived identity: an Ed25519 signing key and an X25519
/// DH key. The `deviceId` is derived once at creation and never changes.
class DeviceIdentity {
  /// 16 hex chars = first 8 bytes of sha256(ed25519Public).
  final String deviceId;

  /// Raw 32-byte Ed25519 public key. Used to verify signatures.
  final Uint8List ed25519Public;

  /// Raw 32-byte X25519 public key. Used for ECDH.
  final Uint8List x25519Public;

  const DeviceIdentity({
    required this.deviceId,
    required this.ed25519Public,
    required this.x25519Public,
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'ed': _b64(ed25519Public),
        'x': _b64(x25519Public),
      };

  static DeviceIdentity fromJson(Map<String, dynamic> j) => DeviceIdentity(
        deviceId: j['device_id'] as String,
        ed25519Public: _b64d(j['ed'] as String),
        x25519Public: _b64d(j['x'] as String),
      );

  static String _b64(Uint8List b) => _base64.encode(b);
  static Uint8List _b64d(String s) => Uint8List.fromList(_base64.decode(s));
}

// Local aliases so this file has no package imports.
const _base64 = _Base64Codec();

class _Base64Codec {
  const _Base64Codec();
  String encode(List<int> b) => base64Encode(b);
  List<int> decode(String s) => base64Decode(s);
}