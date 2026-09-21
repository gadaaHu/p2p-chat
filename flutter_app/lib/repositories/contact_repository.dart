
import '../models/contact.dart';

/// Thin facade over `PeerRegistry`. Kept for symmetry with the other
/// repositories and to give the UI a place to ask "do I know this peer?"
class ContactRepository {
  final PeerRegistryRef _registry;

  ContactRepository(this._registry);

  Future<List<Contact>> all() async => _registry.all();
  Contact? byId(String deviceId) => _registry.byId(deviceId);
  bool contains(String deviceId) => _registry.contains(deviceId);

  Future<void> add({
    required String deviceId,
    required String displayName,
    required List<int> ed25519Public,
    required List<int> x25519Public,
  }) =>
      _registry.upsert(
        deviceId: deviceId,
        displayName: displayName,
        ed25519Public: ed25519Public,
        x25519Public: x25519Public,
      );

  Future<void> rename(String deviceId, String newName) =>
      _registry.rename(deviceId, newName);

  Future<void> remove(String deviceId) => _registry.remove(deviceId);
}

/// Narrow interface so the repository doesn't import PeerRegistry's
/// concrete class (which pulls in the pinning policy and storage).
abstract class PeerRegistryRef {
  List<Contact> all();
  Contact? byId(String deviceId);
  bool contains(String deviceId);
  Future<void> upsert({
    required String deviceId,
    required String displayName,
    required List<int> ed25519Public,
    required List<int> x25519Public,
  });
  Future<void> rename(String deviceId, String newName);
  Future<void> remove(String deviceId);
}