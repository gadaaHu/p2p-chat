import 'dart:convert';

import '../models/profile.dart';
import '../services/storage_ref.dart';

/// The local user's profile. Separate from the cryptographic identity,
/// which lives in `IdentityService`.
class IdentityRepository {
  static const _file = 'profile.json';

  final StorageRef _storage;
  Profile? _cached;

  IdentityRepository(this._storage);

  Future<Profile> load() async {
    if (_cached != null) return _cached!;
    final raw = await _storage.read(_file);
    if (raw == null) {
      final p = Profile(
        displayName: 'Me',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await save(p);
      return p;
    }
    final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
    _cached = Profile.fromJson(j);
    return _cached!;
  }

  Future<void> save(Profile p) async {
    _cached = p;
    await _storage.writeAtomic(_file, utf8.encode(jsonEncode(p.toJson())));
  }

  Future<void> setDisplayName(String name) async {
    final current = await load();
    await save(current.copyWith(displayName: name));
  }

  Future<void> setAvatar(String? path) async {
    final current = await load();
    await save(current.copyWith(avatarPath: path));
  }
}