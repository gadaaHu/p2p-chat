import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/services/storage_service.dart';
import 'package:p2p_chat/services/unread_store.dart';

void main() {
  late Directory tmp;
  late StorageService storage;
  late UnreadStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('unread_');
    storage = await StorageService.open(override: tmp);
    store = UnreadStore(storage);
    await store.load();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('starts empty', () {
    expect(store.unreadFor('peer'), 0);
    expect(store.totalUnread(), 0);
  });

  test('recordReceived increments unread', () async {
    await store.recordReceived('peer', 'm1');
    await store.recordReceived('peer', 'm2');
    expect(store.unreadFor('peer'), 2);
  });

  test('markDisplayed clears unread and queues pending', () async {
    await store.recordReceived('peer', 'm1');
    await store.recordReceived('peer', 'm2');
    await store.markDisplayed('peer', ['m1', 'm2']);
    expect(store.unreadFor('peer'), 0);
    expect((await store.peekPending('peer')).toSet(), {'m1', 'm2'});
  });

  test('takePending clears the set', () async {
    await store.markDisplayed('peer', ['m1', 'm2']);
    expect((await store.takePending('peer')).toSet(), {'m1', 'm2'});
    expect(await store.takePending('peer'), isEmpty);
  });

  test('unread survives restart', () async {
    await store.recordReceived('peer', 'm1');
    final s2 = UnreadStore(storage);
    await s2.load();
    expect(s2.unreadFor('peer'), 1);
  });

  test('pending survives restart', () async {
    await store.markDisplayed('peer', ['m1', 'm2']);
    final s2 = UnreadStore(storage);
    await s2.load();
    expect((await s2.peekPending('peer')).toSet(), {'m1', 'm2'});
  });

  test('total sums across peers', () async {
    await store.recordReceived('a', 'm1');
    await store.recordReceived('b', 'm2');
    await store.recordReceived('b', 'm3');
    expect(store.totalUnread(), 3);
  });
}