import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'kdf.dart';
import 'session_state.dart';

/// Maximum number of messages a receiving chain may skip before we refuse.
/// Bounds memory and prevents a malicious sender from forcing unbounded
/// key derivation.
const maxSkip = 1000;

class DoubleRatchet {
  final Future<SimpleKeyPair> Function() _generateKeyPair;
  final Future<Uint8List> Function(Uint8List priv, Uint8List pub) _x25519;

  DoubleRatchet({
    required Future<SimpleKeyPair> Function() generateKeyPair,
    required Future<Uint8List> Function(Uint8List priv, Uint8List pub) x25519,
  })  : _generateKeyPair = generateKeyPair,
        _x25519 = x25519;

  /// Initializes a session as the initiator. [initialSecret] is the shared
  /// secret from X25519 identity ECDH. [remoteIdentityDhPublic] is the
  /// peer's X25519 identity public key.
  Future<RatchetSession> initAlice({
    required Uint8List initialSecret,
    required Uint8List remoteIdentityDhPublic,
    required SimpleKeyPair ourNewDhKeyPair,
  }) async {
    final ourData = await ourNewDhKeyPair.extract();
    final priv = Uint8List.fromList(ourData.bytes);
    final pub = Uint8List.fromList(ourData.publicKey.bytes);
    final dh = await _x25519(priv, remoteIdentityDhPublic);
    final (rk, cks) = await kdfRootKey(initialSecret, dh);
    return RatchetSession(
      dhSelfPrivate: priv,
      dhSelfPublic: pub,
      dhRemote: remoteIdentityDhPublic,
      rootKey: rk,
      chainKeySend: cks,
      chainKeyRecv: null,
      nSend: 0,
      nRecv: 0,
      pn: 0,
      skipped: {},
      skippedOrder: [],
    );
  }

  /// Initializes a session as the responder. Our DH key pair is the
  /// X25519 identity key — this is what makes the first message decryptable.
  Future<RatchetSession> initBob({
    required Uint8List initialSecret,
    required SimpleKeyPair ourIdentityDhKeyPair,
  }) async {
    final data = await ourIdentityDhKeyPair.extract();
    return RatchetSession(
      dhSelfPrivate: Uint8List.fromList(data.bytes),
      dhSelfPublic: Uint8List.fromList(
        data.publicKey.bytes,
      ),
      dhRemote: null,
      rootKey: initialSecret,
      chainKeySend: null,
      chainKeyRecv: null,
      nSend: 0,
      nRecv: 0,
      pn: 0,
      skipped: {},
      skippedOrder: [],
    );
  }

  // ─── Send ─────────────────────────────────────────────────────────────

  /// Advances the sending chain and returns the message key plus the
  /// ratchet header to attach to the ciphertext.
  Future<({RatchetSession next, Uint8List messageKey, RatchetHeader header})>
      encrypt(RatchetSession s) async {
    final cks = s.chainKeySend;
    if (cks == null) {
      throw StateError('sending chain not initialized');
    }
    final (nextCk, mk) = await kdfChainKey(cks);
    final header = RatchetHeader(
      dh: s.dhSelfPublic,
      n: s.nSend,
      pn: s.pn,
    );
    final next = s.copyWith(
      chainKeySend: nextCk,
      nSend: s.nSend + 1,
    );
    return (next: next, messageKey: mk, header: header);
  }

  // ─── Receive ──────────────────────────────────────────────────────────

