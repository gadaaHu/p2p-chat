import 'dart:typed_data';

/// Narrow storage interface so repositories don't depend on [StorageService]
/// directly and tests can inject a fake.
abstract class StorageRef {
  Future<Uint8List?> read(String name);
  Future<void> writeAtomic(String name, List<int> bytes);
  Future<void> delete(String name);
}
