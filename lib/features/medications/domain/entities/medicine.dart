class Medicine {
  final String id;
  final String profileId;
  final String name;
  final String type; // tablet, capsule, syrup, powder, cream, injection
  final double? dosageValue;
  final String? dosageUnit;
  final double? quantityValue;
  final String? quantityUnit;
  final String frequency; // E.g., 'Once a Day', '2 times, Daily', etc.
  final int startDate; // UTC milliseconds epoch
  final int? endDate; // UTC milliseconds epoch, null means 'Continuous'
  final String? notes;
  final bool active;

  const Medicine({
    required this.id,
    required this.profileId,
    required this.name,
    required this.type,
    this.dosageValue,
    this.dosageUnit,
    this.quantityValue,
    this.quantityUnit,
    required this.frequency,
    required this.startDate,
    this.endDate,
    this.notes,
    this.active = true,
  });

  Medicine copyWith({
    String? id,
    String? profileId,
    String? name,
    String? type,
    double? dosageValue,
    String? dosageUnit,
    double? quantityValue,
    String? quantityUnit,
    String? frequency,
    int? startDate,
    int? endDate,
    String? notes,
    bool? active,
  }) {
    return Medicine(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      name: name ?? this.name,
      type: type ?? this.type,
      dosageValue: dosageValue ?? this.dosageValue,
      dosageUnit: dosageUnit ?? this.dosageUnit,
      quantityValue: quantityValue ?? this.quantityValue,
      quantityUnit: quantityUnit ?? this.quantityUnit,
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      notes: notes ?? this.notes,
      active: active ?? this.active,
    );
  }
}
