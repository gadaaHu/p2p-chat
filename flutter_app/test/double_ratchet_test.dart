import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/services/ratchet/double_ratchet.dart';
import 'package:p2p_chat/services/ratchet/session_state.dart';

void main() {
  late DoubleRatchet dr;
  late SimpleKeyPair aliceId;
  late SimpleKeyPair bobId;
  late Uint8List bobIdPub;
  late Uint8List initialSecret;

  setUp(() async {
    dr = DoubleRatchet(
      generateKeyPair: () => X25519().newKeyPair(),
      x25519: (priv, pub) async {
        final kp = SimpleKeyPairData(priv, type: KeyPairType.x25519, publicKey: SimplePublicKey(pub, type: KeyPairType.x25519));
        final shared = await X25519().sharedSecretKey(keyPair: kp, remotePublicKey: SimplePublicKey(pub, type: KeyPairType.x25519));
        return Uint8List.fromList(await shared.extractBytes());
      },
    );
    aliceId = await X25519().newKeyPair();
    bobId = await X25519().newKeyPair();
    bobIdPub = Uint8List.fromList(
      (await bobId.extract()).publicKey.bytes,
    );

    // Shared secret = DH(aliceId, bobIdPub), matching what X3DH would produce
    // for the "no OPK" case with the identity keys used as the DH inputs.
    final shared = await X25519().sharedSecretKey(
      keyPair: aliceId,
      remotePublicKey: SimplePublicKey(bobIdPub, type: KeyPairType.x25519),
    );
    initialSecret = Uint8List.fromList(await shared.extractBytes());
  });

  test('single message round-trip', () async {
    final aliceKp = await X25519().newKeyPair();
    var a = await dr.initAlice(
      initialSecret: initialSecret,
      remoteIdentityDhPublic: bobIdPub,
      ourNewDhKeyPair: aliceKp,
    );
    final b = await dr.initBob(
      initialSecret: initialSecret,
      ourIdentityDhKeyPair: bobId,
    );

    final enc = await dr.encrypt(a);
    a = enc.next;
    final dec = await dr.decrypt(b, enc.header);
    expect(dec.messageKey, enc.messageKey);
  });

  test('reply establishes a DH ratchet', () async {
    final aliceKp = await X25519().newKeyPair();
    var a = await dr.initAlice(
      initialSecret: initialSecret,
      remoteIdentityDhPublic: bobIdPub,
      ourNewDhKeyPair: aliceKp,
    );
    var b = await dr.initBob(
      initialSecret: initialSecret,
      ourIdentityDhKeyPair: bobId,
    );

    final m1 = await dr.encrypt(a);
    a = m1.next;
    final d1 = await dr.decrypt(b, m1.header);
    b = d1.next;
    expect(d1.messageKey, m1.messageKey);

    final m2 = await dr.encrypt(b);
    b = m2.next;
    final d2 = await dr.decrypt(a, m2.header);
    a = d2.next;
    expect(d2.messageKey, m2.messageKey);
  });

  test('out-of-order within a chain', () async {
    final aliceKp = await X25519().newKeyPair();
    var a = await dr.initAlice(
      initialSecret: initialSecret,
      remoteIdentityDhPublic: bobIdPub,
      ourNewDhKeyPair: aliceKp,
    );
    var b = await dr.initBob(
      initialSecret: initialSecret,
      ourIdentityDhKeyPair: bobId,
    );

    final m1 = await dr.encrypt(a);
    a = m1.next;
    final m2 = await dr.encrypt(a);
    a = m2.next;
    final m3 = await dr.encrypt(a);
    a = m3.next;

    final d3 = await dr.decrypt(b, m3.header);
    b = d3.next;
    expect(d3.messageKey, m3.messageKey);

    final d2 = await dr.decrypt(b, m2.header);
    b = d2.next;
    expect(d2.messageKey, m2.messageKey);

    final d1 = await dr.decrypt(b, m1.header);
    b = d1.next;
    expect(d1.messageKey, m1.messageKey);
  });

  test('interleaved full duplex over 20 rounds', () async {
    final aliceKp = await X25519().newKeyPair();
    var a = await dr.initAlice(
      initialSecret: initialSecret,
      remoteIdentityDhPublic: bobIdPub,
      ourNewDhKeyPair: aliceKp,
    );
    var b = await dr.initBob(
      initialSecret: initialSecret,
      ourIdentityDhKeyPair: bobId,
    );

    for (var i = 0; i < 20; i++) {
      final ma = await dr.encrypt(a);
      a = ma.next;
      final da = await dr.decrypt(b, ma.header);
      b = da.next;
      expect(da.messageKey, ma.messageKey);

      final mb = await dr.encrypt(b);
      b = mb.next;
      final db = await dr.decrypt(a, mb.header);
      a = db.next;
      expect(db.messageKey, mb.messageKey);
    }
  });

  test('skipped keys are bounded', () async {
    final aliceKp = await X25519().newKeyPair();
    var a = await dr.initAlice(
      initialSecret: initialSecret,
      remoteIdentityDhPublic: bobIdPub,
      ourNewDhKeyPair: aliceKp,
    );
    var b = await dr.initBob(
      initialSecret: initialSecret,
      ourIdentityDhKeyPair: bobId,
    );

    RatchetHeader? last;
    for (var i = 0; i < 600; i++) {
      final m = await dr.encrypt(a);
      a = m.next;
      last = m.header;
    }
    final d = await dr.decrypt(b, last!);
    b = d.next;
    expect(
      b.skipped.length,
      lessThanOrEqualTo(RatchetSession.maxSkipped),
    );
  });

  test('state round-trips through JSON', () async {
    final aliceKp = await X25519().newKeyPair();
    var a = await dr.initAlice(
      initialSecret: initialSecret,
      remoteIdentityDhPublic: bobIdPub,
      ourNewDhKeyPair: aliceKp,
    );
    final m = await dr.encrypt(a);
    a = m.next;
    final decoded = RatchetSession.fromJson(
      jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
    );
    final m2 = await dr.encrypt(decoded);
    expect(m2.messageKey, isNotEmpty);
  });

  test('message numbers advance monotonically', () async {
    final aliceKp = await X25519().newKeyPair();
    var a = await dr.initAlice(
      initialSecret: initialSecret,
      remoteIdentityDhPublic: bobIdPub,
      ourNewDhKeyPair: aliceKp,
    );
    var expectedN = 0;
    for (var i = 0; i < 10; i++) {
      final m = await dr.encrypt(a);
      a = m.next;
      expect(m.header.n, expectedN);
      expectedN++;
    }
  });
}