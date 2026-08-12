class Schedule {
  final String id;
  final String profileId;
  final String medicineId;
  final String time; // HH:mm format

  const Schedule({
    required this.id,
    required this.profileId,
    required this.medicineId,
    required this.time,
  });

  Schedule copyWith({
    String? id,
    String? profileId,
    String? medicineId,
    String? time,
  }) {
    return Schedule(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      medicineId: medicineId ?? this.medicineId,
      time: time ?? this.time,
    );
  }
}
