import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/models/identity_pin.dart';
import 'package:p2p_chat/services/pinning_policy.dart';
import 'package:p2p_chat/services/storage_service.dart';

void main() {
  late Directory tmp;
  late StorageService storage;
  late PinningPolicy pins;

  final edA = Uint8List.fromList(List.filled(32, 1));
  final xA = Uint8List.fromList(List.filled(32, 2));
  final edB = Uint8List.fromList(List.filled(32, 3));
  final xB = Uint8List.fromList(List.filled(32, 4));

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pin_');
    storage = await StorageService.open(override: tmp);
    pins = PinningPolicy(storage);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('unknown peer returns PinState.unknown', () async {
    final s = await pins.evaluate(
      deviceId: 'peer',
      ed25519Public: edA,
      x25519Public: xA,
    );
    expect(s, PinState.unknown);
  });

  test('pin then evaluate returns match', () async {
    await pins.pin(deviceId: 'peer', ed25519Public: edA, x25519Public: xA);
    final s = await pins.evaluate(
      deviceId: 'peer',
      ed25519Public: edA,
      x25519Public: xA,
    );
    expect(s, PinState.match);
  });

  test('changed Ed25519 returns changed and does not overwrite', () async {
    await pins.pin(deviceId: 'peer', ed25519Public: edA, x25519Public: xA);
    final s = await pins.evaluate(
      deviceId: 'peer',
      ed25519Public: edB,
      x25519Public: xA,
    );
    expect(s, PinState.changed);
    final p = await pins.pinFor('peer');
    expect(p!.ed25519Public, edA);
  });

  test('changed X25519 returns changed', () async {
    await pins.pin(deviceId: 'peer', ed25519Public: edA, x25519Public: xA);
    final s = await pins.evaluate(
      deviceId: 'peer',
      ed25519Public: edA,
      x25519Public: xB,
    );
    expect(s, PinState.changed);
  });

  test('new pin starts unverified', () async {
    await pins.pin(deviceId: 'peer', ed25519Public: edA, x25519Public: xA);
    expect(await pins.isVerified('peer'), isFalse);
  });

  test('markVerified flips flag and records time', () async {
    await pins.pin(deviceId: 'peer', ed25519Public: edA, x25519Public: xA);
    await pins.markVerified('peer');
    expect(await pins.isVerified('peer'), isTrue);
    final p = await pins.pinFor('peer');
    expect(p!.verifiedAt, isNotNull);
  });

  test('re-pin resets verified', () async {
    await pins.pin(deviceId: 'peer', ed25519Public: edA, x25519Public: xA);
    await pins.markVerified('peer');
    await pins.pin(deviceId: 'peer', ed25519Public: edB, x25519Public: xA);
    expect(await pins.isVerified('peer'), isFalse);
  });

  test('verify flag survives restart', () async {
    await pins.pin(deviceId: 'peer', ed25519Public: edA, x25519Public: xA);
    await pins.markVerified('peer');
    final p2 = PinningPolicy(storage);
    await p2.load();
    expect(await p2.isVerified('peer'), isTrue);
  });

  test('pin survives restart', () async {
    await pins.pin(deviceId: 'peer', ed25519Public: edA, x25519Public: xA);
    final p2 = PinningPolicy(storage);
    await p2.load();
    final s = await p2.evaluate(
      deviceId: 'peer',
      ed25519Public: edA,
      x25519Public: xA,
    );
    expect(s, PinState.match);
  });

  test('forget clears the pin', () async {
    await pins.pin(deviceId: 'peer', ed25519Public: edA, x25519Public: xA);
    await pins.forget('peer');
    final s = await pins.evaluate(
      deviceId: 'peer',
      ed25519Public: edA,
      x25519Public: xA,
    );
    expect(s, PinState.unknown);
  });

  test('missing verified field loads as unverified', () async {
    await storage.writeAtomic(
      'identity_pins.json',
      utf8.encode(jsonEncode({
        'peer': {
          'device_id': 'peer',
          'ed': base64Encode(edA),
          'x': base64Encode(xA),
          'pinned_at': 1,
        },
      })),
    );
    final fresh = PinningPolicy(storage);
    await fresh.load();
    expect(await fresh.isVerified('peer'), isFalse);
  });
}