import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();

  static const _keyIdentityKey = 'identity_key_private';
  static const _keyIdentityKeyPub = 'identity_key_public';

  /// Save the user's permanent Identity Keypair securely
  static Future<void> saveIdentityKeyPair(List<int> privateKey, List<int> publicKey) async {
    await _storage.write(key: _keyIdentityKey, value: base64Encode(privateKey));
    await _storage.write(key: _keyIdentityKeyPub, value: base64Encode(publicKey));
  }

  /// Retrieve the user's Identity Keypair
  static Future<Map<String, List<int>>?> getIdentityKeyPair() async {
    final privBase64 = await _storage.read(key: _keyIdentityKey);
    final pubBase64 = await _storage.read(key: _keyIdentityKeyPub);

    if (privBase64 != null && pubBase64 != null) {
      return {
        'private': base64Decode(privBase64),
        'public': base64Decode(pubBase64),
      };
    }
    return null;
  }

  /// Save Ratchet State for a specific peer
  static Future<void> saveRatchetState(String peerUsername, Map<String, dynamic> state) async {
    await _storage.write(
      key: 'ratchet_state_\$peerUsername',
      value: jsonEncode(state),
    );
  }

  /// Retrieve Ratchet State for a specific peer
  static Future<Map<String, dynamic>?> getRatchetState(String peerUsername) async {
    final stateStr = await _storage.read(key: 'ratchet_state_\$peerUsername');
    if (stateStr != null) {
      return jsonDecode(stateStr);
    }
    return null;
  }

  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
