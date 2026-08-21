class MedicineAdherence {
  final String medicineId;
  final String medicineName;
  final String type;
  final double? adherenceRate; // percentage 0-100, or null if no logs
  final List<DoseLog> logs;

  const MedicineAdherence({
    required this.medicineId,
    required this.medicineName,
    required this.type,
    this.adherenceRate,
    required this.logs,
  });
}

class DoseLog {
  final String date; // yyyy-MM-dd
  final String time; // HH:mm
  final String status; // 'Taken' or 'Skipped'
  final int? takenAt;

  const DoseLog({
    required this.date,
    required this.time,
    required this.status,
    this.takenAt,
  });
}
