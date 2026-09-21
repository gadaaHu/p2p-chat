import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/services/x3dh.dart';

void main() {
  late SimpleKeyPair aliceId;
  late SimpleKeyPair bobId;
  late SimpleKeyPair bobSpk;
  late SimpleKeyPair bobOpk;
  late Uint8List aliceIdPub;
  late Uint8List bobIdPub;
  late Uint8List bobSpkPub;
  late Uint8List bobOpkPub;

  setUp(() async {
    aliceId = await X25519().newKeyPair();
    bobId = await X25519().newKeyPair();
    bobSpk = await X25519().newKeyPair();
    bobOpk = await X25519().newKeyPair();

    aliceIdPub = Uint8List.fromList(
      await (await aliceId.extract()).publicKey.bytes,
    );
    bobIdPub = Uint8List.fromList(
      await (await bobId.extract()).publicKey.bytes,
    );
    bobSpkPub = Uint8List.fromList(
      await (await bobSpk.extract()).publicKey.bytes,
    );
    bobOpkPub = Uint8List.fromList(
      await (await bobOpk.extract()).publicKey.bytes,
    );
  });

  test('initiator and responder derive the same SK', () async {
    final init = await X3dh.initiator(
      aliceIdentityX: aliceId,
      bobIdentityX: bobIdPub,
      bobSpkPublic: bobSpkPub,
      bobOpkPublic: bobOpkPub,
    );
    final resp = await X3dh.responder(
      bobIdentityX: bobId,
      bobSpkPrivate: bobSpk,
      bobOpkPrivate: bobOpk,
      aliceIdentityX: aliceIdPub,
      aliceEkPublic: init.ekPublic,
    );
    expect(resp, init.sk);
  });

  test('works without an OPK', () async {
    final init = await X3dh.initiator(
      aliceIdentityX: aliceId,
      bobIdentityX: bobIdPub,
      bobSpkPublic: bobSpkPub,
      bobOpkPublic: null,
    );
    final resp = await X3dh.responder(
      bobIdentityX: bobId,
      bobSpkPrivate: bobSpk,
      bobOpkPrivate: null,
      aliceIdentityX: aliceIdPub,
      aliceEkPublic: init.ekPublic,
    );
    expect(resp, init.sk);
  });

  test('SK with OPK differs from SK without OPK', () async {
    final withOpk = await X3dh.initiator(
      aliceIdentityX: aliceId,
      bobIdentityX: bobIdPub,
      bobSpkPublic: bobSpkPub,
      bobOpkPublic: bobOpkPub,
    );
    final withoutOpk = await X3dh.initiator(
      aliceIdentityX: aliceId,
      bobIdentityX: bobIdPub,
      bobSpkPublic: bobSpkPub,
      bobOpkPublic: null,
    );
    expect(withOpk.sk, isNot(withoutOpk.sk));
  });

  test('different OPK yields different SK', () async {
    final opk2 = await X25519().newKeyPair();
    final opk2Pub = Uint8List.fromList(
      await (await opk2.extract()).publicKey.bytes,
    );
    final a = await X3dh.initiator(
      aliceIdentityX: aliceId,
      bobIdentityX: bobIdPub,
      bobSpkPublic: bobSpkPub,
      bobOpkPublic: bobOpkPub,
    );
    final b = await X3dh.initiator(
      aliceIdentityX: aliceId,
      bobIdentityX: bobIdPub,
      bobSpkPublic: bobSpkPub,
      bobOpkPublic: opk2Pub,
    );
    expect(a.sk, isNot(b.sk));
  });

  test('wrong SPK private does not reconstruct SK', () async {
    final wrongSpk = await X25519().newKeyPair();
    final init = await X3dh.initiator(
      aliceIdentityX: aliceId,
      bobIdentityX: bobIdPub,
      bobSpkPublic: bobSpkPub,
      bobOpkPublic: null,
    );
    final resp = await X3dh.responder(
      bobIdentityX: bobId,
      bobSpkPrivate: wrongSpk,
      bobOpkPrivate: null,
      aliceIdentityX: aliceIdPub,
      aliceEkPublic: init.ekPublic,
    );
    expect(resp, isNot(init.sk));
  });

  test('SK is 32 bytes', () async {
    final init = await X3dh.initiator(
      aliceIdentityX: aliceId,
      bobIdentityX: bobIdPub,
      bobSpkPublic: bobSpkPub,
      bobOpkPublic: null,
    );
    expect(init.sk.length, 32);
  });

  test('fresh ephemeral per call', () async {
    final a = await X3dh.initiator(
      aliceIdentityX: aliceId,
      bobIdentityX: bobIdPub,
      bobSpkPublic: bobSpkPub,
      bobOpkPublic: null,
    );
    final b = await X3dh.initiator(
      aliceIdentityX: aliceId,
      bobIdentityX: bobIdPub,
      bobSpkPublic: bobSpkPub,
      bobOpkPublic: null,
    );
    expect(a.sk, isNot(b.sk));
    expect(a.ekPublic, isNot(b.ekPublic));
  });
}