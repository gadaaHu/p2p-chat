import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/encrypted_envelope.dart';
import '../models/group.dart';
import '../models/group_message.dart';
import '../models/identity_pin.dart';
import '../models/message.dart';
import '../models/outbound_message.dart';
import '../repositories/message_repository.dart';
import 'crypto_service.dart';
import 'dedupe_store.dart';
import 'group_service.dart';
import 'group_state_store.dart';
import 'identity_service.dart';
import 'manual_signaling_service.dart';
import 'outbound_queue.dart';
import 'peer_registry.dart';
import 'pinning_policy.dart';
import 'prekey_service.dart';
import 'ratchet/double_ratchet.dart';
import 'ratchet/ratchet_store.dart';
import 'receipt_service.dart';
import 'replay_guard.dart';
import 'sender_key_store.dart';
import 'settings_service.dart';
import 'storage_service.dart';
import 'unread_store.dart';
import 'webrtc_manager.dart';
import 'x3dh.dart';

/// A pending identity rotation. Held in memory until the user resolves it.
class PendingRotation {
  final String deviceId;
  final Uint8List ed25519Public;
  final Uint8List x25519Public;
  final Uint8List previousEd25519;
  final DateTime detectedAt;

  PendingRotation({
    required this.deviceId,
    required this.ed25519Public,
    required this.x25519Public,
    required this.previousEd25519,
    required this.detectedAt,
  });
}

/// A security-relevant event that the UI should surface or log.
class SecurityEvent {
  final String kind;
  final String? peerDeviceId;
  final String? detail;
  final DateTime at;

  SecurityEvent({
    required this.kind,
    this.peerDeviceId,
    this.detail,
    DateTime? at,
  }) : at = at ?? DateTime.now();
}

/// The single object the UI talks to. Wires crypto, transport, storage,
/// receipts, and groups together and enforces the invariants:
///
///   - persist before emit
///   - persist before receipt
///   - ratchet state persisted before the message key is used
///   - replay guard checked before signature verification
///   - pin evaluated before ratchet initialization
class SessionManager {
  final StorageService storage;
  final CryptoService crypto;
  final IdentityService identity;
  final PeerRegistry peers;
  final PinningPolicy pins;
  final ReplayGuard replay;
  final DedupeStore dedupe;
  final MessageRepository messageRepo;
  final OutboundQueue queue;
  final ReceiptService receipts;
  final UnreadStore unread;
  final SettingsService settings;
  final PreKeyService prekeys;
  final RatchetStore ratchets;
  final DoubleRatchet ratchet;
  final GroupService groups;
  final GroupStateStore groupState;
  final SenderKeyStore senderKeys;
  final WebRTCManager webrtc;
  final ManualSignalingService signaling;

  String get selfDeviceId => identity.identity.deviceId;

  // ─── Event streams ────────────────────────────────────────────────────

  final _incomingMessages = StreamController<String>.broadcast();
  final _groupMessages = StreamController<GroupMessage>.broadcast();
  final _identityChanged = StreamController<String>.broadcast();
  final _securityEvents = StreamController<SecurityEvent>.broadcast();

  /// Incoming 1:1 chat text from any peer. The UI subscribes per-chat and
  /// filters on the peer ID it cares about.
  Stream<String> get messages => _incomingMessages.stream;

  Stream<GroupMessage> get groupMessages => _groupMessages.stream;

  /// Emitted when a peer presents an identity that differs from the pin.
  /// The UI must show a warning and either accept or reject.
  Stream<String> get identityChanged => _identityChanged.stream;

  /// Structured security events, for diagnostics.
  Stream<SecurityEvent> get securityEvents => _securityEvents.stream;

  Stream<OutboundMessage> get outboundState => queue.stateChanged;

  // ─── Internal state ───────────────────────────────────────────────────

  /// Peers whose chat screen is currently visible. Drives read receipts.
  final Set<String> _visiblePeers = {};

  /// Pending identity rotations, waiting for user resolution.
  final Map<String, PendingRotation> _pendingRotations = {};

  /// Peers blocked because the user rejected a rotation.
  final Set<String> _rejectedPeers = {};

