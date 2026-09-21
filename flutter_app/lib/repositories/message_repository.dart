import 'dart:convert';
import 'dart:typed_data';

import '../models/group_message.dart';
import '../models/message.dart';

/// Single source of truth for message persistence. The UI reads from here;
/// nothing else touches the per-message files directly.
///
/// Two record types share the store:
///   `msg.<id>.json`        — 1:1 incoming message
///   `group.msg.<id>.json`  — group message
///
/// Outgoing messages are not stored here; their authoritative record is
/// the outbound queue. The UI builds the outgoing view from
/// `OutboundMessage` directly.
class MessageRepository {
  static const _prefix = 'msg.';
  static const _groupPrefix = 'group.msg.';
  static const _suffix = '.json';
  static const _indexFile = 'message_index.json';
  static const _maxPerConversation = 5000;

  final StorageRef _storage;
  final List<String> _index = [];
  final Set<String> _indexSet = {};
  final Map<String, Message> _cache = {};
  bool _loaded = false;

  MessageRepository(this._storage);

  Future<void> load() async {
    if (_loaded) return;
    final raw = await _storage.read(_indexFile);
    if (raw != null) {
      final list = (jsonDecode(utf8.decode(raw)) as List).cast<String>();
      _index
        ..clear()
        ..addAll(list);
      _indexSet
        ..clear()
        ..addAll(list);
    }
    _loaded = true;
  }

  /// Incoming 1:1 message. [transport] is informational.
  Future<void> save1to1({
    required Message message,
    required String transport,
  }) async {
    await load();
    await _storage.writeAtomic(
      '$_prefix${message.id}$_suffix',
      utf8.encode(jsonEncode({
        'kind': '1to1',
        'id': message.id,
        'conversation_id': message.conversationId,
        'sender': message.senderDeviceId,
        'text': message.text,
        'at': message.timestamp.millisecondsSinceEpoch,
        'transport': transport,
      })),
    );
    _indexSet.add(message.id);
    _index.add(message.id);
    _cache[message.id] = message;
    await _trimConversation(message.conversationId);
    await _persistIndex();
  }

  Future<void> saveGroup({
    required GroupMessage message,
    required String conversationId,
    required String transport,
  }) async {
    await load();
    await _storage.writeAtomic(
      '$_groupPrefix${message.messageId}$_suffix',
      utf8.encode(jsonEncode({
        'kind': 'group',
        'id': message.messageId,
        'conversation_id': conversationId,
        'group_id': message.groupId,
        'sender': message.senderDeviceId,
        'key_id': message.keyId,
        'sender_seq': message.senderSeq,
        'text': message.content,
        'at': message.sentAtMs,
        'transport': transport,
      })),
    );
    _indexSet.add(message.messageId);
    _index.add(message.messageId);
    _cache[message.messageId] = Message(
      id: message.messageId,
      conversationId: conversationId,
      isGroup: true,
      senderDeviceId: message.senderDeviceId,
      text: message.content,
      isMe: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(message.sentAtMs),
    );
    await _trimConversation(conversationId);
    await _persistIndex();
  }

  Future<Message?> byId(String messageId) async {
    final cached = _cache[messageId];
    if (cached != null) return cached;
    await load();
    final loaded = await _read(messageId);
    if (loaded != null) _cache[messageId] = loaded;
    return loaded;
  }

  /// All messages in a conversation, oldest first.
  Future<List<Message>> forConversation(String conversationId) async {
    await load();
    final result = <Message>[];
    for (final id in _index) {
      final m = _cache[id] ?? await _read(id);
      if (m == null) continue;
      _cache[id] = m;
      if (m.conversationId == conversationId) result.add(m);
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  Future<void> delete(String messageId) async {
    await load();
    await _storage.delete('$_prefix$messageId$_suffix');
    await _storage.delete('$_groupPrefix$messageId$_suffix');
    _cache.remove(messageId);
    _index.remove(messageId);
    _indexSet.remove(messageId);
    await _persistIndex();
  }

  Future<void> deleteConversation(String conversationId) async {
    await load();
    final toRemove = <String>[];
    for (final id in _index) {
      final m = _cache[id] ?? await _read(id);
      if (m?.conversationId == conversationId) toRemove.add(id);
    }
    for (final id in toRemove) {
      await delete(id);
    }
  }

  Future<Message?> _read(String id) async {
    final raw = await _storage.read('$_prefix$id$_suffix') ??
        await _storage.read('$_groupPrefix$id$_suffix');
    if (raw == null) return null;
    try {
      final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final isGroup = j['kind'] == 'group';
      return Message(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        isGroup: isGroup,
        senderDeviceId: j['sender'] as String?,
        text: j['text'] as String,
        isMe: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _trimConversation(String conversationId) async {
    final ids = <String>[];
    for (final id in _index) {
      final m = _cache[id];
      if (m?.conversationId == conversationId) ids.add(id);
    }
    if (ids.length <= _maxPerConversation) return;
    final excess = ids.length - _maxPerConversation;
    for (var i = 0; i < excess; i++) {
      await delete(ids[i]);
    }
  }

  Future<void> _persistIndex() async {
    while (_index.length > _maxPerConversation * 20) {
      _index.removeAt(0);
    }
    await _storage.writeAtomic(
      _indexFile,
      utf8.encode(jsonEncode(_index)),
    );
  }
}

/// Narrow interface so this file does not import `StorageService`
/// directly and tests can inject a fake.
abstract class StorageRef {
  Future<Uint8List?> read(String name);
  Future<void> writeAtomic(String name, List<int> bytes);
  Future<void> delete(String name);
}