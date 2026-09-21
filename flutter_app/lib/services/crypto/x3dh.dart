import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'kdf.dart';

class X3DH {
  static final _algorithm = X25519();

  /// Perform a Diffie-Hellman key exchange between a local private key and a remote public key
  static Future<Uint8List> _dh(SimpleKeyPair localKeyPair, PublicKey remotePublicKey) async {
    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );
    final bytes = await sharedSecret.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Calculates the shared secret as Alice (the sender)
  /// Uses Alice's Identity Key (IKa) and Ephemeral Key (EKa)
  /// Uses Bob's Identity Key (IKb), Signed PreKey (SPKb), and One-Time PreKey (OPKb) (optional)
  static Future<Uint8List> calculateAliceSharedSecret({
    required SimpleKeyPair IKa,
    required SimpleKeyPair EKa,
    required PublicKey IKb,
    required PublicKey SPKb,
    PublicKey? OPKb,
  }) async {
    // DH1 = DH(IKa, SPKb)
    final dh1 = await _dh(IKa, SPKb);
    
    // DH2 = DH(EKa, IKb)
    final dh2 = await _dh(EKa, IKb);
    
    // DH3 = DH(EKa, SPKb)
    final dh3 = await _dh(EKa, SPKb);

    final bytesBuilder = BytesBuilder();
    // Prepend 32 bytes of 0xFF (F) as required by Signal spec
    bytesBuilder.add(List.filled(32, 0xFF));
    bytesBuilder.add(dh1);
    bytesBuilder.add(dh2);
    bytesBuilder.add(dh3);

    // DH4 = DH(EKa, OPKb) if one-time prekey is available
    if (OPKb != null) {
      final dh4 = await _dh(EKa, OPKb);
      bytesBuilder.add(dh4);
    }

    final ikm = bytesBuilder.toBytes();

    // Derive 32-byte shared secret using HKDF
    return await KDF.deriveKey(
      ikm: ikm,
      info: 'X3DH'.codeUnits,
      length: 32,
    );
  }

  /// Calculates the shared secret as Bob (the receiver)
  /// Uses Bob's Identity Key (IKb), Signed PreKey (SPKb), and One-Time PreKey (OPKb) (optional)
  /// Uses Alice's Identity Key (IKa) and Ephemeral Key (EKa)
  static Future<Uint8List> calculateBobSharedSecret({
    required SimpleKeyPair IKb,
    required SimpleKeyPair SPKb,
    SimpleKeyPair? OPKb,
    required PublicKey IKa,
    required PublicKey EKa,
  }) async {
    // Note the order swap from Alice's perspective
    // DH1 = DH(SPKb, IKa)
    final dh1 = await _dh(SPKb, IKa);
    
    // DH2 = DH(IKb, EKa)
    final dh2 = await _dh(IKb, EKa);
    
    // DH3 = DH(SPKb, EKa)
    final dh3 = await _dh(SPKb, EKa);

    final bytesBuilder = BytesBuilder();
    bytesBuilder.add(List.filled(32, 0xFF));
    bytesBuilder.add(dh1);
    bytesBuilder.add(dh2);
    bytesBuilder.add(dh3);

    // DH4 = DH(OPKb, EKa) if one-time prekey was used
    if (OPKb != null) {
      final dh4 = await _dh(OPKb, EKa);
      bytesBuilder.add(dh4);
    }

    final ikm = bytesBuilder.toBytes();

    // Derive 32-byte shared secret using HKDF
    return await KDF.deriveKey(
      ikm: ikm,
      info: 'X3DH'.codeUnits,
      length: 32,
    );
  }
}
