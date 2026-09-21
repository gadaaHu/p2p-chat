import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/models/group.dart';
import 'package:p2p_chat/services/crypto_service.dart';
import 'package:p2p_chat/services/group_service.dart';
import 'package:p2p_chat/services/group_state_store.dart';
import 'package:p2p_chat/services/identity_service.dart';
import 'package:p2p_chat/services/sender_key_store.dart';
import 'package:p2p_chat/services/storage_service.dart';

/// Tests the group message round-trip at the cryptographic layer only.
/// No networking, no signaling — sender key distribution is exercised by
/// passing the built payload directly between two service instances.
void main() {
  late Directory tmpA;
  late Directory tmpB;
  late StorageService storageA;
  late StorageService storageB;
  late CryptoService cryptoA;
  late CryptoService cryptoB;
  late IdentityService idA;
  late IdentityService idB;
  late GroupService svcA;
  late GroupService svcB;

  setUp(() async {
    tmpA = await Directory.systemTemp.createTemp('gA_');
    tmpB = await Directory.systemTemp.createTemp('gB_');
    storageA = await StorageService.open(override: tmpA);
    storageB = await StorageService.open(override: tmpB);
    cryptoA = CryptoService(storageA);
    cryptoB = CryptoService(storageB);
    idA = IdentityService(storageA, cryptoA);
    idB = IdentityService(storageB, cryptoB);
    await idA.loadOrCreate();
    await idB.loadOrCreate();

    svcA = GroupService(
      crypto: cryptoA,
      identity: idA,
      state: GroupStateStore(storageA),
      senderKeys: SenderKeyStore(storageA),
    );
    svcB = GroupService(
      crypto: cryptoB,
      identity: idB,
      state: GroupStateStore(storageB),
      senderKeys: SenderKeyStore(storageB),
    );
    await svcA.init();
    await svcB.init();
  });

  tearDown(() async {
    if (await tmpA.exists()) await tmpA.delete(recursive: true);
    if (await tmpB.exists()) await tmpB.delete(recursive: true);
  });

  test('create and distribute sender key', () async {
    final bMember = GroupMember(
      deviceId: idB.identity.deviceId,
      ed25519Public: idB.identity.ed25519Public,
      addedAt: 0,
    );
    final created = await svcA.create(name: 'test', members: [bMember]);
    expect(created.group.members.length, 2);

    // B applies the group state it would have received over the wire.
    final stateFrame = svcA.buildStateFrame(created.group);
    final decoded = await svcB.parseStateFrame(stateFrame);
    expect(decoded, isNotNull);
    await svcB.applyRemoteState(decoded!);

    // A distributes its sender key.
    final dist = await svcA.buildDistribution(created.group);
    expect(dist.length, 1);
    final key = svcA.parseSenderKey(dist.first.plaintext);
    expect(key, isNotNull);
    expect(await svcB.acceptSenderKey(key!), isTrue);
  });

  test('A sends a group message that B decrypts', () async {
    final bMember = GroupMember(
      deviceId: idB.identity.deviceId,
      ed25519Public: idB.identity.ed25519Public,
      addedAt: 0,
    );
    final created = await svcA.create(name: 'test', members: [bMember]);
    final decoded = await svcB.parseStateFrame(
      svcA.buildStateFrame(created.group),
    );
    await svcB.applyRemoteState(decoded!);
    final dist = await svcA.buildDistribution(created.group);
    await svcB.acceptSenderKey(svcA.parseSenderKey(dist.first.plaintext)!);

    final built = await svcA.buildMessage(
      groupId: created.group.groupId,
      content: 'hello group',
    );
    final wrapped = jsonDecode(svcA.wrapForRecipient(built)) as Map<String, dynamic>;

    final decrypted = await svcB.tryDecrypt(wrapped);
    expect(decrypted, isNotNull);
    expect(decrypted!.content, 'hello group');
    expect(decrypted.senderDeviceId, idA.identity.deviceId);
  });

  test('replay of the same sender_seq fails', () async {
    final bMember = GroupMember(
      deviceId: idB.identity.deviceId,
      ed25519Public: idB.identity.ed25519Public,
      addedAt: 0,
    );
    final created = await svcA.create(name: 'test', members: [bMember]);
    final decoded = await svcB.parseStateFrame(
      svcA.buildStateFrame(created.group),
    );
    await svcB.applyRemoteState(decoded!);
    final dist = await svcA.buildDistribution(created.group);
    await svcB.acceptSenderKey(svcA.parseSenderKey(dist.first.plaintext)!);

    final built = await svcA.buildMessage(
      groupId: created.group.groupId,
      content: 'once',
    );
    final wrapped = jsonDecode(svcA.wrapForRecipient(built)) as Map<String, dynamic>;

    expect(await svcB.tryDecrypt(wrapped), isNotNull);
    expect(await svcB.tryDecrypt(wrapped), isNull);
  });

  test('removed member cannot decrypt new messages', () async {
    final bMember = GroupMember(
      deviceId: idB.identity.deviceId,
      ed25519Public: idB.identity.ed25519Public,
      addedAt: 0,
    );
    final created = await svcA.create(name: 'test', members: [bMember]);
    final state1 = await svcB.parseStateFrame(
      svcA.buildStateFrame(created.group),
    );
    await svcB.applyRemoteState(state1!);
    final dist = await svcA.buildDistribution(created.group);
    await svcB.acceptSenderKey(svcA.parseSenderKey(dist.first.plaintext)!);

    // A removes B. A rotates its sender key. B is not told.
    await svcA.removeMember(
      groupId: created.group.groupId,
      deviceId: idB.identity.deviceId,
    );

    final built = await svcA.buildMessage(
      groupId: created.group.groupId,
      content: 'after removal',
    );
    final wrapped = jsonDecode(svcA.wrapForRecipient(built)) as Map<String, dynamic>;

    // B still knows the old group state; it will see the message but
    // cannot decrypt it because the sender key version is new.
    expect(await svcB.tryDecrypt(wrapped), isNull);
  });

  test('rejects message from a non-member', () async {
    final bMember = GroupMember(
      deviceId: idB.identity.deviceId,
      ed25519Public: idB.identity.ed25519Public,
      addedAt: 0,
    );
    final created = await svcA.create(name: 'test', members: [bMember]);
    final decoded = await svcB.parseStateFrame(
      svcA.buildStateFrame(created.group),
    );
    await svcB.applyRemoteState(decoded!);

    // B has no sender key from A, so tryDecrypt fails cleanly.
    final fake = {
      'type': 'group-msg',
      'group_id': created.group.groupId,
      'message_id': 'fake',
      'sender': 'unknown',
      'key_id': 'nope',
      'sender_seq': 0,
      'sent_at': 0,
      'ct': base64Encode([1, 2, 3]),
      'nonce': base64Encode(List.filled(12, 0)),
      'tag': base64Encode(List.filled(16, 0)),
    };
    expect(await svcB.tryDecrypt(fake), isNull);
  });
}