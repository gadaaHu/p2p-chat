import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../models/group.dart';
import '../models/group_message.dart';
import '../models/sender_key.dart';
import 'crypto_service.dart';
import 'group_state_store.dart';
import 'identity_service.dart';
import 'ratchet/kdf.dart';
import 'sender_key_store.dart';

/// Orchestrates group messages: creation, membership changes, sender
/// key distribution, encryption, and decryption.
///
/// Group messages travel inside pairwise envelopes. The plaintext of the
/// outer envelope is a `group-msg` frame whose `ct`, `nonce`, and `tag`
/// fields are the sender-key-encrypted group content.
class GroupService {
  final CryptoService _crypto;
  final IdentityService _identity;
  final GroupStateStore _state;
  final SenderKeyStore _senderKeys;

  GroupService({
    required CryptoService crypto,
    required IdentityService identity,
    required GroupStateStore state,
    required SenderKeyStore senderKeys,
  })  : _crypto = crypto,
        _identity = identity,
        _state = state,
        _senderKeys = senderKeys;

  /// Retrieves a group's state by its ID.
  Group? groupById(String groupId) => _state.byId(groupId);

  Future<void> init() async {
    await _state.load();
    await _senderKeys.load();
  }

  // ─── Creation & membership ────────────────────────────────────────────