  /// Decrypts using the receiving chain, advancing the DH ratchet if the
  /// header carries a new DH public key.
  Future<({RatchetSession next, Uint8List messageKey})> decrypt(
    RatchetSession s,
    RatchetHeader header,
  ) async {
    // 1. Skipped-message keys: an out-of-order message we saved earlier.
    final cached = s.skipped['${_b64(header.dh)}|${header.n}'];
    if (cached != null) {
      final updated = _removeSkipped(s, cached.id);
      return (next: updated, messageKey: cached.messageKey);
    }

    // 2. New DH public key: they've ratcheted. Skip stale messages on the
    // old chain, then perform the DH ratchet.
    var cur = s;
    if (cur.dhRemote == null ||
        !_bytesEq(cur.dhRemote!, header.dh)) {
      cur = await _skipMessageKeys(cur, header.pn);
      cur = await _dhRatchet(cur, header.dh);
    }

    // 3. Advance the receiving chain to header.n.
    cur = await _skipMessageKeys(cur, header.n);

    // 4. The next chain step yields the message key.
    final ckr = cur.chainKeyRecv;
    if (ckr == null) throw StateError('receiving chain not initialized');
    final (nextCk, mk) = await kdfChainKey(ckr);
    final next = cur.copyWith(
      chainKeyRecv: nextCk,
      nRecv: cur.nRecv + 1,
    );
    return (next: next, messageKey: mk);
  }

  // ─── Internals ────────────────────────────────────────────────────────

  Future<RatchetSession> _dhRatchet(
    RatchetSession s,
    Uint8List theirNewDh,
  ) async {
    // Transition the old sending chain length into pn.
    final newPn = s.nSend;

    // First half: derive the receiving chain from their new DH.
    final dhRecv = await _x25519(s.dhSelfPrivate, theirNewDh);
    final (rk1, ckr) = await kdfRootKey(s.rootKey, dhRecv);

    // Second half: generate our new DH pair, derive the sending chain.
    final newKp = await _generateKeyPair();
    final newData = await newKp.extract();
    final newPriv = Uint8List.fromList(newData.bytes);
    final newPub = Uint8List.fromList(
      newData.publicKey.bytes,
    );
    final dhSend = await _x25519(newPriv, theirNewDh);
    final (rk2, cks) = await kdfRootKey(rk1, dhSend);

    return s.copyWith(
      dhRemote: theirNewDh,
      dhSelfPrivate: newPriv,
      dhSelfPublic: newPub,
      rootKey: rk2,
      chainKeySend: cks,
      chainKeyRecv: ckr,
      nSend: 0,
      nRecv: 0,
      pn: newPn,
    );
  }

  Future<RatchetSession> _skipMessageKeys(
    RatchetSession s,
    int until,
  ) async {
    final ckr = s.chainKeyRecv;
    if (ckr == null) return s;
    if (s.nRecv + maxSkip < until) {
      throw StateError(
        'too many skipped messages: ${until - s.nRecv} > $maxSkip',
      );
    }
    var cur = s;
    var ck = ckr;
    var n = s.nRecv;
    final skipped = Map<String, SkippedKey>.from(cur.skipped);
    final order = List<String>.from(cur.skippedOrder);
    while (n < until) {
      final (nextCk, mk) = await kdfChainKey(ck);
      final dhRemote = cur.dhRemote!;
      final entry = SkippedKey(
        dhPublic: dhRemote,
        n: n,
        messageKey: mk,
      );
      skipped[entry.id] = entry;
      order.add(entry.id);
      while (order.length > RatchetSession.maxSkipped) {
        final evicted = order.removeAt(0);
        skipped.remove(evicted);
      }
      ck = nextCk;
      n++;
    }
    return cur.copyWith(
      chainKeyRecv: ck,
      nRecv: n,
      skipped: skipped,
      skippedOrder: order,
    );
  }

  RatchetSession _removeSkipped(RatchetSession s, String id) {
    final skipped = Map<String, SkippedKey>.from(s.skipped)..remove(id);
    final order = List<String>.from(s.skippedOrder)..remove(id);
    return s.copyWith(skipped: skipped, skippedOrder: order);
  }

  bool _bytesEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  String _b64(Uint8List b) => base64Encode(b);
}

class RatchetHeader {
  final Uint8List dh;
  final int n;
  final int pn;

  const RatchetHeader({
    required this.dh,
    required this.n,
    required this.pn,
  });

  Map<String, dynamic> toJson() => {
        'dh': base64Encode(dh),
        'n': n,
        'pn': pn,
      };

  static RatchetHeader fromJson(Map<String, dynamic> j) => RatchetHeader(
        dh: base64Decode(j['dh'] as String),
        n: j['n'] as int,
        pn: j['pn'] as int,
      );
}