import '../../domain/entities/app_settings.dart';

class SettingsModel extends AppSettings {
  final int updatedAt;
  final int isDirty;

  const SettingsModel({
    required super.profileId,
    required super.remindersEnabled,
    required super.soundEnabled,
    required super.gracePeriodMinutes,
    required this.updatedAt,
    required this.isDirty,
  });

  factory SettingsModel.fromAppSettings(AppSettings settings, {int isDirty = 1, int? updatedAt}) {
    return SettingsModel(
      profileId: settings.profileId,
      remindersEnabled: settings.remindersEnabled,
      soundEnabled: settings.soundEnabled,
      gracePeriodMinutes: settings.gracePeriodMinutes,
      updatedAt: updatedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch,
      isDirty: isDirty,
    );
  }

  factory SettingsModel.fromMap(Map<String, dynamic> map) {
    return SettingsModel(
      profileId: map['profile_id'] as String,
      remindersEnabled: (map['reminders_enabled'] as int) == 1,
      soundEnabled: (map['sound_enabled'] as int) == 1,
      gracePeriodMinutes: map['grace_period_minutes'] as int,
      updatedAt: map['updated_at'] as int,
      isDirty: map['is_dirty'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'profile_id': profileId,
      'reminders_enabled': remindersEnabled ? 1 : 0,
      'sound_enabled': soundEnabled ? 1 : 0,
      'grace_period_minutes': gracePeriodMinutes,
      'updated_at': updatedAt,
      'is_dirty': isDirty,
    };
  }

  AppSettings toEntity() {
    return AppSettings(
      profileId: profileId,
      remindersEnabled: remindersEnabled,
      soundEnabled: soundEnabled,
      gracePeriodMinutes: gracePeriodMinutes,
    );
  }
}
