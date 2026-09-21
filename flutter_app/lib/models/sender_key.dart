import 'dart:convert';

class SenderKey {
  final String groupId;
  final String ownerDeviceId; // the sender this key encrypts for
  final String keyId; // stable identifier: sha256(group|owner|version)[:16]
  final int version;
  final List<int> keyBytes; // 32-byte AES key
  final int createdAt;

  const SenderKey({
    required this.groupId,
    required this.ownerDeviceId,
    required this.keyId,
    required this.version,
    required this.keyBytes,
    required this.createdAt,
    List<int>? chainKey,
  });

  /// Alias used by the recovered sender_key_store.dart which tracks ratchet chain state.
  List<int> get chainKey => keyBytes;

  SenderKey copyWith({
    String? groupId,
    String? ownerDeviceId,
    String? keyId,
    int? version,
    List<int>? keyBytes,
    List<int>? chainKey,
    int? createdAt,
  }) =>
      SenderKey(
        groupId: groupId ?? this.groupId,
        ownerDeviceId: ownerDeviceId ?? this.ownerDeviceId,
        keyId: keyId ?? this.keyId,
        version: version ?? this.version,
        keyBytes: chainKey ?? keyBytes ?? this.keyBytes,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'type': 'sender-key',
        'group_id': groupId,
        'owner': ownerDeviceId,
        'key_id': keyId,
        'version': version,
        'key': base64Encode(keyBytes),
        'created_at': createdAt,
      };

  static SenderKey fromJson(Map<String, dynamic> j) => SenderKey(
        groupId: j['group_id'] as String,
        ownerDeviceId: j['owner'] as String,
        keyId: j['key_id'] as String,
        version: j['version'] as int,
        keyBytes: base64Decode(j['key'] as String),
        createdAt: j['created_at'] as int,
      );
}