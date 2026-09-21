import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as c;

import '../models/sender_key.dart';
import 'storage_service.dart';

/// Owns sender keys for groups. Two populations:
///   - keys we generated, indexed by group ID
///   - keys we received from peers, indexed by key ID
///
/// Chain advancement is handled by the caller. This store only persists
/// and enforces version monotonicity.
class SenderKeyStore {
  static const _file = 'sender_keys.json';
  static const _keepOwnVersions = 3;

  final StorageService _storage;
  bool _loaded = false;

  final Map<String, List<SenderKey>> _own = {};
  final Map<String, SenderKey> _received = {};
  final Map<String, int> _seqHighWater = {};

  final _changed = StreamController<void>.broadcast();
  Stream<void> get changed => _changed.stream;

  SenderKeyStore(this._storage);

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.read(_file);
    if (raw != null) {
      final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      (j['own'] as Map<String, dynamic>? ?? {}).forEach((gid, list) {
        _own[gid] = (list as List)
            .map((e) => SenderKey.fromJson(e as Map<String, dynamic>))
            .toList();
      });
      (j['received'] as Map<String, dynamic>? ?? {}).forEach((kid, v) {
        _received[kid] = SenderKey.fromJson(v as Map<String, dynamic>);
      });
      (j['seq'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        _seqHighWater[k] = v as int;
      });
    }
    _loaded = true;
  }

  Future<void> _persist() async {
    await _storage.writeAtomic(
      _file,
      utf8.encode(jsonEncode({
        'own': _own.map(
          (g, list) => MapEntry(g, list.map((k) => k.toJson()).toList()),
        ),
        'received': _received.map((k, v) => MapEntry(k, v.toJson())),
        'seq': _seqHighWater,
      })),
    );
    _changed.add(null);
  }

  // ─── Own keys ─────────────────────────────────────────────────────────

  Future<SenderKey> activeOrCreate({
    required String groupId,
    required String ownerDeviceId,
    bool rotate = false,
  }) async {
    await load();
    final list = _own.putIfAbsent(groupId, () => []);
    if (!rotate && list.isNotEmpty) return list.last;

    final version = list.isEmpty ? 1 : list.last.version + 1;
    final key = _generateKey(groupId, ownerDeviceId, version);
    list.add(key);
    while (list.length > _keepOwnVersions) {
      list.removeAt(0);
    }
    await _persist();
    return key;
  }

  List<SenderKey> ownVersions(String groupId) =>
      (_own[groupId] ?? const <SenderKey>[]).reversed.toList();

  Future<void> updateOwnChain(String groupId, String keyId, List<int> chain) async {
    await load();
    final list = _own[groupId];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      if (list[i].keyId == keyId) {
        list[i] = list[i].copyWith(chainKey: chain);
        await _persist();
        return;
      }
    }
  }

  // ─── Received keys ────────────────────────────────────────────────────

  SenderKey? received(String keyId) => _received[keyId];

  Future<void> putReceived(SenderKey key) async {
    await load();
    final existing = _received[key.keyId];
    if (existing != null && existing.version >= key.version) return;

    final hasNewerSameOwner = _received.values.any((k) =>
        k.groupId == key.groupId &&
        k.ownerDeviceId == key.ownerDeviceId &&
        k.version > key.version);
    if (hasNewerSameOwner) return;

    _received[key.keyId] = key;
    await _persist();
  }

  Future<void> updateReceivedChain(String keyId, List<int> chain) async {
    await load();
    final k = _received[keyId];
    if (k != null) {
      _received[keyId] = k.copyWith(chainKey: chain);
      await _persist();
    }
  }

  // ─── Chain sequences ──────────────────────────────────────────────────

  Future<bool> acceptSeq(
    String groupId,
    String owner,
    int seq,
  ) async {
    await load();
    final k = '$groupId|$owner';
    final cur = _seqHighWater[k] ?? -1;
    if (seq <= cur) return false;
    _seqHighWater[k] = seq;
    await _persist();
    return true;
  }

  int nextSeq(String groupId, String owner) {
    final k = '$groupId|$owner';
    return (_seqHighWater[k] ?? -1) + 1;
  }

  void dispose() => _changed.close();

  // ─── Generation ───────────────────────────────────────────────────────

  SenderKey _generateKey(String groupId, String owner, int version) {
    final r = Random.secure();
    final chain = List<int>.generate(32, (_) => r.nextInt(256));
    final keyId = c.sha256
        .convert(utf8.encode('$groupId|$owner|$version'))
        .toString()
        .substring(0, 16);
    return SenderKey(
      groupId: groupId,
      ownerDeviceId: owner,
      keyId: keyId,
      version: version,
      keyBytes: chain,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }
}