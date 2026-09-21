import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'kdf.dart';

class DoubleRatchet {
  Uint8List? rootKey;
  Uint8List? sendChainKey;
  Uint8List? recvChainKey;
  
  SimpleKeyPair? DHs; // Our current ratchet key pair
  PublicKey? DHr; // Remote party's current ratchet public key

  int sendCount = 0;
  int recvCount = 0;
  
  // Skipped message keys for out-of-order delivery (reserved for future use)
  // ignore: unused_field
  final Map<String, Uint8List> _skippedMessageKeys = {};

  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();

  /// Initialize the ratchet as Alice (Sender)
  Future<void> ratchetInitAlice(Uint8List sharedSecret, PublicKey remoteRatchetKey) async {
    DHs = await _x25519.newKeyPair();
    DHr = remoteRatchetKey;
    
    // Perform initial DH Ratchet step to set up sending chain
    final dhOut = await _dh(DHs!, DHr!);
    final rootOutput = await _kdfRoot(sharedSecret, dhOut);
    
    rootKey = rootOutput['rootKey'];
    sendChainKey = rootOutput['chainKey'];
  }

  /// Initialize the ratchet as Bob (Receiver)
  Future<void> ratchetInitBob(Uint8List sharedSecret, SimpleKeyPair bobRatchetKey) async {
    DHs = bobRatchetKey;
    rootKey = sharedSecret;
    // recvChainKey and sendChainKey will be populated on first received message (DH step)
  }

  Future<Uint8List> _dh(SimpleKeyPair localPair, PublicKey remotePublic) async {
    final shared = await _x25519.sharedSecretKey(keyPair: localPair, remotePublicKey: remotePublic);
    final bytes = await shared.extractBytes();
    return Uint8List.fromList(bytes);
  }

  Future<Map<String, Uint8List>> _kdfRoot(Uint8List rk, Uint8List dhOut) async {
    // HKDF to derive next Root Key and Chain Key
    final ikm = BytesBuilder()..add(rk)..add(dhOut);
    final derived = await KDF.deriveKey(ikm: ikm.toBytes(), length: 64, info: 'RootKDF'.codeUnits);
    
    return {
      'rootKey': derived.sublist(0, 32),
      'chainKey': derived.sublist(32, 64),
    };
  }

  /// Perform a Diffie-Hellman Ratchet step
  Future<void> _dhRatchet(PublicKey headerDHr) async {
    DHr = headerDHr;

    // Step 1: Update receiving chain using the remote's new public key
    final dhRecv = await _dh(DHs!, DHr!);
    final recvOutput = await _kdfRoot(rootKey!, dhRecv);
    rootKey = recvOutput['rootKey'];
    recvChainKey = recvOutput['chainKey'];

    // Step 2: Generate a new sending key pair and update sending chain
    DHs = await _x25519.newKeyPair();
    final dhSend = await _dh(DHs!, DHr!);
    final sendOutput = await _kdfRoot(rootKey!, dhSend);
    rootKey = sendOutput['rootKey'];
    sendChainKey = sendOutput['chainKey'];

    sendCount = 0;
    recvCount = 0;
  }

  /// Encrypt a plaintext message
  Future<Map<String, dynamic>> encryptMessage(String plaintext) async {
    if (sendChainKey == null) {
      throw Exception("Cannot encrypt: sending chain key is null (DH Ratchet incomplete)");
    }

    // Step 1: Symmetric ratchet to get message key
    final kdfOutput = await KDF.ratchetKdf(sendChainKey!);
    final messageKey = kdfOutput['messageKey']!;
    sendChainKey = kdfOutput['nextChainKey'];

    // Step 2: Encrypt with AES-GCM
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(messageKey),
      nonce: nonce,
    );

    sendCount++;

    final publicBytes = await DHs!.extractPublicKey();

    return {
      'header': {
        'dh': base64Encode(publicBytes.bytes), // Send our current DH public key
        'n': sendCount - 1,
      },
      'ciphertext': base64Encode(secretBox.concatenation()),
    };
  }

  /// Decrypt a ciphertext message
  Future<String> decryptMessage(Map<String, dynamic> encryptedPacket) async {
    final header = encryptedPacket['header'];
    final remoteDhBase64 = header['dh'];
    final remoteDhBytes = base64Decode(remoteDhBase64);
    final headerDHr = SimplePublicKey(remoteDhBytes, type: KeyPairType.x25519);

    final ciphertext = base64Decode(encryptedPacket['ciphertext']);

    // Check if this is a new DH key from the sender
    bool isNewDh = false;
    if (DHr == null) {
      isNewDh = true;
    } else {
      final currentDhBytes = (DHr! as SimplePublicKey).bytes;
      if (base64Encode(currentDhBytes) != remoteDhBase64) {
        isNewDh = true;
      }
    }

    if (isNewDh) {
      // Ratchet forward!
      await _dhRatchet(headerDHr);
    }

    // Symmetric ratchet to get message key
    final kdfOutput = await KDF.ratchetKdf(recvChainKey!);
    final messageKey = kdfOutput['messageKey']!;
    recvChainKey = kdfOutput['nextChainKey'];
    
    recvCount++;

    // Decrypt
    final secretBox = SecretBox.fromConcatenation(
      ciphertext,
      nonceLength: _aesGcm.nonceLength,
      macLength: _aesGcm.macAlgorithm.macLength,
    );

    final cleartextBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: SecretKey(messageKey),
    );

    return utf8.decode(cleartextBytes);
  }
}
