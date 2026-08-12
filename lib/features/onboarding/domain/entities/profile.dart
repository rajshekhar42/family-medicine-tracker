class Profile {
  final String id;
  final String profileName;
  final String timeZone;
  final String? avatarUrl;
  final int createdAt;
  final int? lastSync;
  final bool isOwner;
  final String? appCode;
  final String profileType; // 'Parent' or 'Caretaker'

  const Profile({
    required this.id,
    required this.profileName,
    required this.timeZone,
    this.avatarUrl,
    required this.createdAt,
    this.lastSync,
    this.isOwner = false,
    this.appCode,
    this.profileType = 'Parent',
  });

  Profile copyWith({
    String? id,
    String? profileName,
    String? timeZone,
    String? avatarUrl,
    int? createdAt,
    int? lastSync,
    bool? isOwner,
    String? appCode,
    String? profileType,
  }) {
    return Profile(
      id: id ?? this.id,
      profileName: profileName ?? this.profileName,
      timeZone: timeZone ?? this.timeZone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      lastSync: lastSync ?? this.lastSync,
      isOwner: isOwner ?? this.isOwner,
      appCode: appCode ?? this.appCode,
      profileType: profileType ?? this.profileType,
    );
  }
}
