import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/services/crypto_service.dart';
import 'package:p2p_chat/services/storage_service.dart';

void main() {
  late Directory tmp;
  late StorageService storage;
  late CryptoService crypto;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('crypto_test_');
    storage = await StorageService.open(override: tmp);
    crypto = CryptoService(storage);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('Ed25519', () {
    test('sign/verify round-trip', () async {
      final kp = await crypto.generateEd25519();
      final pub = await crypto.ed25519PublicBytes(kp);
      final msg = utf8.encode('hello');
      final sig = await crypto.signEd25519(kp, msg);
      expect(await crypto.verifyEd25519(pub, msg, sig), isTrue);
    });

    test('tampered message fails', () async {
      final kp = await crypto.generateEd25519();
      final pub = await crypto.ed25519PublicBytes(kp);
      final sig = await crypto.signEd25519(kp, utf8.encode('a'));
      expect(await crypto.verifyEd25519(pub, utf8.encode('b'), sig), isFalse);
    });

    test('tampered signature fails', () async {
      final kp = await crypto.generateEd25519();
      final pub = await crypto.ed25519PublicBytes(kp);
      final sig = await crypto.signEd25519(kp, utf8.encode('x'));
      final tampered = Uint8List.fromList(sig);
      tampered[0] ^= 0xFF;
      expect(
        await crypto.verifyEd25519(pub, utf8.encode('x'), tampered),
        isFalse,
      );
    });

    test('rejects malformed signature length', () async {
      final kp = await crypto.generateEd25519();
      final pub = await crypto.ed25519PublicBytes(kp);
      expect(
        await crypto.verifyEd25519(pub, utf8.encode('x'), Uint8List(10)),
        isFalse,
      );
    });
  });

  group('X25519', () {
    test('both sides derive the same shared secret', () async {
      final a = await crypto.generateX25519();
      final b = await crypto.generateX25519();
      final apub = await crypto.x25519PublicBytes(a);
      final bpub = await crypto.x25519PublicBytes(b);

      final s1 = await crypto.x25519SharedSecret(a, bpub);
      final s2 = await crypto.x25519SharedSecret(b, apub);
      expect(await s1.extractBytes(), await s2.extractBytes());
    });

    test('different pairs produce different secrets', () async {
      final a = await crypto.generateX25519();
      final b = await crypto.generateX25519();
      final c = await crypto.generateX25519();
      final bpub = await crypto.x25519PublicBytes(b);
      final cpub = await crypto.x25519PublicBytes(c);

      final ab = await crypto.x25519SharedSecret(a, bpub);
      final ac = await crypto.x25519SharedSecret(a, cpub);
      expect(
        await ab.extractBytes(),
        isNot(await ac.extractBytes()),
      );
    });
  });

  group('AES-256-GCM', () {
    test('encrypt/decrypt round-trip', () async {
      final key = SecretKey(List.filled(32, 7));
      final plaintext = utf8.encode('secret payload');
      final aad = utf8.encode('aad');

      final box = await crypto.encrypt(
        plaintext,
        key,
        keyId: 'test.key',
        aad: aad,
      );
      final clear = await crypto.decrypt(
        key,
        nonce: box.nonce,
        ciphertext: box.ciphertext,
        tag: box.tag,
        aad: aad,
      );
      expect(clear, plaintext);
    });

    test('tampered ciphertext fails', () async {
      final key = SecretKey(List.filled(32, 7));
      final aad = utf8.encode('aad');
      final box = await crypto.encrypt(
        utf8.encode('hello'),
        key,
        keyId: 'test.key',
        aad: aad,
      );
      final tampered = Uint8List.fromList(box.ciphertext);
      tampered[0] ^= 0xFF;
      await expectLater(
        () => crypto.decrypt(
          key,
          nonce: box.nonce,
          ciphertext: tampered,
          tag: box.tag,
          aad: aad,
        ),
        throwsA(anything),
      );
    });

    test('tampered tag fails', () async {
      final key = SecretKey(List.filled(32, 7));
      final aad = utf8.encode('aad');
      final box = await crypto.encrypt(
        utf8.encode('hello'),
        key,
        keyId: 'test.key',
        aad: aad,
      );
      final tamperedTag = Uint8List.fromList(box.tag);
      tamperedTag[0] ^= 0xFF;
      await expectLater(
        () => crypto.decrypt(
          key,
          nonce: box.nonce,
          ciphertext: box.ciphertext,
          tag: tamperedTag,
          aad: aad,
        ),
        throwsA(anything),
      );
    });

    test('tampered AAD fails', () async {
      final key = SecretKey(List.filled(32, 7));
      final box = await crypto.encrypt(
        utf8.encode('hello'),
        key,
        keyId: 'test.key',
        aad: utf8.encode('aad1'),
      );
      await expectLater(
        () => crypto.decrypt(
          key,
          nonce: box.nonce,
          ciphertext: box.ciphertext,
          tag: box.tag,
          aad: utf8.encode('aad2'),
        ),
        throwsA(anything),
      );
    });

    test('wrong key fails', () async {
      final key1 = SecretKey(List.filled(32, 7));
      final key2 = SecretKey(List.filled(32, 8));
      final box = await crypto.encrypt(
        utf8.encode('hello'),
        key1,
        keyId: 'test.key',
        aad: const [],
      );
      await expectLater(
        () => crypto.decrypt(
          key2,
          nonce: box.nonce,
          ciphertext: box.ciphertext,
          tag: box.tag,
          aad: const [],
        ),
        throwsA(anything),
      );
    });
  });

  group('key derivation', () {
    test('same context produces the same AES key', () async {
      final shared = SecretKey(List.filled(32, 3));
      final k1 = await crypto.deriveAesKey(shared, 'ctx');
      final k2 = await crypto.deriveAesKey(shared, 'ctx');
      expect(await k1.extractBytes(), await k2.extractBytes());
    });

    test('different context produces different AES key', () async {
      final shared = SecretKey(List.filled(32, 3));
      final k1 = await crypto.deriveAesKey(shared, 'ctx1');
      final k2 = await crypto.deriveAesKey(shared, 'ctx2');
      expect(await k1.extractBytes(), isNot(await k2.extractBytes()));
    });
  });

  group('nonce allocation', () {
    test('ten thousand nonces for one keyId never repeat', () async {
      final key = SecretKey(List.filled(32, 7));
      final seen = <String>{};
      for (var i = 0; i < 10000; i++) {
        final box = await crypto.encrypt(
          utf8.encode('m$i'),
          key,
          keyId: 'nonce.serial',
          aad: const [],
        );
        final n = base64Encode(box.nonce);
        expect(seen.add(n), isTrue, reason: 'nonce reuse at $i');
      }
    });

    test('nonces for different keyIds are independent', () async {
      final key = SecretKey(List.filled(32, 7));
      final a = await crypto.nextNonceFor('key.a');
      final b = await crypto.nextNonceFor('key.b');
      // They could theoretically collide by chance, but the prefixes are
      // random 4 bytes and the counters start at 0, so this is essentially
      // never.
      expect(base64Encode(a), isNot(base64Encode(b)));
    });

    test('nonce length is 12 bytes', () async {
      final n = await crypto.nextNonceFor('size.check');
      expect(n.length, 12);
    });
  });
}