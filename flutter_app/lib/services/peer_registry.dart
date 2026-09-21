import 'dart:convert';
import 'dart:typed_data';

import '../models/contact.dart';
import 'pinning_policy.dart';
import 'storage_service.dart';

/// Replaces the server directory. Everything the app knows about a peer
/// lives here: the display name, the pinned identity, and the display
/// metadata. All state is local.
///
/// The registry does not own key material for sessions — those live in
/// the ratchet store. It owns the *identity* of the peer.
class PeerRegistry {
  static const _file = 'peers.json';

  final StorageService _storage;
  final PinningPolicy _pins;
  final Map<String, Contact> _peers = {};
  bool _loaded = false;

  PeerRegistry(this._storage, this._pins);

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.read(_file);
    if (raw != null) {
      final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      j.forEach((id, v) {
        _peers[id] = Contact.fromJson(v as Map<String, dynamic>);
      });
    }
    _loaded = true;
  }

  List<Contact> all() {
    final list = _peers.values.toList();
    list.sort((a, b) => a.displayName
        .toLowerCase()
        .compareTo(b.displayName.toLowerCase()));
    return list;
  }

  Contact? byId(String deviceId) => _peers[deviceId];

  bool contains(String deviceId) => _peers.containsKey(deviceId);

  /// Adds or updates a peer. Also pins the identity if no pin exists.
  /// Callers should have already evaluated the pin state; this method
  /// only creates the record.
  Future<void> upsert({
    required String deviceId,
    required String displayName,
    required List<int> ed25519Public,
    required List<int> x25519Public,
  }) async {
    await load();
    final existing = _peers[deviceId];
    final contact = Contact(
      deviceId: deviceId,
      displayName: displayName,
      ed25519Public: existing?.ed25519Public ??
          Uint8ListFrom(ed25519Public),
      x25519Public: existing?.x25519Public ?? Uint8ListFrom(x25519Public),
      addedAt:
          existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
      notes: existing?.notes,
    );
    _peers[deviceId] = contact;

    if (await _pins.pinFor(deviceId) == null) {
      await _pins.pin(
        deviceId: deviceId,
        ed25519Public: ed25519Public,
        x25519Public: x25519Public,
      );
    }
    await _persist();
  }

  Future<void> rename(String deviceId, String newName) async {
    await load();
    final existing = _peers[deviceId];
    if (existing == null) return;
    _peers[deviceId] = existing.copyWith(displayName: newName);
    await _persist();
  }

  Future<void> remove(String deviceId) async {
    await load();
    _peers.remove(deviceId);
    await _pins.forget(deviceId);
    await _persist();
  }

  Future<void> _persist() async {
    final j = <String, dynamic>{};
    _peers.forEach((id, c) => j[id] = c.toJson());
    await _storage.writeAtomic(_file, utf8.encode(jsonEncode(j)));
  }
}

/// Local helper so this file has no typed_data import for one call site.
Uint8List Uint8ListFrom(List<int> bytes) =>
    Uint8List.fromList(bytes);