  /// Per-peer read-receipt debounce timers.
  final Map<String, Timer> _readTimers = {};
  static const _readFlushDelay = Duration(milliseconds: 800);

  /// Prekey header waiting to ride the next outbound envelope. Set when
  /// we initiate, cleared once sent.
  final Map<String, PreKeyHeader> _pendingPreKey = {};

  StreamSubscription<String>? _dcSub;

  SessionManager({
    required this.storage,
    required this.crypto,
    required this.identity,
    required this.peers,
    required this.pins,
    required this.replay,
    required this.dedupe,
    required this.messageRepo,
    required this.queue,
    required this.receipts,
    required this.unread,
    required this.settings,
    required this.prekeys,
    required this.ratchets,
    required this.ratchet,
    required this.groups,
    required this.groupState,
    required this.senderKeys,
    required this.webrtc,
    required this.signaling,
  });

  // ─── Lifecycle ────────────────────────────────────────────────────────

  Future<void> start() async {
    await identity.loadOrCreate();
    await peers.load();
    await pins.load();
    await replay.load();
    await dedupe.load();
    await messageRepo.load();
    await queue.load();
    await unread.load();
    await settings.load();
    await prekeys.loadOrGenerate();
    await groups.init();

    _dcSub = webrtc.messages.listen(_onDataChannelMessage);
  }

  void onResume() {
    // No polling to restart in a serverless app. This hook exists for
    // symmetry and for future LAN-discovery features.
  }

  Future<void> onPause() async {
    for (final peer in _visiblePeers.toList()) {
      await _flushReadReceipts(peer);
    }
  }

  Future<void> dispose() async {
    for (final t in _readTimers.values) {
      t.cancel();
    }
    _readTimers.clear();
    await _dcSub?.cancel();

    await webrtc.dispose();
    await _incomingMessages.close();
    await _groupMessages.close();
    await _identityChanged.close();
    await _securityEvents.close();
    queue.dispose();
  }

  // ─── Pairing ──────────────────────────────────────────────────────────

  /// Called by PairScreen after a data channel opens and the identity
  /// handshake completes on both sides.
  Future<void> onChannelReady(String peerDeviceId) async {
    // Ensure we have a ratchet session. If not, run X3DH initiation.
    await _ensureRatchet(peerDeviceId);
    await _sendIdentityHandshake(peerDeviceId);
    // Flush any messages that were queued while the peer was offline.
    await queue.flushOverP2P(peerDeviceId, _sendP2P);
    // Any pending read receipts can now go out too.
    await _flushReadReceipts(peerDeviceId);
  }

  // ─── Chat ─────────────────────────────────────────────────────────────

  Future<List<Message>> messagesFor(String peerDeviceId) =>
      messageRepo.forConversation(peerDeviceId);

  Future<String> sendMessage(String peerDeviceId, String plaintext) async {
    final pin = await pins.pinFor(peerDeviceId);
    if (pin == null) {
      throw StateError('peer $peerDeviceId is not paired');
    }
    if (_rejectedPeers.contains(peerDeviceId)) {
      throw StateError('peer $peerDeviceId is blocked');
    }

    final envelope = await _buildEnvelope(peerDeviceId, plaintext);
    final row = OutboundMessage(
      messageId: envelope.messageId,
      peerDeviceId: peerDeviceId,
      plaintext: plaintext,
      envelope: envelope,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      state: MessageState.queued,
      attempts: 0,
      nextAttemptAt: 0,
    );
    await queue.enqueue(row);
    unawaited(queue.flushOverP2P(peerDeviceId, _sendP2P));
    return envelope.messageId;
  }

  int unreadFor(String peerDeviceId) => unread.unreadFor(peerDeviceId);
  int totalUnread() => unread.totalUnread();

  void setPeerVisible(String peerDeviceId, bool visible) {
    if (visible) {
      _visiblePeers.add(peerDeviceId);
      unawaited(_scheduleReadFlush(peerDeviceId));
    } else {
      _visiblePeers.remove(peerDeviceId);
      unawaited(_flushReadReceipts(peerDeviceId));
    }
  }

