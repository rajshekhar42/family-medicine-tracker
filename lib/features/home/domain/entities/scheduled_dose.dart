class ScheduledDose {
  final String scheduleId;
  final String medicineId;
  final String medicineName;
  final String medicineType;
  final String dosage;
  final String quantity;
  final String frequency;
  final String scheduledTime; // HH:mm 24-hour format
  final String date; // yyyy-MM-dd
  final String? logId; // Null if not logged yet
  final String? status; // 'Taken', 'Skipped', or null
  final int? takenAt; // Null if status != 'Taken'

  const ScheduledDose({
    required this.scheduleId,
    required this.medicineId,
    required this.medicineName,
    required this.medicineType,
    required this.dosage,
    required this.quantity,
    required this.frequency,
    required this.scheduledTime,
    required this.date,
    this.logId,
    this.status,
    this.takenAt,
  });

  ScheduledDose copyWith({
    String? scheduleId,
    String? medicineId,
    String? medicineName,
    String? medicineType,
    String? dosage,
    String? quantity,
    String? frequency,
    String? scheduledTime,
    String? date,
    String? logId,
    String? status,
    int? takenAt,
  }) {
    return ScheduledDose(
      scheduleId: scheduleId ?? this.scheduleId,
      medicineId: medicineId ?? this.medicineId,
      medicineName: medicineName ?? this.medicineName,
      medicineType: medicineType ?? this.medicineType,
      dosage: dosage ?? this.dosage,
      quantity: quantity ?? this.quantity,
      frequency: frequency ?? this.frequency,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      date: date ?? this.date,
      logId: logId ?? this.logId,
      status: status ?? this.status,
      takenAt: takenAt ?? this.takenAt,
    );
  }
}
