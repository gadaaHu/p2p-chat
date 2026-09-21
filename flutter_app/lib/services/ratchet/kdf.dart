import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Root-key KDF. Advances the root chain given a new DH output.
/// Uses HKDF-SHA256 with the DH output as salt. The root key is the IKM.
/// Output is split: first 32 bytes are the new root key, last 32 the
/// new chain key.
Future<(Uint8List, Uint8List)> kdfRootKey(
  Uint8List rootKey,
  Uint8List dhOutput,
) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
  final derived = await hkdf.deriveKey(
    secretKey: SecretKey(rootKey),
    nonce: dhOutput,
    info: _info('p2p_chat/v2/root'),
  );
  final out = Uint8List.fromList(await derived.extractBytes());
  return (out.sublist(0, 32), out.sublist(32, 64));
}

/// Chain-key KDF. Advances one step in a symmetric ratchet and emits a
/// message key. The constants 0x01 and 0x02 prevent key reuse between the
/// next chain step and the message key.
Future<(Uint8List, Uint8List)> kdfChainKey(Uint8List chainKey) async {
  final hmac = Hmac.sha256();
  final sk = SecretKey(chainKey);
  final nextMac = await hmac.calculateMac([1], secretKey: sk);
  final msgMac = await hmac.calculateMac([2], secretKey: sk);
  return (
    Uint8List.fromList(nextMac.bytes),
    Uint8List.fromList(msgMac.bytes),
  );
}

Uint8List _info(String s) => Uint8List.fromList(s.codeUnits);