  Future<void> flushAllReadReceipts() async {
    for (final peer in _visiblePeers.toList()) {
      await _flushReadReceipts(peer);
    }
  }

  // ─── Identity management ──────────────────────────────────────────────

  PendingRotation? pendingRotation(String deviceId) =>
      _pendingRotations[deviceId];

  Future<void> markVerified(String peerDeviceId) =>
      pins.markVerified(peerDeviceId);

  Future<void> acceptRotation(String deviceId) async {
    final pending = _pendingRotations.remove(deviceId);
    if (pending == null) return;
    await pins.pin(
      deviceId: deviceId,
      ed25519Public: pending.ed25519Public,
      x25519Public: pending.x25519Public,
    );
    await pins.markVerified(deviceId);
    await _invalidatePeerState(deviceId);
    _rejectedPeers.remove(deviceId);
    // Re-handshake with the new identity.
    await _ensureRatchet(deviceId);
  }

  Future<void> rejectRotation(String deviceId) async {
    _pendingRotations.remove(deviceId);
    _rejectedPeers.add(deviceId);
    await _invalidatePeerState(deviceId);
    await queue.markAllBlockedForPeer(deviceId);
  }

  Future<void> forgetPeer(String deviceId) async {
    _pendingRotations.remove(deviceId);
    _rejectedPeers.remove(deviceId);
    await pins.forget(deviceId);
    await peers.remove(deviceId);
    await _invalidatePeerState(deviceId);
  }

  Future<void> _invalidatePeerState(String deviceId) async {
    _readTimers.remove(deviceId)?.cancel();
    await ratchets.delete(deviceId);
    await replay.forget(deviceId);
    _pendingPreKey.remove(deviceId);
  }

  // ─── Groups ───────────────────────────────────────────────────────────

  Group? groupById(String groupId) => groupState.byId(groupId);
  List<Group> allGroups() => groupState.all();

  Future<Group> createGroup({
    required String name,
    required List<GroupMember> members,
  }) async {
    final result = await groups.create(name: name, members: members);
    await _distributeGroup(result.group, result.recipients);
    return result.group;
  }

  Future<Group> addGroupMember(String groupId, GroupMember member) async {
    final result = await groups.addMember(groupId: groupId, member: member);
    await _distributeGroup(result.group, result.recipients);
    return result.group;
  }

  Future<Group> removeGroupMember(String groupId, String deviceId) async {
    final result = await groups.removeMember(
      groupId: groupId,
      deviceId: deviceId,
    );
    await _distributeGroup(result.group, result.recipients);
    return result.group;
  }

  Future<void> _distributeGroup(
    Group group,
    List<GroupMember> recipients,
  ) async {
    final stateFrame = groups.buildStateFrame(group);
    for (final r in recipients) {
      if (r.deviceId == selfDeviceId) continue;
      await _enqueueFrame(r.deviceId, stateFrame, isGroupState: true);
    }
    final dist = await groups.buildDistribution(group);
    for (final d in dist) {
      await _enqueueFrame(d.recipient.deviceId, d.plaintext, isSenderKey: true);
    }
  }

  Future<String> sendGroupMessage(String groupId, String content) async {
    final g = groupState.byId(groupId);
    if (g == null) throw StateError('unknown group $groupId');
    final built = await groups.buildMessage(
      groupId: groupId,
      content: content,
    );
    final payload = groups.wrapForRecipient(built);
    final recipients = g.peers(selfDeviceId);
    final logicalId = built.meta.messageId;

    for (final r in recipients) {
      final envelope = await _buildEnvelopeWithPlaintext(r.deviceId, payload);
      final row = OutboundMessage(
        messageId: envelope.messageId,
        peerDeviceId: r.deviceId,
        plaintext: content,
        envelope: envelope,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        state: MessageState.queued,
        attempts: 0,
        nextAttemptAt: 0,
        logicalId: logicalId,
        fanoutRecipientId: r.deviceId,
      );
      await queue.enqueue(row);
      unawaited(queue.flushOverP2P(r.deviceId, _sendP2P));
    }
    return logicalId;
  }

