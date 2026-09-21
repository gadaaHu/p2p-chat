import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto_service.dart';
import 'identity_service.dart';
import 'storage_service.dart';
import 'x3dh.dart';

/// Manages this device's prekey material: one active signed prekey plus
/// a pool of one-time prekeys. There is no server, so bundles are
/// exchanged through the pairing QR.
class PreKeyService {
  static const _file = 'prekeys.json';
  static const _spkRotateDays = 7;
  static const _batchSize = 100;
  static const _replenishThreshold = 20;
  static const _keepSpkVersions = 3;

  final StorageService _storage;
  final IdentityService _identity;
  final CryptoService _crypto;

  bool _loaded = false;
  int _nextSpkId = 1;
  final Map<int, SimpleKeyPair> _spks = {};
  int _nextOpkId = 1;
  final Map<int, SimpleKeyPair> _opks = {};
  int _lastSpkRotationMs = 0;

  PreKeyService({
    required StorageService storage,
    required IdentityService identity,
    required CryptoService crypto,
  })  : _storage = storage,
        _identity = identity,
        _crypto = crypto;

  Future<void> loadOrGenerate() async {
    if (_loaded) return;

    final raw = await _storage.read(_file);
    if (raw != null) {
      final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      _nextSpkId = j['next_spk_id'] as int;
      _nextOpkId = j['next_opk_id'] as int;
      _lastSpkRotationMs = j['last_spk_rotation_ms'] as int;
      for (final e in (j['spks'] as List).cast<Map<String, dynamic>>()) {
        _spks[e['id'] as int] = await _crypto.x25519FromSeed(
          base64Decode(e['seed'] as String),
        );
      }
      for (final e in (j['opks'] as List).cast<Map<String, dynamic>>()) {
        _opks[e['id'] as int] = await _crypto.x25519FromSeed(
          base64Decode(e['seed'] as String),
        );
      }
    }

    final age = DateTime.now().millisecondsSinceEpoch - _lastSpkRotationMs;
    final needRotation =
        _spks.isEmpty || age > _spkRotateDays * 24 * 3600 * 1000;
    if (needRotation) {
      final kp = await _crypto.generateX25519();
      _spks[_nextSpkId] = kp;
      _nextSpkId++;
      _lastSpkRotationMs = DateTime.now().millisecondsSinceEpoch;
      final ids = _spks.keys.toList()..sort();
      while (ids.length > _keepSpkVersions) {
        _spks.remove(ids.removeAt(0));
      }
    }

    if (_opks.length < _replenishThreshold) {
      await _generateOpks(_batchSize - _opks.length);
    }

    _loaded = true;
    await _persist();
  }

  Future<void> _generateOpks(int count) async {
    for (var i = 0; i < count; i++) {
      _opks[_nextOpkId] = await _crypto.generateX25519();
      _nextOpkId++;
    }
  }

  Future<void> _persist() async {
    final spks = <Map<String, dynamic>>[];
    for (final e in _spks.entries) {
      final d = await e.value.extract();
      spks.add({'id': e.key, 'seed': base64Encode(d.bytes)});
    }
    final opks = <Map<String, dynamic>>[];
    for (final e in _opks.entries) {
      final d = await e.value.extract();
      opks.add({'id': e.key, 'seed': base64Encode(d.bytes)});
    }
    await _storage.writeAtomic(
      _file,
      utf8.encode(jsonEncode({
        'next_spk_id': _nextSpkId,
        'next_opk_id': _nextOpkId,
        'last_spk_rotation_ms': _lastSpkRotationMs,
        'spks': spks,
        'opks': opks,
      })),
    );
  }

  /// Builds a bundle for this device containing the newest SPK and one
  /// fresh OPK. The OPK is removed from the pool — an OPK is used at most
  /// once.
  Future<PreKeyBundle> exportBundle() async {
    await loadOrGenerate();
    final spkId = _spks.keys.reduce(max);
    final spk = _spks[spkId]!;
    final spkData = await spk.extract();
    final spkPub = Uint8List.fromList(
      spkData.publicKey.bytes,
    );
    final spkPubB64 = base64Encode(spkPub);
    final spkSig = await _crypto.signEd25519(
      _identity.ed25519KeyPair,
      utf8.encode('spk:$spkPubB64'),
    );

    // Pick the lowest-id remaining OPK.
    final opkId = _opks.isEmpty ? null : (_opks.keys.toList()..sort()).first;
    Uint8List? opkPub;
    if (opkId != null) {
      final d = await _opks[opkId]!.extract();
      opkPub = Uint8List.fromList(d.publicKey.bytes);
    }

    return PreKeyBundle(
      deviceId: _identity.identity.deviceId,
      identityEd25519: _identity.identity.ed25519Public,
      identityX25519: _identity.identity.x25519Public,
      spkId: spkId,
      spkPublic: spkPub,
      spkSignature: spkSig,
      opkId: opkId,
      opkPublic: opkPub,
    );
  }

  /// Verifies the SPK signature in [bundle] against the given identity
  /// Ed25519 key. Returns false if anything is malformed.
  Future<bool> verifyBundle(
    PreKeyBundle bundle,
    Uint8List ed25519Public,
  ) async {
    return _crypto.verifyEd25519(
      ed25519Public,
      utf8.encode('spk:${base64Encode(bundle.spkPublic)}'),
      bundle.spkSignature,
    );
  }

  /// Returns the SPK key pair with the given id, or null if it has been
  /// rotated out. A null return means the initiator used an SPK we no
  /// longer hold; the session cannot be established.
  Future<SimpleKeyPair?> spkById(int id) async {
    await loadOrGenerate();
    return _spks[id];
  }

  /// Removes and returns the OPK with the given id. Null if already
  /// consumed or unknown. Idempotent from the caller's perspective.
  Future<SimpleKeyPair?> takeOpkById(int id) async {
    await loadOrGenerate();
    final kp = _opks.remove(id);
    if (kp != null) await _persist();
    return kp;
  }
}