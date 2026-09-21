import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'storage_service.dart';

/// Primitives only. No protocol logic. Callers use these to build X3DH,
/// the Double Ratchet, sender keys, and the envelope signature.
///
/// Nonce safety: AES-GCM is catastrophically broken if a (key, nonce)
/// pair ever repeats. This class guarantees uniqueness across process
/// restarts by reserving counters in batches and persisting the batch
/// bound *before* any counter from that batch is used. Concurrent
/// encryption is serialized per keyId via [_withNonceLock].
class CryptoService {
  static final Ed25519 _ed = Ed25519();
  static final X25519 _x = X25519();
  static final AesGcm _gcm = AesGcm.with256bits();

  static const _noncePrefixBytes = 4;
  static const _counterBytes = 8;
  static const _counterReserve = 1000;

  final StorageService _storage;
  final Random _random = Random.secure();

  // Per-keyId serialization for nonce allocation. This is what makes
  // concurrent encryption safe.
  final Map<String, Future<void>> _nonceLocks = {};

  CryptoService(this._storage);

  // ─── Ed25519 ──────────────────────────────────────────────────────────

  Future<SimpleKeyPair> generateEd25519() => _ed.newKeyPair();

  Future<SimpleKeyPair> ed25519FromSeed(Uint8List seed) =>
      _ed.newKeyPairFromSeed(seed);

  Future<Uint8List> ed25519PublicBytes(SimpleKeyPair kp) async {
    final d = await kp.extract();
    return Uint8List.fromList(d.publicKey.bytes);
  }

  Future<Uint8List> signEd25519(SimpleKeyPair kp, List<int> message) async {
    final sig = await _ed.sign(message, keyPair: kp);
    return Uint8List.fromList(sig.bytes);
  }

  Future<bool> verifyEd25519(
    Uint8List publicKey,
    List<int> message,
    Uint8List signature,
  ) async {
    if (publicKey.length != 32 || signature.length != 64) return false;
    final pub = SimplePublicKey(publicKey, type: KeyPairType.ed25519);
    return _ed.verify(
      message,
      signature: Signature(signature, publicKey: pub),
    );
  }

  // ─── X25519 ───────────────────────────────────────────────────────────

  Future<SimpleKeyPair> generateX25519() => _x.newKeyPair();

  Future<SimpleKeyPair> x25519FromSeed(Uint8List seed) =>
      _x.newKeyPairFromSeed(seed);

  Future<Uint8List> x25519PublicBytes(SimpleKeyPair kp) async {
    final d = await kp.extract();
    return Uint8List.fromList(d.publicKey.bytes);
  }

  Future<SecretKey> x25519SharedSecret(
    SimpleKeyPair ours,
    Uint8List theirPublic,
  ) async {
    final their = SimplePublicKey(theirPublic, type: KeyPairType.x25519);
    return _x.sharedSecretKey(keyPair: ours, remotePublicKey: their);
  }

  /// Derives a 32-byte AES key from a shared secret and a context string.
  /// Not a general-purpose KDF; the shared secret is already uniform. The
  /// context string separates key uses.
  Future<SecretKey> deriveAesKey(SecretKey shared, String context) async {
    final raw = await shared.extractBytes();
    final digest = await Sha256().hash([...raw, ...utf8.encode(context)]);
    return SecretKey(digest.bytes);
  }

  // ─── AES-256-GCM ─────────────────────────────────────────────────────

  Future<EncryptedBox> encrypt(
    List<int> plaintext,
    SecretKey key, {
    required String keyId,
    required List<int> aad,
    Uint8List? nonce,
  }) async {
    final n = nonce ?? await nextNonceFor(keyId);
    final box = await _gcm.encrypt(
      plaintext,
      secretKey: key,
      nonce: n,
      aad: aad,
    );
    return EncryptedBox(
      nonce: Uint8List.fromList(n),
      ciphertext: Uint8List.fromList(box.cipherText),
      tag: Uint8List.fromList(box.mac.bytes),
    );
  }

  Future<Uint8List> decrypt(
    SecretKey key, {
    required Uint8List nonce,
    required Uint8List ciphertext,
    required Uint8List tag,
    required List<int> aad,
  }) async {
    final box = SecretBox(ciphertext, nonce: nonce, mac: Mac(tag));
    final clear = await _gcm.decrypt(box, secretKey: key, aad: aad);
    return Uint8List.fromList(clear);
  }

  // ─── Nonce allocation ────────────────────────────────────────────────

  /// Returns the next unused nonce for [keyId]. Serialized per keyId so
  /// two concurrent calls cannot read the same counter.
  Future<Uint8List> nextNonceFor(String keyId) =>
      _withNonceLock(keyId, () => _allocateNonce(keyId));

  Future<T> _withNonceLock<T>(String keyId, Future<T> Function() body) async {
    final prev = _nonceLocks[keyId] ?? Future<void>.value();
    final completer = Completer<void>();
    _nonceLocks[keyId] = completer.future;
    await prev;
    try {
      return await body();
    } finally {
      completer.complete();
      // Clean up if no one chained onto us.
      if (identical(_nonceLocks[keyId], completer.future)) {
        _nonceLocks.remove(keyId);
      }
    }
  }

  String _nonceFile(String keyId) =>
      'nonce.${_sanitize(keyId)}.json';

  Future<Uint8List> _allocateNonce(String keyId) async {
    final fname = _nonceFile(keyId);
    final raw = await _storage.read(fname);

    _CounterState state;
    if (raw == null) {
      state = _CounterState(
        prefix: _randomBytes(_noncePrefixBytes),
        next: 0,
        batchEnd: 0,
      );
    } else {
      state = _CounterState.fromJson(
        jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
      );
    }

    if (state.next >= state.batchEnd) {
      // Reserve the next batch and persist the new bound *before* using
      // any counter in it. A crash after this write and before the
      // counter is used is safe: the counter is simply skipped.
      state = state.withBatch(state.next + _counterReserve);
      await _storage.writeAtomic(
        fname,
        utf8.encode(jsonEncode(state.toJson())),
      );
    }

    final counter = state.next;
    final advanced = state.withNext(counter + 1);
    await _storage.writeAtomic(
      fname,
      utf8.encode(jsonEncode(advanced.toJson())),
    );

    final nonce = Uint8List(_noncePrefixBytes + _counterBytes);
    nonce.setRange(0, _noncePrefixBytes, state.prefix);
    ByteData.view(nonce.buffer)
        .setUint64(_noncePrefixBytes, counter, Endian.big);
    return nonce;
  }

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  String _sanitize(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

class EncryptedBox {
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List tag;

  const EncryptedBox({
    required this.nonce,
    required this.ciphertext,
    required this.tag,
  });
}

class _CounterState {
  final Uint8List prefix; // 4 bytes
  final int next;         // next counter to use
  final int batchEnd;     // exclusive upper bound of the reserved batch

  const _CounterState({
    required this.prefix,
    required this.next,
    required this.batchEnd,
  });

  _CounterState withNext(int n) =>
      _CounterState(prefix: prefix, next: n, batchEnd: batchEnd);

  _CounterState withBatch(int end) =>
      _CounterState(prefix: prefix, next: next, batchEnd: end);

  Map<String, dynamic> toJson() => {
        'prefix': base64Encode(prefix),
        'next': next,
        'batch_end': batchEnd,
      };

  factory _CounterState.fromJson(Map<String, dynamic> j) => _CounterState(
        prefix: base64Decode(j['prefix'] as String),
        next: j['next'] as int,
        batchEnd: j['batch_end'] as int,
      );
}