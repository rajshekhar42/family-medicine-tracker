class AppSettings {
  final String profileId;
  final bool remindersEnabled;
  final bool soundEnabled;
  final int gracePeriodMinutes; // E.g., 15, 30, 45, 60 minutes

  const AppSettings({
    required this.profileId,
    this.remindersEnabled = true,
    this.soundEnabled = true,
    this.gracePeriodMinutes = 30,
  });

  AppSettings copyWith({
    String? profileId,
    bool? remindersEnabled,
    bool? soundEnabled,
    int? gracePeriodMinutes,
  }) {
    return AppSettings(
      profileId: profileId ?? this.profileId,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      gracePeriodMinutes: gracePeriodMinutes ?? this.gracePeriodMinutes,
    );
  }
}
