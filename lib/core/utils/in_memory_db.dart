class InMemoryDb {
  static Map<String, dynamic>? ownerProfile;
  static Map<String, dynamic>? ownerSettings;
  static final List<Map<String, dynamic>> profiles = [];
  static final List<Map<String, dynamic>> medicines = [];
  static final List<Map<String, dynamic>> schedules = [];
  static final List<Map<String, dynamic>> medicineLogs = [];

  static void clearAll() {
    ownerProfile = null;
    ownerSettings = null;
    profiles.clear();
    medicines.clear();
    schedules.clear();
    medicineLogs.clear();
  }
}
