import 'dart:convert';

import 'storage_service.dart';

/// Bounded sliding window of accepted (peer, counter) pairs. Persisted so
/// a crash cannot be used to replay an old message.
///
/// Window semantics:
///   - counters <= max - windowSize are rejected outright (too old to
///     judge, and memory is bounded)
///   - counters already in the window are rejected (duplicate)
///   - counters within the window but new are accepted
class ReplayGuard {
  static const _file = 'replay_guard.json';
  static const windowSize = 256;

  final StorageService _storage;
  final Map<String, _PeerReplayState> _state = {};
  bool _loaded = false;

  ReplayGuard(this._storage);

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.read(_file);
    if (raw != null) {
      final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      j.forEach((peer, v) {
        _state[peer] = _PeerReplayState.fromJson(
          v as Map<String, dynamic>,
        );
      });
    }
    _loaded = true;
  }

  /// Returns true if [counter] from [peerDeviceId] is fresh. Persists
  /// state before returning true, so a crash after acceptance cannot
  /// allow the same counter to be accepted again.
  Future<bool> accept(String peerDeviceId, int counter) async {
    await load();
    final s = _state.putIfAbsent(peerDeviceId, _PeerReplayState.new);

    if (s.max >= 0 && counter <= s.max - windowSize) return false;
    if (s.window.contains(counter)) return false;

    s.window.add(counter);
    if (counter > s.max) s.max = counter;

    // Evict counters that fell out of the window.
    if (s.window.length > windowSize * 2) {
      s.window.removeWhere((c) => c < s.max - windowSize);
    }

    await _persist();
    return true;
  }

  /// Highest accepted counter for [peerDeviceId], or -1 if none.
  Future<int> highWater(String peerDeviceId) async {
    await load();
    return _state[peerDeviceId]?.max ?? -1;
  }

  /// Clears all state for a peer. Called when a peer's identity is
  /// rotated or forgotten.
  Future<void> forget(String peerDeviceId) async {
    await load();
    _state.remove(peerDeviceId);
    await _persist();
  }

  Future<void> _persist() async {
    final j = <String, dynamic>{};
    _state.forEach((k, v) => j[k] = v.toJson());
    await _storage.writeAtomic(_file, utf8.encode(jsonEncode(j)));
  }
}

class _PeerReplayState {
  _PeerReplayState();
  
  int max = -1;
  final Set<int> window = {};

  Map<String, dynamic> toJson() => {
        'max': max,
        'window': window.toList(),
      };

  factory _PeerReplayState.fromJson(Map<String, dynamic> j) {
    final s = _PeerReplayState()..max = j['max'] as int;
    s.window.addAll((j['window'] as List).cast<int>());
    return s;
  }
}