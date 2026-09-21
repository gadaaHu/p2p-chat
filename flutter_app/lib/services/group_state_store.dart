import 'dart:async';
import 'dart:convert';

import '../models/group.dart';
import 'storage_service.dart';

/// Persists local group state. One file per group so a corrupt file
/// cannot take down every group. Rejects writes with a stale epoch.
class GroupStateStore {
  static const _indexFile = 'groups_index.json';
  static const _prefix = 'group.';
  static const _suffix = '.json';

  final StorageService _storage;
  final Map<String, Group> _groups = {};
  final _changed = StreamController<Group>.broadcast();
  Stream<Group> get changed => _changed.stream;

  GroupStateStore(this._storage);

  Future<void> load() async {
    final raw = await _storage.read(_indexFile);
    if (raw == null) return;
    final ids = (jsonDecode(utf8.decode(raw)) as List).cast<String>();
    for (final id in ids) {
      final g = await _storage.read('$_prefix$id$_suffix');
      if (g == null) continue;
      try {
        _groups[id] = Group.fromJson(
          jsonDecode(utf8.decode(g)) as Map<String, dynamic>,
        );
      } catch (_) {
        // Corrupt: skip.
      }
    }
  }

  Group? byId(String groupId) => _groups[groupId];

  List<Group> all() => _groups.values.toList();

  Future<void> put(Group g) async {
    final existing = _groups[g.groupId];
    if (existing != null && g.epoch < existing.epoch) return;
    _groups[g.groupId] = g;
    await _storage.writeAtomic(
      '$_prefix${g.groupId}$_suffix',
      utf8.encode(jsonEncode(g.toJson())),
    );
    await _persistIndex();
    _changed.add(g);
  }

  Future<void> remove(String groupId) async {
    _groups.remove(groupId);
    await _storage.delete('$_prefix$groupId$_suffix');
    await _persistIndex();
  }

  Future<void> _persistIndex() async {
    await _storage.writeAtomic(
      _indexFile,
      utf8.encode(jsonEncode(_groups.keys.toList())),
    );
  }

  void dispose() => _changed.close();
}