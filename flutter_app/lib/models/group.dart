import 'dart:convert';
import 'dart:typed_data';

class GroupMember {
  final String deviceId;
  final Uint8List ed25519Public; // snapshot at the time of add
  final int addedAt;

  const GroupMember({
    required this.deviceId,
    required this.ed25519Public,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'ed': base64Encode(ed25519Public),
        'added_at': addedAt,
      };

  static GroupMember fromJson(Map<String, dynamic> j) => GroupMember(
        deviceId: j['device_id'] as String,
        ed25519Public: base64Decode(j['ed'] as String),
        addedAt: j['added_at'] as int,
      );
}

class Group {
  final String groupId;

  /// Bumped on every membership change. Used to reject stale group-state
  /// messages arriving out of order.
  final int epoch;

  final String name;
  final List<GroupMember> members;
  final int createdAt;
  final int updatedAt;

  const Group({
    required this.groupId,
    required this.epoch,
    required this.name,
    required this.members,
    required this.createdAt,
    required this.updatedAt,
  });

  Group copyWith({
    int? epoch,
    String? name,
    List<GroupMember>? members,
    int? updatedAt,
  }) =>
      Group(
        groupId: groupId,
        epoch: epoch ?? this.epoch,
        name: name ?? this.name,
        members: members ?? this.members,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Members other than us. Callers pass their own device ID.
  List<GroupMember> peers(String selfDeviceId) =>
      members.where((m) => m.deviceId != selfDeviceId).toList();

  /// Returns true if a member with [deviceId] exists in the group.
  bool contains(String deviceId) =>
      members.any((m) => m.deviceId == deviceId);

  Map<String, dynamic> toJson() => {
        'group_id': groupId,
        'epoch': epoch,
        'name': name,
        'members': members.map((m) => m.toJson()).toList(),
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  static Group fromJson(Map<String, dynamic> j) => Group(
        groupId: j['group_id'] as String,
        epoch: j['epoch'] as int,
        name: j['name'] as String,
        members: (j['members'] as List)
            .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: j['created_at'] as int,
        updatedAt: j['updated_at'] as int,
      );
}