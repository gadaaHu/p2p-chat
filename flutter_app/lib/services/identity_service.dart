import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as c;

import '../models/identity.dart';
import 'crypto_service.dart';
import 'storage_service.dart';

/// Owns the device's long-lived identity keys. Generates on first run,
/// loads on subsequent runs. Never derives session keys — that is the
/// ratchet's job.
class IdentityService {
  static const _identityFile = 'identity.json';

  final StorageService _storage;
  final CryptoService _crypto;

  SimpleKeyPair? _ed;
  SimpleKeyPair? _x;
  DeviceIdentity? _identity;

  IdentityService(this._storage, this._crypto);

  DeviceIdentity get identity {
    final i = _identity;
    if (i == null) throw StateError('IdentityService not initialized');
    return i;
  }

  SimpleKeyPair get ed25519KeyPair {
    final k = _ed;
    if (k == null) throw StateError('IdentityService not initialized');
    return k;
  }

  SimpleKeyPair get x25519KeyPair {
    final k = _x;
    if (k == null) throw StateError('IdentityService not initialized');
    return k;
  }

  bool get isInitialized => _identity != null;

  Future<DeviceIdentity> loadOrCreate() async {
    if (_identity != null) return _identity!;

    final raw = await _storage.read(_identityFile);
    if (raw != null) {
      final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      _ed = await _crypto.ed25519FromSeed(
        base64Decode(j['ed_seed'] as String),
      );
      _x = await _crypto.x25519FromSeed(
        base64Decode(j['x_seed'] as String),
      );
      _identity = DeviceIdentity(
        deviceId: j['device_id'] as String,
        ed25519Public: base64Decode(j['ed_pub'] as String),
        x25519Public: base64Decode(j['x_pub'] as String),
      );
      return _identity!;
    }

    return _createFresh();
  }

  Future<DeviceIdentity> _createFresh() async {
    final ed = await _crypto.generateEd25519();
    final x = await _crypto.generateX25519();
    final edData = await ed.extract();
    final xData = await x.extract();
    final edPub = Uint8List.fromList(edData.publicKey.bytes);
    final xPub = Uint8List.fromList(xData.publicKey.bytes);

    // deviceId: first 16 hex chars of sha256(Ed25519 public).
    final digest = c.sha256.convert(edPub).toString();
    final deviceId = digest.substring(0, 16);

    await _storage.writeAtomic(
      _identityFile,
      utf8.encode(jsonEncode({
        'device_id': deviceId,
        'ed_seed': base64Encode(edData.bytes),
        'x_seed': base64Encode(xData.bytes),
        'ed_pub': base64Encode(edPub),
        'x_pub': base64Encode(xPub),
      })),
    );

    _ed = ed;
    _x = x;
    _identity = DeviceIdentity(
      deviceId: deviceId,
      ed25519Public: edPub,
      x25519Public: xPub,
    );
    return _identity!;
  }

  /// Signs an arbitrary byte string with the identity Ed25519 key.
  /// Used to sign identity handshake frames and sender key distributions.
  Future<Uint8List> sign(List<int> message) =>
      _crypto.signEd25519(ed25519KeyPair, message);

  /// Verifies a signature against an explicit Ed25519 public key. Does
  /// not consult the pin store; the caller decides which key to trust.
  Future<bool> verify(
    Uint8List ed25519Public,
    List<int> message,
    Uint8List signature,
  ) =>
      _crypto.verifyEd25519(ed25519Public, message, signature);

  /// Wipes the identity and all derived state. Only used by tests and by
  /// a future "reset device" action. Callers must also clear pins,
  /// ratchets, and queues.
  Future<void> reset() async {
    await _storage.delete(_identityFile);
    _ed = null;
    _x = null;
    _identity = null;
  }
}