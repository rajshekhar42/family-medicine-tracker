class MedTypeConfig {
  final List<MedTypeUnit> types;

  const MedTypeConfig({required this.types});

  MedTypeUnit? getTypeConfig(String id) {
    try {
      return types.firstWhere((t) => t.id.toLowerCase() == id.toLowerCase());
    } catch (_) {
      return null;
    }
  }
}

class MedTypeUnit {
  final String id;
  final String displayName;
  final bool dosageEnabled;
  final List<String> dosageUnits;
  final bool quantityEnabled;
  final List<String> quantityUnits;

  const MedTypeUnit({
    required this.id,
    required this.displayName,
    required this.dosageEnabled,
    required this.dosageUnits,
    required this.quantityEnabled,
    required this.quantityUnits,
  });
}
