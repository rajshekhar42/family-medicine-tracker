class AppConstants {
  AppConstants._();

  // Database
  static const String dbName = 'medicine_tracker.db';
  static const int dbVersion = 4;

  // Tables
  static const String tableProfiles = 'profiles';
  static const String tableMedicines = 'medicines';
  static const String tableSchedules = 'schedules';
  static const String tableMedicineLog = 'medicine_log';
  static const String tableSettings = 'settings';
  static const String tableSyncQueue = 'sync_queue';
  static const String tableChunkBuffer = 'chunk_buffer';

  // Remote Config Keys
  static const String remoteConfigMedTypeUnits = 'medTypeUnits';

  // Google API Constants
  static const String driveFolderName = 'MedicineTrackerApp';

  // Timezones
  static const String defaultTimezone = 'UTC';

  // Cloud Sync
  static const int syncDebounceMinutes = 0;

  // Route Paths
  static const String routeOnboarding = '/onboarding';
  static const String routeHome = '/';
  static const String routeAddMedication = '/add-medication';
  static const String routeEditMedication = '/edit-medication';
  static const String routeMedicinesList = '/medicines-list';
  static const String routeHistory = '/history';
  static const String routeSettings = '/settings';
  static const String routeFamilyProfile = '/family-profile';

  // Frequencies Options
  static const List<String> frequencyOptions = [
    'Once a Day',
    '2 times, Daily',
    '3 times, Daily',
    'X times, Daily',
    'Once a Week',
    'X times a Week',
    'Once a Month',
    'X times a Month',
  ];
}
