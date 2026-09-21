/// The local user's editable profile. Distinct from `DeviceIdentity`:
/// this is what the user chooses, not what the device is.
class Profile {
  final String displayName;
  final String? avatarPath;
  final int updatedAt;

  const Profile({
    required this.displayName,
    this.avatarPath,
    required this.updatedAt,
  });

  Profile copyWith({String? displayName, String? avatarPath}) => Profile(
        displayName: displayName ?? this.displayName,
        avatarPath: avatarPath ?? this.avatarPath,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Map<String, dynamic> toJson() => {
        'name': displayName,
        if (avatarPath != null) 'avatar': avatarPath,
        'updated_at': updatedAt,
      };

  static Profile fromJson(Map<String, dynamic> j) => Profile(
        displayName: j['name'] as String,
        avatarPath: j['avatar'] as String?,
        updatedAt: j['updated_at'] as int,
      );
}