import 'dart:convert';

import 'storage_service.dart';

class UnreadStore {
  static const _file = 'unread.json';

  final StorageService _storage;

  /// Per-peer pending read set: message IDs received but not yet receipted.
  final Map<String, Set<String>> _pending = {};

  /// Per-peer high-water mark: highest received counter we have marked read.
  /// Purely a display optimization — the authoritative state is the set.
  final Map<String, int> _watermark = {};

  /// Per-peer unread count reported to the UI.
  final Map<String, int> _unread = {};

  bool _loaded = false;

  UnreadStore(this._storage);

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.read(_file);
    if (raw != null) {
      final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      (j['pending'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        _pending[k] = (v as List).cast<String>().toSet();
      });
      (j['watermark'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        _watermark[k] = v as int;
      });
      (j['unread'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        _unread[k] = v as int;
      });
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    await _storage.writeAtomic(
      _file,
      utf8.encode(jsonEncode({
        'pending': _pending.map((k, v) => MapEntry(k, v.toList())),
        'watermark': _watermark,
        'unread': _unread,
      })),
    );
  }

  int unreadFor(String peerDeviceId) => _unread[peerDeviceId] ?? 0;

  int totalUnread() => _unread.values.fold(0, (a, b) => a + b);

  /// Called when a chat message from [peer] is persisted. Increments the
  /// unread count. Does NOT add to the pending read set — that only happens
  /// when the chat is actually on screen.
  Future<void> recordReceived(String peerDeviceId, String messageId) async {
    await load();
    _unread[peerDeviceId] = (_unread[peerDeviceId] ?? 0) + 1;
    await _persist();
  }

  /// Called when the chat screen becomes visible and a message is shown.
  Future<void> markDisplayed(String peerDeviceId, List<String> messageIds) async {
    await load();
    final set = _pending.putIfAbsent(peerDeviceId, () => <String>{});
    set.addAll(messageIds);
    _unread[peerDeviceId] = 0;
    await _persist();
  }

  /// Returns and clears the pending read set for [peerDeviceId]. Called
  /// right before building a read receipt, so a crash between this and the
  /// receipt's delivery would lose the batch — acceptable, because the peer
  /// simply sees "delivered" instead of "read" for those messages.
  Future<List<String>> takePending(String peerDeviceId) async {
    await load();
    final set = _pending.remove(peerDeviceId);
    if (set == null || set.isEmpty) return const [];
    await _persist();
    return set.toList();
  }

  /// Non-destructive peek for tests and diagnostics.
  Future<List<String>> peekPending(String peerDeviceId) async {
    await load();
    return (_pending[peerDeviceId] ?? const <String>{}).toList();
  }

  /// Called when the user manually marks all as read from the chat list.
  Future<void> markAllRead(String peerDeviceId, List<String> messageIds) async {
    await markDisplayed(peerDeviceId, messageIds);
  }
}