  // ─── Envelope construction ────────────────────────────────────────────

  Future<EncryptedEnvelope> _buildEnvelope(
    String peerDeviceId,
    String plaintext,
  ) async {
    await _ensureRatchet(peerDeviceId);
    final session = (await ratchets.get(peerDeviceId))!;
    final step = await ratchet.encrypt(session);
    // Persist the advanced ratchet state before using the message key.
    await ratchets.put(peerDeviceId, step.next);

    final messageId = _newMessageId();
    // Counter derived from the ratchet's nSend, not a parallel counter.
    final counter = step.header.n;
    final nonce = await crypto.nextNonceFor('session.$peerDeviceId');

    final preKeyHeader = _pendingPreKey.remove(peerDeviceId);
    final ratchetJson = step.header.toJson();

    final headerBytes = EncryptedEnvelope(
      messageId: messageId,
      fromDeviceId: selfDeviceId,
      toDeviceId: peerDeviceId,
      nonce: base64Encode(nonce),
      ciphertext: '',
      tag: '',
      counter: counter,
      signature: '',
      ratchet: ratchetJson,
      prekey: preKeyHeader?.toJson(),
    ).canonicalHeader();

    final box = await crypto.encrypt(
      utf8.encode(plaintext),
      SecretKey(step.messageKey),
      keyId: 'ratchet.$peerDeviceId',
      aad: headerBytes,
      nonce: nonce,
    );

    final partial = EncryptedEnvelope(
      messageId: messageId,
      fromDeviceId: selfDeviceId,
      toDeviceId: peerDeviceId,
      nonce: base64Encode(box.nonce),
      ciphertext: base64Encode(box.ciphertext),
      tag: base64Encode(box.tag),
      counter: counter,
      signature: '',
      ratchet: ratchetJson,
      prekey: preKeyHeader?.toJson(),
    );

    final sig = await crypto.signEd25519(
      identity.ed25519KeyPair,
      partial.canonicalHeader(),
    );

    return EncryptedEnvelope(
      messageId: messageId,
      fromDeviceId: selfDeviceId,
      toDeviceId: peerDeviceId,
      nonce: partial.nonce,
      ciphertext: partial.ciphertext,
      tag: partial.tag,
      counter: partial.counter,
      signature: base64Encode(sig),
      ratchet: ratchetJson,
      prekey: preKeyHeader?.toJson(),
    );
  }

  Future<EncryptedEnvelope> _buildEnvelopeWithPlaintext(
    String peerDeviceId,
    String payload,
  ) =>
      _buildEnvelope(peerDeviceId, payload);

  Future<void> _enqueueFrame(
    String peerDeviceId,
    String payload, {
    bool isGroupState = false,
    bool isSenderKey = false,
  }) async {
    final envelope = await _buildEnvelopeWithPlaintext(peerDeviceId, payload);
    final label = isGroupState
        ? '(group-state)'
        : isSenderKey
            ? '(sender-key)'
            : '(frame)';
    final row = OutboundMessage(
      messageId: envelope.messageId,
      peerDeviceId: peerDeviceId,
      plaintext: label,
      envelope: envelope,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      state: MessageState.queued,
      attempts: 0,
      nextAttemptAt: 0,
    );
    await queue.enqueue(row);
    unawaited(queue.flushOverP2P(peerDeviceId, _sendP2P));
  }

  Future<void> _sendP2P(OutboundMessage m) async {
    if (!webrtc.isDataChannelOpen) {
      throw StateError('data channel not open');
    }
    await webrtc.send(jsonEncode(m.envelope.toJson()));
  }

  // ─── Ratchet initialization ───────────────────────────────────────────

