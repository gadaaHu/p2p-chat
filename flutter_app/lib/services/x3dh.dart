import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// X3DH per the Signal spec, adapted to use separate Ed25519 and X25519
/// identity keys. The Ed25519 key is the long-term identity; the X25519
/// key is the DH identity.
class X3dh {
  X3dh._();

  static final _x = X25519();
  static final _f = Uint8List.fromList(List.filled(32, 0xFF));
  static final _info = Uint8List.fromList('p2p_chat/x3dh/v1'.codeUnits);

  /// Initiator side. Returns the shared secret and the ephemeral public
  /// key that must be transmitted in the prekey block.
  static Future<X3dhInitResult> initiator({
    required SimpleKeyPair aliceIdentityX,
    required Uint8List bobIdentityX,
    required Uint8List bobSpkPublic,
    required Uint8List? bobOpkPublic,
  }) async {
    final ek = await _x.newKeyPair();
    final ekData = await ek.extract();
    final ekPublic = Uint8List.fromList(
      ekData.publicKey.bytes,
    );

    final dh1 = await _dh(aliceIdentityX, bobSpkPublic);
    final dh2 = await _dh(ek, bobIdentityX);
    final dh3 = await _dh(ek, bobSpkPublic);
    final dh4 = bobOpkPublic == null ? null : await _dh(ek, bobOpkPublic);

    final sk = await _kdf([dh1, dh2, dh3, if (dh4 != null) dh4]);
    return X3dhInitResult(sk: sk, ekPublic: ekPublic);
  }

  /// Responder side. Reconstructs the same secret from transmitted
  /// values. The SPK and OPK private keys are selected by the caller
  /// based on the ids in the initiator's prekey block.
  static Future<Uint8List> responder({
    required SimpleKeyPair bobIdentityX,
    required SimpleKeyPair bobSpkPrivate,
    required SimpleKeyPair? bobOpkPrivate,
    required Uint8List aliceIdentityX,
    required Uint8List aliceEkPublic,
  }) async {
    final dh1 = await _dh(bobSpkPrivate, aliceIdentityX);
    final dh2 = await _dh(bobIdentityX, aliceEkPublic);
    final dh3 = await _dh(bobSpkPrivate, aliceEkPublic);
    final dh4 =
        bobOpkPrivate == null ? null : await _dh(bobOpkPrivate, aliceEkPublic);

    return _kdf([dh1, dh2, dh3, if (dh4 != null) dh4]);
  }

  static Future<Uint8List> _dh(
    SimpleKeyPair ourPrivate,
    Uint8List theirPublic,
  ) async {
    final shared = await _x.sharedSecretKey(
      keyPair: ourPrivate,
      remotePublicKey: SimplePublicKey(
        theirPublic,
        type: KeyPairType.x25519,
      ),
    );
    return Uint8List.fromList(await shared.extractBytes());
  }

  static Future<Uint8List> _kdf(List<Uint8List> dhs) async {
    final b = BytesBuilder()..add(_f);
    for (final dh in dhs) {
      b.add(dh);
    }
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final out = await hkdf.deriveKey(
      secretKey: SecretKey(b.toBytes()),
      nonce: const [],
      info: _info,
    );
    return Uint8List.fromList(await out.extractBytes());
  }
}

class X3dhInitResult {
  final Uint8List sk;
  final Uint8List ekPublic;

  const X3dhInitResult({required this.sk, required this.ekPublic});
}

/// The X3DH header transmitted with the initiator's first message.
class PreKeyHeader {
  final Uint8List identityX;
  final Uint8List ephemeralX;
  final int spkId;
  final int? opkId;

  const PreKeyHeader({
    required this.identityX,
    required this.ephemeralX,
    required this.spkId,
    this.opkId,
  });

  Map<String, dynamic> toJson() => {
        'ik': base64Encode(identityX),
        'ek': base64Encode(ephemeralX),
        'spk_id': spkId,
        if (opkId != null) 'opk_id': opkId,
      };

  static PreKeyHeader fromJson(Map<String, dynamic> j) => PreKeyHeader(
        identityX: base64Decode(j['ik'] as String),
        ephemeralX: base64Decode(j['ek'] as String),
        spkId: j['spk_id'] as int,
        opkId: j['opk_id'] as int?,
      );
}

/// A peer's prekey bundle, as it appears in a pairing QR.
class PreKeyBundle {
  final String deviceId;
  final Uint8List identityEd25519;
  final Uint8List identityX25519;
  final int spkId;
  final Uint8List spkPublic;
  final Uint8List spkSignature;
  final int? opkId;
  final Uint8List? opkPublic;

  const PreKeyBundle({
    required this.deviceId,
    required this.identityEd25519,
    required this.identityX25519,
    required this.spkId,
    required this.spkPublic,
    required this.spkSignature,
    this.opkId,
    this.opkPublic,
  });

  /// Compact, QR-friendly encoding.
  String encode() => 'p2pb:${base64Url.encode(utf8.encode(jsonEncode(toJson()))).replaceAll('=', '')}';

  static PreKeyBundle? tryDecode(String s) {
    final trimmed = s.trim();
    if (!trimmed.startsWith('p2pb:')) return null;
    try {
      final raw = trimmed.substring(5);
      final padded = raw + ('=' * ((4 - raw.length % 4) % 4));
      final j = jsonDecode(utf8.decode(base64Url.decode(padded)))
          as Map<String, dynamic>;
      return PreKeyBundle.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'ed': base64Encode(identityEd25519),
        'x': base64Encode(identityX25519),
        'spk_id': spkId,
        'spk': base64Encode(spkPublic),
        'spk_sig': base64Encode(spkSignature),
        if (opkId != null) 'opk_id': opkId,
        if (opkPublic != null) 'opk': base64Encode(opkPublic!),
      };

  static PreKeyBundle fromJson(Map<String, dynamic> j) => PreKeyBundle(
        deviceId: j['device_id'] as String,
        identityEd25519: base64Decode(j['ed'] as String),
        identityX25519: base64Decode(j['x'] as String),
        spkId: j['spk_id'] as int,
        spkPublic: base64Decode(j['spk'] as String),
        spkSignature: base64Decode(j['spk_sig'] as String),
        opkId: j['opk_id'] as int?,
        opkPublic:
            j['opk'] == null ? null : base64Decode(j['opk'] as String),
      );
}