import '../../domain/entities/profile.dart';

class ProfileModel extends Profile {
  final int updatedAt;
  final int isDirty;

  const ProfileModel({
    required super.id,
    required super.profileName,
    required super.timeZone,
    super.avatarUrl,
    required super.createdAt,
    super.lastSync,
    required super.isOwner,
    super.appCode,
    super.profileType,
    required this.updatedAt,
    required this.isDirty,
  });

  factory ProfileModel.fromProfile(Profile profile, {bool? isOwner, int isDirty = 1, int? updatedAt}) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return ProfileModel(
      id: profile.id,
      profileName: profile.profileName,
      timeZone: profile.timeZone,
      avatarUrl: profile.avatarUrl,
      createdAt: profile.createdAt,
      lastSync: profile.lastSync,
      isOwner: isOwner ?? profile.isOwner,
      appCode: profile.appCode,
      profileType: profile.profileType,
      updatedAt: updatedAt ?? now,
      isDirty: isDirty,
    );
  }

  factory ProfileModel.fromMap(Map<String, dynamic> map) {
    return ProfileModel(
      id: map['id'] as String,
      profileName: map['profile_name'] as String,
      timeZone: map['time_zone'] as String,
      avatarUrl: map['avatar_url'] as String?,
      createdAt: map['created_at'] as int,
      lastSync: map['last_sync'] as int?,
      isOwner: (map['is_owner'] as int) == 1,
      appCode: map['app_code'] as String?,
      profileType: (map['profile_type'] as String?) ?? 'Parent',
      updatedAt: map['updated_at'] as int,
      isDirty: map['is_dirty'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'profile_name': profileName,
      'time_zone': timeZone,
      'avatar_url': avatarUrl,
      'created_at': createdAt,
      'last_sync': lastSync,
      'is_owner': isOwner ? 1 : 0,
      'app_code': appCode,
      'profile_type': profileType,
      'updated_at': updatedAt,
      'is_dirty': isDirty,
    };
  }

  Profile toEntity() {
    return Profile(
      id: id,
      profileName: profileName,
      timeZone: timeZone,
      avatarUrl: avatarUrl,
      createdAt: createdAt,
      lastSync: lastSync,
      isOwner: isOwner,
      appCode: appCode,
      profileType: profileType,
    );
  }
}
