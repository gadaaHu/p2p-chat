import 'dart:convert';

import 'storage_service.dart';

/// User-visible preferences. Persisted as a single small JSON file.
class SettingsService {
  static const _file = 'settings.json';

  final StorageService _storage;
  bool _loaded = false;

  bool _readReceiptsEnabled = true;

  /// Set by main.dart to a callback that wipes all local data. The
  /// settings screen invokes it after confirmation.
  Future<void> Function()? onFullWipeRequested;

  SettingsService(this._storage);

  bool get readReceiptsEnabled => _readReceiptsEnabled;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.read(_file);
    if (raw != null) {
      try {
        final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        _readReceiptsEnabled = (j['read_receipts'] as bool?) ?? true;
      } catch (_) {
        // Corrupt settings: fall back to defaults.
      }
    }
    _loaded = true;
  }

  Future<void> setReadReceiptsEnabled(bool value) async {
    await load();
    _readReceiptsEnabled = value;
    await _storage.writeAtomic(
      _file,
      utf8.encode(jsonEncode({'read_receipts': value})),
    );
  }

  /// Called by SettingsScreen after user confirmation.
  Future<void> requestFullWipe() async {
    final cb = onFullWipeRequested;
    if (cb != null) await cb();
  }
}