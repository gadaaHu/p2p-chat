import 'dart:convert';

import 'session_state.dart';
import '../storage_service.dart';

class RatchetStore {
  static const _prefix = 'ratchet.';
  static const _suffix = '.json';

  final StorageService _storage;
  final Map<String, RatchetSession> _cache = {};

  RatchetStore(this._storage);

  Future<RatchetSession?> get(String peerDeviceId) async {
    final cached = _cache[peerDeviceId];
    if (cached != null) return cached;
    final raw = await _storage.read('$_prefix$peerDeviceId$_suffix');
    if (raw == null) return null;
    try {
      final s = RatchetSession.fromJson(
        jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
      );
      _cache[peerDeviceId] = s;
      return s;
    } catch (_) {
      return null;
    }
  }

  /// Synchronous lookup from cache only. Returns null if not loaded yet.
  RatchetSession? byPeer(String peerDeviceId) => _cache[peerDeviceId];

  Future<void> put(String peerDeviceId, RatchetSession session) async {
    _cache[peerDeviceId] = session;
    await _storage.writeAtomic(
      '$_prefix$peerDeviceId$_suffix',
      utf8.encode(jsonEncode(session.toJson())),
    );
  }

  Future<void> delete(String peerDeviceId) async {
    _cache.remove(peerDeviceId);
    await _storage.delete('$_prefix$peerDeviceId$_suffix');
  }
}