  Future<({Group group, List<GroupMember> recipients})> create({
    required String name,
    required List<GroupMember> members,
  }) async {
    final self = _identity.identity;
    final selfMember = GroupMember(
      deviceId: self.deviceId,
      ed25519Public: self.ed25519Public,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final all = [selfMember, ...members];
    final groupId = _newGroupId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final g = Group(
      groupId: groupId,
      epoch: 1,
      name: name,
      members: all,
      createdAt: now,
      updatedAt: now,
    );
    await _state.put(g);
    await _senderKeys.activeOrCreate(
      groupId: groupId,
      ownerDeviceId: self.deviceId,
    );
    return (group: g, recipients: members);
  }

  Future<({Group group, List<GroupMember> recipients})> addMember({
    required String groupId,
    required GroupMember member,
  }) async {
    final g = _state.byId(groupId);
    if (g == null) throw StateError('unknown group $groupId');
    if (g.contains(member.deviceId)) {
      return (group: g, recipients: const <GroupMember>[]);
    }
    final updated = g.copyWith(
      epoch: g.epoch + 1,
      members: [...g.members, member],
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _state.put(updated);
    // Rotate our sender key so the new member cannot read history.
    await _senderKeys.activeOrCreate(
      groupId: groupId,
      ownerDeviceId: _identity.identity.deviceId,
      rotate: true,
    );
    return (group: updated, recipients: updated.members);
  }

  Future<({Group group, List<GroupMember> recipients})> removeMember({
    required String groupId,
    required String deviceId,
  }) async {
    final g = _state.byId(groupId);
    if (g == null) throw StateError('unknown group $groupId');
    final updated = g.copyWith(
      epoch: g.epoch + 1,
      members:
          g.members.where((m) => m.deviceId != deviceId).toList(growable: false),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _state.put(updated);
    // Rotate our sender key so the removed member cannot read new messages.
    await _senderKeys.activeOrCreate(
      groupId: groupId,
      ownerDeviceId: _identity.identity.deviceId,
      rotate: true,
    );
    return (group: updated, recipients: updated.members);
  }

  /// Applies a group-state frame received from a peer. Advances our
  /// epoch, rotates our own sender key, and returns the recipients who
  /// need our updated sender key.
  Future<({Group group, List<GroupMember> recipients})> applyRemoteState(
    Group incoming,
  ) async {
    final existing = _state.byId(incoming.groupId);
    if (existing != null && incoming.epoch <= existing.epoch) {
      return (group: existing, recipients: const <GroupMember>[]);
    }
    await _state.put(incoming);
    await _senderKeys.activeOrCreate(
      groupId: incoming.groupId,
      ownerDeviceId: _identity.identity.deviceId,
      rotate: true,
    );
    return (group: incoming, recipients: incoming.members);
  }

  // ─── Sender key distribution ──────────────────────────────────────────

  Future<List<({GroupMember recipient, String plaintext})>>
      buildDistribution(Group group) async {
    final our = await _senderKeys.activeOrCreate(
      groupId: group.groupId,
      ownerDeviceId: _identity.identity.deviceId,
    );
    final body = jsonEncode(our.toJson());
    return [
      for (final r in group.peers(_identity.identity.deviceId))
        (recipient: r, plaintext: body),
    ];
  }

  SenderKey? parseSenderKey(String plaintext) {
    try {
      final j = jsonDecode(plaintext) as Map<String, dynamic>;
      if (j['type'] != 'sender-key') return null;
      return SenderKey.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  Future<bool> acceptSenderKey(SenderKey key) async {
    final g = _state.byId(key.groupId);
    if (g == null) return false;
    if (!g.contains(key.ownerDeviceId)) return false;
    await _senderKeys.putReceived(key);
    return true;
  }

  // ─── Message build ────────────────────────────────────────────────────

  Future<BuiltGroupMessage> buildMessage({
    required String groupId,
    required String content,
  }) async {
    final g = _state.byId(groupId);
    if (g == null) throw StateError('unknown group $groupId');
    final self = _identity.identity;

    final sk = await _senderKeys.activeOrCreate(
      groupId: groupId,
      ownerDeviceId: self.deviceId,
    );
    final seq = _senderKeys.nextSeq(groupId, self.deviceId);
    final mid = _newMessageId();

    final meta = GroupMessage(
      messageId: mid,
      groupId: groupId,
      senderDeviceId: self.deviceId,
      keyId: sk.keyId,
      senderSeq: seq,
      sentAtMs: DateTime.now().millisecondsSinceEpoch,
      content: content,
    );

    // Advance the sender chain.
    final (nextChain, messageKey) = await kdfChainKey(
      Uint8List.fromList(sk.chainKey),
    );
    await _senderKeys.updateOwnChain(
      groupId,
      sk.keyId,
      nextChain,
    );

    final aad = _groupAad(meta);
    final nonce = await _crypto.nextNonceFor('group.$groupId.${sk.keyId}');

    final box = await _crypto.encrypt(
      utf8.encode(jsonEncode({
        'message_id': mid,
        'content': content,
      })),
      SecretKey(messageKey),
      keyId: 'group.$groupId.${sk.keyId}',
      aad: aad,
      nonce: nonce,
    );

    // Advance sender sequence.
    await _senderKeys.acceptSeq(groupId, self.deviceId, seq);

    return BuiltGroupMessage(
      meta: meta,
      ciphertext: box.ciphertext,
      nonce: box.nonce,
      tag: box.tag,
    );
  }

  String wrapForRecipient(BuiltGroupMessage built) =>
      jsonEncode({
        'type': 'group-msg',
        'group_id': built.meta.groupId,
        'message_id': built.meta.messageId,
        'sender': built.meta.senderDeviceId,
        'key_id': built.meta.keyId,
        'sender_seq': built.meta.senderSeq,
        'sent_at': built.meta.sentAtMs,
        'ct': base64Encode(built.ciphertext),
        'nonce': base64Encode(built.nonce),
        'tag': base64Encode(built.tag),
      });

  // ─── Message receive ──────────────────────────────────────────────────

  Future<GroupMessage?> tryDecrypt(Map<String, dynamic> payload) async {
    if (payload['type'] != 'group-msg') return null;
    final groupId = payload['group_id'] as String?;
    final sender = payload['sender'] as String?;
    final keyId = payload['key_id'] as String?;
    final senderSeq = payload['sender_seq'] as int?;
    if (groupId == null ||
        sender == null ||
        keyId == null ||
        senderSeq == null) {
      return null;
    }

    final g = _state.byId(groupId);
    if (g == null) return null;
    if (!g.contains(sender)) return null;

    if (!await _senderKeys.acceptSeq(groupId, sender, senderSeq)) {
      return null;
    }

    final sk = _senderKeys.received(keyId);
    if (sk == null) return null;
    if (sk.groupId != groupId || sk.ownerDeviceId != sender) return null;

    final meta = GroupMessage(
      messageId: payload['message_id'] as String,
      groupId: groupId,
      senderDeviceId: sender,
      keyId: keyId,
      senderSeq: senderSeq,
      sentAtMs: payload['sent_at'] as int,
      content: '',
    );

    final (nextChain, messageKey) = await kdfChainKey(
      Uint8List.fromList(sk.chainKey),
    );
    await _senderKeys.updateReceivedChain(keyId, nextChain);

    final Uint8List clear;
    try {
      clear = await _crypto.decrypt(
        SecretKey(messageKey),
        nonce: base64Decode(payload['nonce'] as String),
        ciphertext: base64Decode(payload['ct'] as String),
        tag: base64Decode(payload['tag'] as String),
        aad: _groupAad(meta),
      );
    } catch (_) {
      return null;
    }

    final decoded = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    return GroupMessage(
      messageId: meta.messageId,
      groupId: meta.groupId,
      senderDeviceId: meta.senderDeviceId,
      keyId: meta.keyId,
      senderSeq: meta.senderSeq,
      sentAtMs: meta.sentAtMs,
      content: decoded['content'] as String,
    );
  }

  // ─── Group state framing ──────────────────────────────────────────────

  String buildStateFrame(Group g) =>
      jsonEncode({'type': 'group-state', ...g.toJson()});

  Future<Group?> parseStateFrame(String plaintext) async {
    try {
      final j = jsonDecode(plaintext) as Map<String, dynamic>;
      if (j['type'] != 'group-state') return null;
      return Group.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  Uint8List _groupAad(GroupMessage m) {
    final b = BytesBuilder();
    void add(String s) {
      final bytes = utf8.encode(s);
      final len = ByteData(4)..setUint32(0, bytes.length, Endian.big);
      b.add(len.buffer.asUint8List());
      b.add(bytes);
    }

    add(m.groupId);
    add(m.messageId);
    add(m.senderDeviceId);
    add(m.keyId);
    add(m.senderSeq.toString());
    return b.toBytes();
  }

  String _newGroupId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'g-$t-${_identity.identity.deviceId}';
  }

  String _newMessageId() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'gm-$t-${_identity.identity.deviceId}';
  }
}

class BuiltGroupMessage {
  final GroupMessage meta;
  final Uint8List ciphertext;
  final Uint8List nonce;
  final Uint8List tag;

  const BuiltGroupMessage({
    required this.meta,
    required this.ciphertext,
    required this.nonce,
    required this.tag,
  });
}