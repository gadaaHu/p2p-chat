import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:p2p_chat/models/group.dart';
import 'package:p2p_chat/services/crypto_service.dart';
import 'package:p2p_chat/services/group_service.dart';
import 'package:p2p_chat/services/group_state_store.dart';
import 'package:p2p_chat/services/identity_service.dart';
import 'package:p2p_chat/services/sender_key_store.dart';
import 'package:p2p_chat/services/storage_service.dart';

/// Group flow at the service layer, driven in-process. No networking.
/// Exercises the full lifecycle: create, distribute, send, receive,
/// membership change, rotation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('group create → send → receive → remove → cannot decrypt', () async {
    final tmpA = await Directory.systemTemp.createTemp('gfA_');
    final tmpB = await Directory.systemTemp.createTemp('gfB_');
    final tmpC = await Directory.systemTemp.createTemp('gfC_');

    final storageA = await StorageService.open(override: tmpA);
    final storageB = await StorageService.open(override: tmpB);
    final storageC = await StorageService.open(override: tmpC);

    final cryptoA = CryptoService(storageA);
    final cryptoB = CryptoService(storageB);
    final cryptoC = CryptoService(storageC);

    final idA = IdentityService(storageA, cryptoA);
    final idB = IdentityService(storageB, cryptoB);
    final idC = IdentityService(storageC, cryptoC);
    await idA.loadOrCreate();
    await idB.loadOrCreate();
    await idC.loadOrCreate();

    final svcA = GroupService(
      crypto: cryptoA,
      identity: idA,
      state: GroupStateStore(storageA),
      senderKeys: SenderKeyStore(storageA),
    );
    final svcB = GroupService(
      crypto: cryptoB,
      identity: idB,
      state: GroupStateStore(storageB),
      senderKeys: SenderKeyStore(storageB),
    );
    final svcC = GroupService(
      crypto: cryptoC,
      identity: idC,
      state: GroupStateStore(storageC),
      senderKeys: SenderKeyStore(storageC),
    );
    await svcA.init();
    await svcB.init();
    await svcC.init();

    // A creates a group with B and C.
    final bMember = GroupMember(
      deviceId: idB.identity.deviceId,
      ed25519Public: idB.identity.ed25519Public,
      addedAt: 0,
    );
    final cMember = GroupMember(
      deviceId: idC.identity.deviceId,
      ed25519Public: idC.identity.ed25519Public,
      addedAt: 0,
    );
    final created = await svcA.create(
      name: 'integration',
      members: [bMember, cMember],
    );

    // Distribute state and sender key to B and C.
    final stateFrame = svcA.buildStateFrame(created.group);
    await svcB.applyRemoteState((await svcB.parseStateFrame(stateFrame))!);
    await svcC.applyRemoteState((await svcC.parseStateFrame(stateFrame))!);

    final dist = await svcA.buildDistribution(created.group);
    for (final d in dist) {
      final key = svcA.parseSenderKey(d.plaintext)!;
      if (d.recipient.deviceId == idB.identity.deviceId) {
        await svcB.acceptSenderKey(key);
      } else if (d.recipient.deviceId == idC.identity.deviceId) {
        await svcC.acceptSenderKey(key);
      }
    }

    // A sends a message.
    final built = await svcA.buildMessage(
      groupId: created.group.groupId,
      content: 'hello everyone',
    );
    final wrapped = jsonDecode(svcA.wrapForRecipient(built)) as Map<String, dynamic>;

    final decB = await svcB.tryDecrypt(wrapped);
    final decC = await svcC.tryDecrypt(wrapped);
    expect(decB!.content, 'hello everyone');
    expect(decC!.content, 'hello everyone');

    // A removes B.
    await svcA.removeMember(
      groupId: created.group.groupId,
      deviceId: idB.identity.deviceId,
    );

    // A sends another message. C is up to date (in a real flow, C would
    // receive the new state frame), B is not.
    final newState = svcA.buildStateFrame(
      svcA.groupById(created.group.groupId)!,
    );
    await svcC.applyRemoteState((await svcC.parseStateFrame(newState))!);

    final newDist = await svcA.buildDistribution(
      svcA.groupById(created.group.groupId)!,
    );
    for (final d in newDist) {
      if (d.recipient.deviceId == idC.identity.deviceId) {
        await svcC.acceptSenderKey(svcA.parseSenderKey(d.plaintext)!);
      }
    }

    final built2 = await svcA.buildMessage(
      groupId: created.group.groupId,
      content: 'after removal',
    );
    final wrapped2 = jsonDecode(svcA.wrapForRecipient(built2)) as Map<String, dynamic>;

    // C decrypts. B cannot, because it does not have the new sender key.
    expect(await svcC.tryDecrypt(wrapped2), isNotNull);
    expect(await svcB.tryDecrypt(wrapped2), isNull);

    // Cleanup.
    await tmpA.delete(recursive: true);
    await tmpB.delete(recursive: true);
    await tmpC.delete(recursive: true);
  });
}