  Future<void> _ensureRatchet(String peerDeviceId) async {
    final existing = await ratchets.get(peerDeviceId);
    if (existing != null) return;

    final pin = await pins.pinFor(peerDeviceId);
    if (pin == null) {
      throw StateError('no pinned identity for $peerDeviceId');
    }

    // The initiator is the device with the lexicographically smaller ID.
    // Both sides agree without a round trip.
    final weInitiate = selfDeviceId.compareTo(peerDeviceId) < 0;

    // Initial shared secret from identity X25519 ECDH.
    final shared = await crypto.x25519SharedSecret(
      identity.x25519KeyPair,
      pin.x25519Public,
    );
    final secret = Uint8List.fromList(await shared.extractBytes());

    if (weInitiate) {
      // We use our own prekey bundle when we are the responder. When we
      // initiate, we use our own identity keys — X3DH with the peer's
      // pinned bundle is only needed when the peer has published one.
      // The current design: TOFU at pairing, then pure X25519 ECDH as
      // the seed. X3DH's full 4-DH variant is available via PreKeyService
      // when the peer published a bundle in their pairing QR.
      final newKp = await crypto.generateX25519();
      final session = await ratchet.initAlice(
        initialSecret: secret,
        remoteIdentityDhPublic: pin.x25519Public,
        ourNewDhKeyPair: newKp,
      );
      await ratchets.put(peerDeviceId, session);
    } else {
      final session = await ratchet.initBob(
        initialSecret: secret,
        ourIdentityDhKeyPair: identity.x25519KeyPair,
      );
      await ratchets.put(peerDeviceId, session);
    }
  }

  // ─── Identity handshake over the data channel ─────────────────────────

  Future<void> _sendIdentityHandshake(String peerDeviceId) async {
    final body = jsonEncode({
      'ed': base64Encode(identity.identity.ed25519Public),
      'x': base64Encode(identity.identity.x25519Public),
    });
    final sig = await crypto.signEd25519(
      identity.ed25519KeyPair,
      utf8.encode('identity|$selfDeviceId|$body'),
    );
    final frame = jsonEncode({
      'type': 'identity',
      'from': selfDeviceId,
      'body': body,
      'sig': base64Encode(sig),
    });
    try {
      await webrtc.send(frame);
    } catch (_) {
      // Channel closed mid-handshake: the peer will retry when they
      // reconnect. No state to roll back.
    }
  }

  // ─── Inbound ──────────────────────────────────────────────────────────

  Future<void> _onDataChannelMessage(String raw) async {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (j['type'] == 'identity') {
      await _handleIdentityFrame(j);
      return;
    }

    final EncryptedEnvelope envelope;
    try {
      envelope = EncryptedEnvelope.fromJson(j);
    } catch (_) {
      _emitSecurity('envelope_invalid', detail: j['from']?.toString());
      return;
    }
    await _processIncoming(envelope, transport: 'p2p');
  }

  Future<void> _handleIdentityFrame(Map<String, dynamic> j) async {
    final from = j['from'] as String?;
    final body = j['body'] as String?;
    final sigB64 = j['sig'] as String?;
    if (from == null || body == null || sigB64 == null) return;

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final ed = base64Decode(decoded['ed'] as String);
    final x = base64Decode(decoded['x'] as String);

    final ok = await crypto.verifyEd25519(
      ed,
      utf8.encode('identity|$from|$body'),
      base64Decode(sigB64),
    );
    if (!ok) {
      _emitSecurity('identity_signature_invalid', peerDeviceId: from);
      return;
    }

    if (_rejectedPeers.contains(from)) return;

    final state = await pins.evaluate(
      deviceId: from,
      ed25519Public: ed,
      x25519Public: x,
    );

    switch (state) {
      case PinState.unknown:
        await pins.pin(
          deviceId: from,
          ed25519Public: ed,
          x25519Public: x,
        );
        await peers.upsert(
          deviceId: from,
          displayName: from.substring(0, 6),
          ed25519Public: ed,
          x25519Public: x,
        );
        break;

      case PinState.match:
        break;

      case PinState.changed:
        final existing = await pins.pinFor(from);
        _pendingRotations[from] = PendingRotation(
          deviceId: from,
          ed25519Public: ed,
          x25519Public: x,
          previousEd25519: existing!.ed25519Public,
          detectedAt: DateTime.now(),
        );
        _identityChanged.add(from);
        _emitSecurity('identity_changed', peerDeviceId: from);
        return;
    }
  }

