import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class KDF {
  /// Derives one or more keys from input key material using HKDF (HMAC-SHA256).
  /// [ikm] is the input key material.
  /// [salt] is an optional salt value. If null, a 32-byte zero salt is used.
  /// [info] is an optional context and application specific information.
  /// [length] is the length of the derived keying material in bytes.
  static Future<Uint8List> deriveKey({
    required Uint8List ikm,
    Uint8List? salt,
    List<int>? info,
    int length = 32,
  }) async {
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: length,
    );

    final secretKey = SecretKey(ikm);
    
    // According to HKDF spec, if salt is not provided, it should be a string of zeros
    // However, package:cryptography's Hkdf allows an empty list to mean "no salt"
    // which operates correctly. We use an empty list instead of null if it's missing.
    final derivedKey = await hkdf.deriveKey(
      secretKey: secretKey,
      nonce: salt ?? Uint8List(32), // 32 bytes of zeros if no salt is provided
      info: info ?? [],
    );

    final bytes = await derivedKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// KDF for the symmetric ratchet. Derives a message key and the next chain key.
  static Future<Map<String, Uint8List>> ratchetKdf(Uint8List chainKey) async {
    final hmac = Hmac.sha256();
    
    // In standard Double Ratchet:
    // Message Key = HMAC-SHA256(chainKey, 0x01)
    // Next Chain Key = HMAC-SHA256(chainKey, 0x02)
    
    final mkMac = await hmac.calculateMac(
      [0x01],
      secretKey: SecretKey(chainKey),
    );
    
    final ckMac = await hmac.calculateMac(
      [0x02],
      secretKey: SecretKey(chainKey),
    );
    
    return {
      'messageKey': Uint8List.fromList(mkMac.bytes),
      'nextChainKey': Uint8List.fromList(ckMac.bytes),
    };
  }
}
