import '../../domain/entities/scheduled_dose.dart';

class ScheduledDoseModel extends ScheduledDose {
  const ScheduledDoseModel({
    required super.scheduleId,
    required super.medicineId,
    required super.medicineName,
    required super.medicineType,
    required super.dosage,
    required super.quantity,
    required super.frequency,
    required super.scheduledTime,
    required super.date,
    super.logId,
    super.status,
    super.takenAt,
  });

  factory ScheduledDoseModel.fromMap(Map<String, dynamic> map, String date) {
    final dosageVal = map['dosage_value'];
    final dosageUnit = map['dosage_unit'] ?? '';
    final dosageStr = dosageVal != null ? '$dosageVal $dosageUnit'.trim() : '';

    final quantityVal = map['quantity_value'];
    final quantityUnit = map['quantity_unit'] ?? '';
    final quantityStr = quantityVal != null ? '$quantityVal $quantityUnit'.trim() : '';

    return ScheduledDoseModel(
      scheduleId: map['schedule_id'] as String,
      medicineId: map['medicine_id'] as String,
      medicineName: map['name'] as String,
      medicineType: map['type'] as String,
      dosage: dosageStr,
      quantity: quantityStr,
      frequency: map['frequency'] as String,
      scheduledTime: map['time'] as String,
      date: date,
      logId: map['log_id'] as String?,
      status: map['status'] as String?,
      takenAt: map['taken_at'] as int?,
    );
  }

  ScheduledDose toEntity() {
    return ScheduledDose(
      scheduleId: scheduleId,
      medicineId: medicineId,
      medicineName: medicineName,
      medicineType: medicineType,
      dosage: dosage,
      quantity: quantity,
      frequency: frequency,
      scheduledTime: scheduledTime,
      date: date,
      logId: logId,
      status: status,
      takenAt: takenAt,
    );
  }
}
