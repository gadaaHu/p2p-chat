import 'dart:convert';
import 'dart:typed_data';

import '../models/identity_pin.dart';
import 'storage_service.dart';

/// Trust-on-first-use. A key change is never silently accepted: the
/// caller must explicitly confirm via [pin] after user approval.
///
/// The `verified` flag is separate from the pin itself. A pin exists as
/// soon as we see a key. Verification exists only after the user has
/// compared safety numbers out of band. Rotation resets verification.
class PinningPolicy {
  static const _file = 'identity_pins.json';

  final StorageService _storage;
  final Map<String, IdentityPin> _pins = {};
  bool _loaded = false;

  PinningPolicy(this._storage);

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.read(_file);
    if (raw != null) {
      final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      j.forEach((id, v) {
        _pins[id] = IdentityPin.fromJson(v as Map<String, dynamic>);
      });
    }
    _loaded = true;
  }

  Future<IdentityPin?> pinFor(String deviceId) async {
    await load();
    return _pins[deviceId];
  }

  Future<List<IdentityPin>> all() async {
    await load();
    return _pins.values.toList();
  }

  Future<bool> isVerified(String deviceId) async {
    await load();
    return _pins[deviceId]?.verified ?? false;
  }

  /// Pure evaluation. Does not mutate state.
  Future<PinState> evaluate({
    required String deviceId,
    required List<int> ed25519Public,
    required List<int> x25519Public,
  }) async {
    await load();
    final existing = _pins[deviceId];
    if (existing == null) return PinState.unknown;
    if (_bytesEq(existing.ed25519Public, ed25519Public) &&
        _bytesEq(existing.x25519Public, x25519Public)) {
      return PinState.match;
    }
    return PinState.changed;
  }

  /// Creates or replaces the pin. Callers must first call [evaluate] and
  /// decide what to do with a `changed` result. Never call this from a
  /// silent path.
  Future<void> pin({
    required String deviceId,
    required List<int> ed25519Public,
    required List<int> x25519Public,
  }) async {
    await load();
    _pins[deviceId] = IdentityPin(
      deviceId: deviceId,
      ed25519Public: Uint8List.fromList(ed25519Public),
      x25519Public: Uint8List.fromList(x25519Public),
      pinnedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      verified: false,
      verifiedAt: null,
    );
    await _persist();
  }

  Future<void> markVerified(String deviceId) async {
    await load();
    final existing = _pins[deviceId];
    if (existing == null) return;
    _pins[deviceId] = existing.copyWith(
      verified: true,
      verifiedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    await _persist();
  }

  Future<void> markUnverified(String deviceId) async {
    await load();
    final existing = _pins[deviceId];
    if (existing == null || !existing.verified) return;
    _pins[deviceId] = existing.copyWith(
      verified: false,
      verifiedAt: null,
    );
    await _persist();
  }

  Future<void> forget(String deviceId) async {
    await load();
    _pins.remove(deviceId);
    await _persist();
  }

  Future<void> _persist() async {
    final j = <String, dynamic>{};
    _pins.forEach((id, p) {
      j[id] = p.toJson();
    });
    await _storage.writeAtomic(_file, utf8.encode(jsonEncode(j)));
  }

  bool _bytesEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}