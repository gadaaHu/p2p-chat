import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/models/sender_key.dart';
import 'package:p2p_chat/services/sender_key_store.dart';
import 'package:p2p_chat/services/storage_service.dart';

void main() {
  late Directory tmp;
  late StorageService storage;
  late SenderKeyStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sk_');
    storage = await StorageService.open(override: tmp);
    store = SenderKeyStore(storage);
    await store.load();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('activeOrCreate creates version 1', () async {
    final k = await store.activeOrCreate(
      groupId: 'g',
      ownerDeviceId: 'me',
    );
    expect(k.version, 1);
    expect(k.chainKey.length, 32);
  });

  test('activeOrCreate is idempotent without rotate', () async {
    final k1 = await store.activeOrCreate(
      groupId: 'g',
      ownerDeviceId: 'me',
    );
    final k2 = await store.activeOrCreate(
      groupId: 'g',
      ownerDeviceId: 'me',
    );
    expect(k1.keyId, k2.keyId);
  });

  test('rotate bumps version and changes keyId', () async {
    final k1 = await store.activeOrCreate(
      groupId: 'g',
      ownerDeviceId: 'me',
    );
    final k2 = await store.activeOrCreate(
      groupId: 'g',
      ownerDeviceId: 'me',
      rotate: true,
    );
    expect(k2.version, k1.version + 1);
    expect(k2.keyId, isNot(k1.keyId));
  });

  test('keeps last three versions', () async {
    for (var i = 0; i < 5; i++) {
      await store.activeOrCreate(
        groupId: 'g',
        ownerDeviceId: 'me',
        rotate: true,
      );
    }
    expect(store.ownVersions('g').length, 3);
  });

  test('putReceived rejects older version for same owner', () async {
    final v2 = SenderKey(
      groupId: 'g',
      ownerDeviceId: 'peer',
      keyId: 'k2',
      version: 2,
      keyBytes: List.filled(32, 0),
      createdAt: 0,
    );
    final v1 = SenderKey(
      groupId: 'g',
      ownerDeviceId: 'peer',
      keyId: 'k1',
      version: 1,
      keyBytes: List.filled(32, 1),
      createdAt: 0,
    );
    await store.putReceived(v2);
    await store.putReceived(v1);
    expect(store.received('k1'), isNull);
    expect(store.received('k2'), isNotNull);
  });

  test('acceptSeq enforces monotonicity', () async {
    expect(await store.acceptSeq('g', 'peer', 0), isTrue);
    expect(await store.acceptSeq('g', 'peer', 1), isTrue);
    expect(await store.acceptSeq('g', 'peer', 0), isFalse);
    expect(await store.acceptSeq('g', 'peer', 1), isFalse);
    expect(await store.acceptSeq('g', 'peer', 2), isTrue);
  });

  test('seq is per (group, owner)', () async {
    await store.acceptSeq('g', 'a', 5);
    expect(await store.acceptSeq('g', 'b', 0), isTrue);
    expect(await store.acceptSeq('h', 'a', 0), isTrue);
  });

  test('nextSeq returns highWater + 1', () async {
    expect(store.nextSeq('g', 'me'), 0);
    await store.acceptSeq('g', 'me', 0);
    expect(store.nextSeq('g', 'me'), 1);
    await store.acceptSeq('g', 'me', 5);
    expect(store.nextSeq('g', 'me'), 6);
  });
}