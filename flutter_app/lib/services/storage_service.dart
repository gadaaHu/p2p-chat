import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Atomic file storage rooted at a per-app directory. Every write goes
/// through a temp file + rename, so a crash cannot leave a truncated file.
///
/// POSIX rename(2) is atomic. On Windows, Dart's `File.rename` uses
/// MoveFileEx with MOVEFILE_REPLACE_EXISTING, which is also atomic.
class StorageService {
  final Directory _root;

  StorageService._(this._root);

  static Future<StorageService> open({Directory? override}) async {
    final base = override ?? await getApplicationSupportDirectory();
    final root = Directory('${base.path}/p2p_chat');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return StorageService._(root);
  }

  File file(String name) => File('${_root.path}/$name');

  Future<bool> exists(String name) => file(name).exists();

  Future<Uint8List?> read(String name) async {
    final f = file(name);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  /// Atomic write. If the process is killed mid-write, either the old
  /// file or the new file is on disk — never a partial.
  Future<void> writeAtomic(String name, List<int> bytes) async {
    final target = file(name);
    final tmpPath =
        '${target.path}.tmp.${DateTime.now().microsecondsSinceEpoch}';
    final tmp = File(tmpPath);
    final sink = tmp.openWrite();
    try {
      sink.add(bytes);
      await sink.flush();
    } finally {
      await sink.close();
    }
    await tmp.rename(target.path);
  }

  Future<void> delete(String name) async {
    final f = file(name);
    if (await f.exists()) await f.delete();
  }

  /// Lists files matching a prefix. Used to enumerate per-message records.
  Future<List<String>> list({String prefix = ''}) async {
    final entries = await _root.list().toList();
    return entries
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.startsWith(prefix))
        .toList();
  }

  /// Removes every file in the store. Used by tests and by a future
  /// "wipe local data" action.
  Future<void> wipe() async {
    if (await _root.exists()) {
      await _root.delete(recursive: true);
      await _root.create(recursive: true);
    }
  }
}