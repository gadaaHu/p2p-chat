import 'package:cryptography/cryptography.dart';
import 'ratchet/ratchet_store.dart';

/// Manages per-session symmetric encryption keys derived from the ratchet.
/// Provides the `sessionKey` method required by ReceiptService.
class KeyExchangeService {
  final RatchetStore _ratchets;

  KeyExchangeService(this._ratchets);

  /// Returns the current session secret key for the given peer device.
  Future<SecretKey> sessionKey(String peerDeviceId) async {
    final session = _ratchets.byPeer(peerDeviceId);
    if (session == null) {
      throw StateError('No ratchet session for peer $peerDeviceId');
    }
    // Return the current sending chain key as the session key
    final keyBytes = session.chainKeySend ?? session.rootKey;
    return SecretKey(keyBytes);
  }
}
