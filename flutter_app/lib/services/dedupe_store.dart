import 'dart:convert';

import 'storage_service.dart';

/// Tracks seen message IDs within a bounded sliding window to prevent
/// replayed or duplicate messages from being surfaced to the UI.
class DedupeStore {
  static const _file = 'dedupe.json';
  static const _maxSize = 2048;

  final StorageService _storage;
  final Set<String> _seen = {};
  bool _loaded = false;

  DedupeStore(this._storage);

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.read(_file);
    if (raw != null) {
      final list = (jsonDecode(utf8.decode(raw)) as List).cast<String>();
      _seen.addAll(list);
    }
    _loaded = true;
  }

  /// Returns true if [messageId] has not been seen before, and records it.
  Future<bool> accept(String messageId) async {
    await load();
    if (_seen.contains(messageId)) return false;
    _seen.add(messageId);
    if (_seen.length > _maxSize) {
      // Evict oldest (by insertion order in the set — roughly FIFO)
      _seen.remove(_seen.first);
    }
    await _persist();
    return true;
  }

  /// Returns true if this messageId has already been seen.
  bool contains(String messageId) => _seen.contains(messageId);

  /// Records a messageId as seen without returning a value.
  Future<void> record(String messageId) async {
    await load();
    _seen.add(messageId);
    if (_seen.length > _maxSize) {
      _seen.remove(_seen.first);
    }
    await _persist();
  }

  Future<void> _persist() async {
    await _storage.writeAtomic(_file, utf8.encode(jsonEncode(_seen.toList())));
  }
}
