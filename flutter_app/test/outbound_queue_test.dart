import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/models/encrypted_envelope.dart';
import 'package:p2p_chat/models/outbound_message.dart';
import 'package:p2p_chat/services/offline_relay_service.dart';
import 'package:p2p_chat/services/outbound_queue.dart';
import 'package:p2p_chat/services/storage_service.dart';

/// Fake relay that can be flipped between accept and reject.
class _FakeRelay implements OfflineRelayService {
  bool accept = true;
  int calls = 0;
  final List<EncryptedEnvelope> enqueued = [];

  @override
  Future<void> enqueue(EncryptedEnvelope envelope) async {
    calls++;
    if (!accept) throw StateError('relay down');
    enqueued.add(envelope);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

EncryptedEnvelope _env(String id) => EncryptedEnvelope(
      messageId: id,
      fromDeviceId: 'a',
      toDeviceId: 'b',
      nonce: base64Encode([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]),
      ciphertext: 'AA==',
      tag: 'AA==',
      counter: 0,
      signature: 'AA==',
    );

OutboundMessage _msg(String id) => OutboundMessage(
      messageId: id,
      peerDeviceId: 'b',
      plaintext: 'hello',
      envelope: _env(id),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      state: MessageState.queued,
      attempts: 0,
      nextAttemptAt: 0,
    );

void main() {
  late Directory tmp;
  late StorageService storage;
  late _FakeRelay relay;
  late OutboundQueue queue;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('oq_');
    storage = await StorageService.open(override: tmp);
    relay = _FakeRelay();
    queue = OutboundQueue(storage, relay);
    await queue.load();
  });

  tearDown(() async {
    queue.dispose();
  });

  test('enqueue then immediate relay accept moves to relayed', () async {
    final states = <MessageState>[];
    queue.stateChanged.listen((m) => states.add(m.state));

    await queue.enqueue(_msg('m1'));
    // Give the retry timer a microtask tick.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(queue.byId('m1')!.state, MessageState.relayed);
    expect(relay.enqueued.length, 1);
    expect(states, contains(MessageState.relayed));
  });

  test('relay failure keeps state queued and schedules backoff', () async {
    relay.accept = false;
    await queue.enqueue(_msg('m1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final m = queue.byId('m1')!;
    expect(m.state, MessageState.queued);
    expect(m.attempts, 1);
    expect(m.nextAttemptAt, greaterThan(DateTime.now().millisecondsSinceEpoch - 100));
    expect(m.lastError, isNotNull);
  });

  test('relay recovery delivers queued messages', () async {
    relay.accept = false;
    await queue.enqueue(_msg('m1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(queue.byId('m1')!.state, MessageState.queued);

    relay.accept = true;
    // Wait for the 1-second backoff to expire, then trigger the queue.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await queue.enqueue(_msg('m2')); // triggers _scheduleRetry(immediate: true)
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(queue.byId('m1')!.state, MessageState.relayed);
    expect(queue.byId('m2')!.state, MessageState.relayed);
  });

  test('markDelivered flips state and records timestamp', () async {
    await queue.enqueue(_msg('m1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await queue.markDelivered('m1', 1234567890);
    final m = queue.byId('m1')!;
    expect(m.state, MessageState.delivered);
    expect(m.deliveredAt, 1234567890);
  });

  test('queue survives restart', () async {
    relay.accept = false;
    await queue.enqueue(_msg('m1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Simulate process restart.
    queue.dispose();
    final queue2 = OutboundQueue(storage, relay);
    await queue2.load();

    final m = queue2.byId('m1')!;
    expect(m.state, MessageState.queued);
    expect(m.attempts, 1);
    queue2.dispose();
  });

  test('blocked peer stops retry loop', () async {
    relay.accept = false;
    await queue.enqueue(_msg('m1'));
    await queue.enqueue(_msg('m2'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await queue.markAllBlockedForPeer('b');

    expect(queue.byId('m1')!.state, MessageState.blocked);
    expect(queue.byId('m2')!.state, MessageState.blocked);
  });

  test('expired queued message is marked failed', () async {
    // Insert an old message directly.
    final old = OutboundMessage(
      messageId: 'old',
      peerDeviceId: 'b',
      plaintext: 'x',
      envelope: _env('old'),
      createdAt: DateTime.now().millisecondsSinceEpoch -
          OutboundQueue.expiryMs -
          1000,
      state: MessageState.queued,
      attempts: 5,
      nextAttemptAt: 0,
    );
    await queue.enqueue(old);
    relay.accept = true;
    // Trigger process queue via a new enqueue.
    await queue.enqueue(_msg('new'));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(queue.byId('old')!.state, MessageState.failed);
    expect(queue.byId('old')!.lastError, 'expired');
  });

  test('flushOverP2P marks queued as relayed without touching relay', () async {
    relay.accept = false; // relay is down
    await queue.enqueue(_msg('m1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(queue.byId('m1')!.state, MessageState.queued);

    var sent = 0;
    await queue.flushOverP2P('b', (m) async {
      sent++;
    });

    expect(sent, 1);
    expect(queue.byId('m1')!.state, MessageState.relayed);
  });
}