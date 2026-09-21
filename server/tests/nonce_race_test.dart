import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/services/crypto_service.dart';
import 'package:p2p_chat/services/storage_service.dart';

/// Reproduces the concurrency bug and verifies the fix: concurrent
/// encryption under the same keyId must produce distinct nonces.
///
/// Without the per-keyId lock in CryptoService, this test fails when
/// the counter file is read by two futures before either writes back.
void main() {
  late Directory tmp;
  late StorageService storage;
  late CryptoService crypto;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('nonce_race_');
    storage = await StorageService.open(override: tmp);
    crypto = CryptoService(storage);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('200 concurrent encrypts on one key never reuse a nonce', () async {
    final key = SecretKey(List.filled(32, 42));
    final futures = List.generate(
      200,
      (i) => crypto.encrypt(
        utf8.encode('msg$i'),
        key,
        keyId: 'concurrent',
        aad: const [],
      ),
    );
    final results = await Future.wait(futures);
    final nonces = results.map((r) => base64Encode(r.nonce)).toSet();
    expect(nonces.length, results.length);
  });

  test('interleaved keyIds do not interfere', () async {
    final key = SecretKey(List.filled(32, 7));
    final futures = <Future>[];
    for (var i = 0; i < 50; i++) {
      futures.add(crypto.encrypt(
        utf8.encode('a$i'),
        key,
        keyId: 'key.a',
        aad: const [],
      ));
      futures.add(crypto.encrypt(
        utf8.encode('b$i'),
        key,
        keyId: 'key.b',
        aad: const [],
      ));
    }
    final results = await Future.wait(futures);
    final nonces = results
        .cast<EncryptedBox>()
        .map((r) => base64Encode(r.nonce))
        .toSet();
    expect(nonces.length, results.length);
  });
}