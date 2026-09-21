import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/services/replay_guard.dart';
import 'package:p2p_chat/services/storage_service.dart';

/// The outbound counter must not reset on app restart, or the peer's
/// replay guard will reject the first message after restart as "too
/// old". This test verifies the persisted state survives a simulated
/// restart and rejects stale counters while accepting new ones.
void main() {
  late Directory tmp;
  late StorageService storage;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('counter_restart_');
    storage = await StorageService.open(override: tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('guard accepts fresh counters after restart', () async {
    final g1 = ReplayGuard(storage);
    await g1.load();
    for (var i = 0; i < 10; i++) {
      expect(await g1.accept('peer', i), isTrue);
    }

    // Simulated restart.
    final g2 = ReplayGuard(storage);
    await g2.load();

    // Continuing forward is fine.
    expect(await g2.accept('peer', 10), isTrue);
    expect(await g2.accept('peer', 11), isTrue);

    // Going back is rejected.
    expect(await g2.accept('peer', 5), isFalse);
  });

  test('high water reflects accepted counters', () async {
    final g = ReplayGuard(storage);
    await g.load();
    expect(await g.highWater('peer'), -1);
    await g.accept('peer', 3);
    await g.accept('peer', 7);
    await g.accept('peer', 5);
    expect(await g.highWater('peer'), 7);

    final g2 = ReplayGuard(storage);
    await g2.load();
    expect(await g2.highWater('peer'), 7);
  });

  test('forget clears state for a peer only', () async {
    final g = ReplayGuard(storage);
    await g.load();
    await g.accept('a', 5);
    await g.accept('b', 5);
    await g.forget('a');
    expect(await g.highWater('a'), -1);
    expect(await g.highWater('b'), 5);
  });
}