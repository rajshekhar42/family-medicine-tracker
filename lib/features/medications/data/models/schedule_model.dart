import '../../domain/entities/schedule.dart';

class ScheduleModel extends Schedule {
  final int isDirty;
  final int updatedAt;

  const ScheduleModel({
    required super.id,
    required super.profileId,
    required super.medicineId,
    required super.time,
    required this.updatedAt,
    required this.isDirty,
  });

  factory ScheduleModel.fromSchedule(Schedule schedule, {int isDirty = 1, int? updatedAt}) {
    return ScheduleModel(
      id: schedule.id,
      profileId: schedule.profileId,
      medicineId: schedule.medicineId,
      time: schedule.time,
      updatedAt: updatedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch,
      isDirty: isDirty,
    );
  }

  factory ScheduleModel.fromMap(Map<String, dynamic> map) {
    return ScheduleModel(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      medicineId: map['medicine_id'] as String,
      time: map['time'] as String,
      updatedAt: map['updated_at'] as int,
      isDirty: map['is_dirty'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'profile_id': profileId,
      'medicine_id': medicineId,
      'time': time,
      'updated_at': updatedAt,
      'is_dirty': isDirty,
    };
  }

  Schedule toEntity() {
    return Schedule(
      id: id,
      profileId: profileId,
      medicineId: medicineId,
      time: time,
    );
  }
}