  Future<void> _processIncoming(
    EncryptedEnvelope env, {
    required String transport,
  }) async {
    final peer = env.fromDeviceId;

    // 1. Dedupe on message ID. A redelivery is a no-op.
    if (await dedupe.contains(env.messageId)) {
      // Still send a receipt so the sender learns delivery succeeded.
      await _sendReceipt(env.messageId, peer);
      return;
    }

    // 2. Replay window.
    if (!await replay.accept(peer, env.counter)) {
      _emitSecurity(
        'replay_rejected',
        peerDeviceId: peer,
        detail: 'counter=${env.counter}',
      );
      return;
    }

    // 3. Pin lookup.
    final pin = await pins.pinFor(peer);
    if (pin == null) {
      _emitSecurity('no_pin', peerDeviceId: peer);
      return;
    }

    // 4. Signature over the canonical header.
    final sigOk = await crypto.verifyEd25519(
      pin.ed25519Public,
      env.canonicalHeader(),
      base64Decode(env.signature),
    );
    if (!sigOk) {
      _emitSecurity('signature_invalid', peerDeviceId: peer);
      return;
    }

    // 5. Session-establishing message?
    if (env.isSessionInit) {
      await _maybeEstablishFromPreKey(env);
    }

    // 6. Ratchet advance.
    final session = await ratchets.get(peer);
    if (session == null) {
      _emitSecurity('no_ratchet', peerDeviceId: peer);
      return;
    }
    final headerJson = env.ratchet;
    if (headerJson == null) {
      _emitSecurity('missing_ratchet', peerDeviceId: peer);
      return;
    }
    final step;
    try {
      step = await ratchet.decrypt(
        session,
        RatchetHeader.fromJson(headerJson),
      );
    } catch (e) {
      _emitSecurity(
        'ratchet_failed',
        peerDeviceId: peer,
        detail: e.toString(),
      );
      return;
    }
    await ratchets.put(peer, step.next);

    // 7. Decrypt.
    final Uint8List clear;
    try {
      clear = await crypto.decrypt(
        SecretKey(step.messageKey),
        nonce: base64Decode(env.nonce),
        ciphertext: base64Decode(env.ciphertext),
        tag: base64Decode(env.tag),
        aad: env.canonicalHeader(),
      );
    } catch (_) {
      _emitSecurity('decrypt_failed', peerDeviceId: peer);
      return;
    }

    // 8. Dispatch by plaintext type.
    await _dispatchPlaintext(peer, env, clear, transport);
  }

  Future<void> _maybeEstablishFromPreKey(EncryptedEnvelope env) async {
    final peer = env.fromDeviceId;
    final existing = await ratchets.get(peer);
    if (existing != null) return; // already have a session

    final header = PreKeyHeader.fromJson(env.prekey!);
    final spk = await prekeys.spkById(header.spkId);
    if (spk == null) {
      _emitSecurity(
        'spk_missing',
        peerDeviceId: peer,
        detail: 'spk_id=${header.spkId}',
      );
      return;
    }
    SimpleKeyPair? opk;
    if (header.opkId != null) {
      opk = await prekeys.takeOpkById(header.opkId!);
    }

    final sk = await X3dh.responder(
      bobIdentityX: identity.x25519KeyPair,
      bobSpkPrivate: spk,
      bobOpkPrivate: opk,
      aliceIdentityX: header.identityX,
      aliceEkPublic: header.ephemeralX,
    );

    final session = await ratchet.initBob(
      initialSecret: sk,
      ourIdentityDhKeyPair: identity.x25519KeyPair,
    );
    await ratchets.put(peer, session);
  }

