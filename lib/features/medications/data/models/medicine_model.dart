import '../../domain/entities/medicine.dart';

class MedicineModel extends Medicine {
  final int isDirty;
  final int updatedAt;

  const MedicineModel({
    required super.id,
    required super.profileId,
    required super.name,
    required super.type,
    super.dosageValue,
    super.dosageUnit,
    super.quantityValue,
    super.quantityUnit,
    required super.frequency,
    required super.startDate,
    super.endDate,
    super.notes,
    required super.active,
    required this.updatedAt,
    required this.isDirty,
  });

  factory MedicineModel.fromMedicine(Medicine medicine, {int isDirty = 1, int? updatedAt}) {
    return MedicineModel(
      id: medicine.id,
      profileId: medicine.profileId,
      name: medicine.name,
      type: medicine.type,
      dosageValue: medicine.dosageValue,
      dosageUnit: medicine.dosageUnit,
      quantityValue: medicine.quantityValue,
      quantityUnit: medicine.quantityUnit,
      frequency: medicine.frequency,
      startDate: medicine.startDate,
      endDate: medicine.endDate,
      notes: medicine.notes,
      active: medicine.active,
      updatedAt: updatedAt ?? DateTime.now().toUtc().millisecondsSinceEpoch,
      isDirty: isDirty,
    );
  }

  factory MedicineModel.fromMap(Map<String, dynamic> map) {
    return MedicineModel(
      id: map['id'] as String,
      profileId: map['profile_id'] as String,
      name: map['name'] as String,
      type: map['type'] as String,
      dosageValue: map['dosage_value'] as double?,
      dosageUnit: map['dosage_unit'] as String?,
      quantityValue: map['quantity_value'] as double?,
      quantityUnit: map['quantity_unit'] as String?,
      frequency: map['frequency'] as String,
      startDate: map['start_date'] as int,
      endDate: map['end_date'] as int?,
      notes: map['notes'] as String?,
      active: (map['active'] as int) == 1,
      updatedAt: map['updated_at'] as int,
      isDirty: map['is_dirty'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'profile_id': profileId,
      'name': name,
      'type': type,
      'dosage_value': dosageValue,
      'dosage_unit': dosageUnit,
      'quantity_value': quantityValue,
      'quantity_unit': quantityUnit,
      'frequency': frequency,
      'start_date': startDate,
      'end_date': endDate,
      'notes': notes,
      'active': active ? 1 : 0,
      'updated_at': updatedAt,
      'is_dirty': isDirty,
    };
  }

  Medicine toEntity() {
    return Medicine(
      id: id,
      profileId: profileId,
      name: name,
      type: type,
      dosageValue: dosageValue,
      dosageUnit: dosageUnit,
      quantityValue: quantityValue,
      quantityUnit: quantityUnit,
      frequency: frequency,
      startDate: startDate,
      endDate: endDate,
      notes: notes,
      active: active,
    );
  }
}
