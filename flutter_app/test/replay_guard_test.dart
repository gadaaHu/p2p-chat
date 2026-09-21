import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/services/replay_guard.dart';
import 'package:p2p_chat/services/storage_service.dart';

void main() {
  late Directory tmp;
  late StorageService storage;
  late ReplayGuard guard;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('replay_');
    storage = await StorageService.open(override: tmp);
    guard = ReplayGuard(storage);
    await guard.load();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('first counter accepted', () async {
    expect(await guard.accept('peer', 0), isTrue);
  });

  test('duplicate counter rejected', () async {
    await guard.accept('peer', 0);
    expect(await guard.accept('peer', 0), isFalse);
  });

  test('out-of-order within window accepted', () async {
    await guard.accept('peer', 10);
    expect(await guard.accept('peer', 5), isTrue);
    expect(await guard.accept('peer', 7), isTrue);
  });

  test('counter below window rejected', () async {
    await guard.accept('peer', 1000);
    expect(
      await guard.accept('peer', 1000 - ReplayGuard.windowSize - 1),
      isFalse,
    );
  });

  test('duplicates within window rejected', () async {
    await guard.accept('peer', 10);
    await guard.accept('peer', 5);
    expect(await guard.accept('peer', 5), isFalse);
  });

  test('window persists across restart', () async {
    await guard.accept('peer', 5);
    final g2 = ReplayGuard(storage);
    await g2.load();
    expect(await g2.accept('peer', 5), isFalse);
    expect(await g2.accept('peer', 6), isTrue);
  });

  test('per-peer isolation', () async {
    await guard.accept('peerA', 5);
    expect(await guard.accept('peerB', 5), isTrue);
  });

  test('window bound holds under many accepts', () async {
    for (var i = 0; i < 2000; i++) {
      await guard.accept('peer', i);
    }
    final raw = await storage.read('replay_guard.json');
    final state = jsonDecode(utf8.decode(raw!)) as Map<String, dynamic>;
    final window = (state['peer'] as Map<String, dynamic>)['window'] as List;
    expect(window.length, lessThanOrEqualTo(ReplayGuard.windowSize * 2));
  });
}