  Future<void> _dispatchPlaintext(
    String peer,
    EncryptedEnvelope env,
    Uint8List clear,
    String transport,
  ) async {
    // Receipt?
    final receipt = receipts.parse(clear);
    if (receipt != null) {
      if (receipt.isRead) {
        for (final id in receipt.messageIds) {
          await queue.markRead(id);
        }
      } else {
        for (final id in receipt.messageIds) {
          await queue.markDelivered(id, receipt.atMs);
        }
      }
      await dedupe.record(env.messageId);
      return;
    }

    // Structured frame?
    Map<String, dynamic>? asMap;
    try {
      final v = jsonDecode(utf8.decode(clear));
      if (v is Map<String, dynamic>) asMap = v;
    } catch (_) {
      asMap = null;
    }

    if (asMap != null) {
      final t = asMap['type'];
      if (t == 'sender-key') {
        final key = groups.parseSenderKey(utf8.decode(clear));
        if (key != null) await groups.acceptSenderKey(key);
        await dedupe.record(env.messageId);
        await _sendReceipt(env.messageId, peer);
        return;
      }
      if (t == 'group-state') {
        final g = await groups.parseStateFrame(utf8.decode(clear));
        if (g != null) {
          final applied = await groups.applyRemoteState(g);
          // Redistribute our own sender key if the epoch advanced.
          if (applied.recipients.isNotEmpty) {
            await _distributeGroup(applied.group, applied.recipients);
          }
        }
        await dedupe.record(env.messageId);
        await _sendReceipt(env.messageId, peer);
        return;
      }
      if (t == 'group-msg') {
        final gm = await groups.tryDecrypt(asMap);
        if (gm == null) {
          _emitSecurity('group_decrypt_failed', peerDeviceId: peer);
          return;
        }
        // Persist, then emit.
        await messageRepo.saveGroup(
          message: gm,
          conversationId: gm.groupId,
          transport: transport,
        );
        await dedupe.record(env.messageId);
        _groupMessages.add(gm);
        await _sendReceipt(env.messageId, peer);
        return;
      }
    }

    // Plain chat message.
    final text = utf8.decode(clear);
    final msg = Message(
      id: env.messageId,
      conversationId: peer,
      isGroup: false,
      senderDeviceId: peer,
      text: text,
      isMe: false,
      timestamp: DateTime.now(),
    );
    // Persist first, then update state.
    await messageRepo.save1to1(message: msg, transport: transport);
    await dedupe.record(env.messageId);
    await unread.recordReceived(peer, env.messageId);

    if (_visiblePeers.contains(peer)) {
      await unread.markDisplayed(peer, [env.messageId]);
      unawaited(_scheduleReadFlush(peer));
    }

    _incomingMessages.add(text);
    await _sendReceipt(env.messageId, peer);
  }

  // ─── Receipts ─────────────────────────────────────────────────────────

  Future<void> _sendReceipt(String messageId, String peer) async {
    try {
      final plaintext = receipts.buildDeliveryPlaintext(messageId);
      await _enqueueFrame(
        peer,
        utf8.decode(plaintext),
        isSenderKey: false,
        isGroupState: false,
      );
    } catch (_) {
      // Receipt failure is not fatal; the sender's UI shows "relayed"
      // instead of "delivered" until retry succeeds.
    }
  }

  Future<void> _scheduleReadFlush(String peerDeviceId) async {
    _readTimers[peerDeviceId]?.cancel();
    _readTimers[peerDeviceId] = Timer(
      _readFlushDelay,
      () => unawaited(_flushReadReceipts(peerDeviceId)),
    );
  }

  Future<void> _flushReadReceipts(String peerDeviceId) async {
    _readTimers.remove(peerDeviceId)?.cancel();

    if (!settings.readReceiptsEnabled) {
      await unread.takePending(peerDeviceId);
      return;
    }

    final ids = await unread.takePending(peerDeviceId);
    if (ids.isEmpty) return;
    try {
      final plaintext = receipts.buildReadPlaintext(ids);
      await _enqueueFrame(peerDeviceId, utf8.decode(plaintext));
    } catch (_) {
      // Best effort. Losing a read receipt shows "delivered" instead of
      // "read" on the sender's side.
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  String _newMessageId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return '$t-$selfDeviceId';
  }

  void _emitSecurity(
    String kind, {
    String? peerDeviceId,
    String? detail,
  }) {
    _securityEvents.add(SecurityEvent(
      kind: kind,
      peerDeviceId: peerDeviceId,
      detail: detail,
    ));
  }
}

void unawaited(Future<void> f) {}