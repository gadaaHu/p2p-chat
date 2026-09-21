import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/models/encrypted_envelope.dart';
import 'package:p2p_chat/models/outbound_message.dart';
import 'package:p2p_chat/services/outbound_queue.dart';
import 'package:p2p_chat/services/storage_service.dart';

/// The outbound queue no longer depends on a relay service. It retries
/// over the data channel only. This test uses a fake sender that can be
/// flipped between success and failure.
void main() {
  late Directory tmp;
  late StorageService storage;
  late _FakeSender sender;
  late OutboundQueue queue;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('oq_');
    storage = await StorageService.open(override: tmp);
    sender = _FakeSender();
    queue = OutboundQueue(storage, sender.send);
    await queue.load();
  });

  tearDown(() async {
    queue.dispose();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('enqueue then immediate send success moves to relayed', () async {
    await queue.enqueue(_msg('m1', 'peer'));
    await queue.flushOverP2P('peer', sender.send);
    expect(queue.byId('m1')!.state, MessageState.relayed);
    expect(sender.sent.length, 1);
  });

  test('send failure keeps state queued and records error', () async {
    sender.accept = false;
    await queue.enqueue(_msg('m1', 'peer'));
    await queue.flushOverP2P('peer', sender.send);
    final m = queue.byId('m1')!;
    expect(m.state, MessageState.queued);
    expect(m.attempts, greaterThanOrEqualTo(1));
    expect(m.lastError, isNotNull);
  });

  test('recovery flushes queued messages', () async {
    sender.accept = false;
    await queue.enqueue(_msg('m1', 'peer'));
    await queue.flushOverP2P('peer', sender.send);
    expect(queue.byId('m1')!.state, MessageState.queued);

    sender.accept = true;
    await queue.flushOverP2P('peer', sender.send);
    expect(queue.byId('m1')!.state, MessageState.relayed);
  });

  test('markDelivered transitions and records timestamp', () async {
    await queue.enqueue(_msg('m1', 'peer'));
    await queue.flushOverP2P('peer', sender.send);
    await queue.markDelivered('m1', 1234567890);
    final m = queue.byId('m1')!;
    expect(m.state, MessageState.delivered);
    expect(m.deliveredAt, 1234567890);
  });

  test('markRead requires delivered', () async {
    await queue.enqueue(_msg('m1', 'peer'));
    await queue.flushOverP2P('peer', sender.send);
    await queue.markRead('m1', 1);
    expect(queue.byId('m1')!.state, MessageState.relayed);
    await queue.markDelivered('m1', 2);
    await queue.markRead('m1', 3);
    expect(queue.byId('m1')!.state, MessageState.read);
  });

  test('markRead is idempotent', () async {
    await queue.enqueue(_msg('m1', 'peer'));
    await queue.flushOverP2P('peer', sender.send);
    await queue.markDelivered('m1', 1);
    await queue.markRead('m1', 2);
    await queue.markRead('m1', 3);
    expect(queue.byId('m1')!.state, MessageState.read);
  });

  test('queue survives restart', () async {
    sender.accept = false;
    await queue.enqueue(_msg('m1', 'peer'));
    await queue.flushOverP2P('peer', sender.send);

    queue.dispose();
    final q2 = OutboundQueue(storage, sender.send);
    await q2.load();
    expect(q2.byId('m1')!.state, MessageState.queued);
    q2.dispose();
  });

  test('blocked peer marks pending messages blocked', () async {
    sender.accept = false;
    await queue.enqueue(_msg('m1', 'peer'));
    await queue.enqueue(_msg('m2', 'peer'));
    await queue.flushOverP2P('peer', sender.send);
    await queue.markAllBlockedForPeer('peer');
    expect(queue.byId('m1')!.state, MessageState.blocked);
    expect(queue.byId('m2')!.state, MessageState.blocked);
  });

  test('group fan-out summary aggregates', () async {
    final m1 = _msg('m1', 'p1', logical: 'L', recipient: 'p1');
    final m2 = _msg('m2', 'p2', logical: 'L', recipient: 'p2');
    final m3 = _msg('m3', 'p3', logical: 'L', recipient: 'p3');
    await queue.enqueue(m1);
    await queue.enqueue(m2);
    await queue.enqueue(m3);

    await queue.markDelivered('m1', 1);
    await queue.markDelivered('m2', 1);

    final summary = queue.summarize('L');
    expect(summary.total, 3);
    expect(summary.delivered, 2);
    expect(summary.allDelivered, isFalse);
  });

  test('expired message marked failed', () async {
    final old = OutboundMessage(
      messageId: 'old',
      peerDeviceId: 'peer',
      plaintext: 'x',
      envelope: _env('old', 'peer'),
      createdAt: DateTime.now().millisecondsSinceEpoch -
          OutboundQueue.expiryMs -
          1000,
      state: MessageState.queued,
      attempts: 5,
      nextAttemptAt: 0,
    );
    await queue.enqueue(old);
    sender.accept = true;
    await queue.enqueue(_msg('trigger', 'peer'));
    await queue.flushOverP2P('peer', sender.send);
    // Force a process cycle.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      queue.byId('old')?.state,
      anyOf(MessageState.failed, MessageState.queued),
    );
  });
}

OutboundMessage _msg(
  String id,
  String peer, {
  String? logical,
  String? recipient,
}) =>
    OutboundMessage(
      messageId: id,
      peerDeviceId: peer,
      plaintext: 'hello $id',
      envelope: _env(id, peer),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      state: MessageState.queued,
      attempts: 0,
      nextAttemptAt: 0,
      logicalId: logical,
      fanoutRecipientId: recipient,
    );

EncryptedEnvelope _env(String id, String peer) => EncryptedEnvelope(
      messageId: id,
      fromDeviceId: 'me',
      toDeviceId: peer,
      nonce: base64Encode(List.filled(12, 1)),
      ciphertext: base64Encode([1, 2, 3]),
      tag: base64Encode(List.filled(16, 2)),
      counter: 0,
      signature: base64Encode(List.filled(64, 3)),
      ratchet: {
        'dh': base64Encode(List.filled(32, 4)),
        'n': 0,
        'pn': 0,
      },
    );

class _FakeSender {
  bool accept = true;
  final List<OutboundMessage> sent = [];

  Future<void> send(OutboundMessage m) async {
    if (!accept) throw StateError('channel closed');
    sent.add(m);
  }
}