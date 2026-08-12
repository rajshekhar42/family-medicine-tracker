import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'dart:ui';
import 'firebase_options.dart';
import 'app.dart';
import 'core/utils/db_helper.dart';
import 'features/settings/presentation/services/notification_service.dart';

Trace? appStartupTrace;

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase Core safely
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');

    // Start App Startup Trace
    try {
      appStartupTrace = FirebasePerformance.instance.newTrace('app_startup_trace');
      await appStartupTrace?.start();
    } catch (e) {
      debugPrint('Failed to start app_startup_trace: $e');
    }

    // Fetch and apply dynamic telemetry configuration from Remote Config
    bool enableTelemetry = true;
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      
      await remoteConfig.setDefaults({
        'enable_telemetry': true,
      });

      await remoteConfig.fetchAndActivate();
      enableTelemetry = remoteConfig.getBool('enable_telemetry');
      debugPrint('Remote Config telemetry flag: $enableTelemetry');
    } catch (e) {
      debugPrint('Failed to configure telemetry from Remote Config: $e');
    }

    // Configure Analytics, Performance, and Crashlytics based on configuration
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enableTelemetry);
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(enableTelemetry);
      
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(enableTelemetry && !kDebugMode);
      
      // Pass all uncaught Flutter errors to Crashlytics
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Pass all uncaught asynchronous errors to Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('Failed to configure Firebase telemetry/Crashlytics collection: $e');
    }
  } catch (e) {
    debugPrint('Firebase initialization warning: $e. Using local/mock fallback.');
  }

  // Initialize notifications service
  await NotificationService.instance.init();

  // Initialize SQLite local database source of truth if not on Web
  if (!kIsWeb) {
    try {
      final db = await DbHelper.instance.database;
      debugPrint('Database initialized successfully: ${db.path}');
    } catch (e) {
      debugPrint('Failed to initialize local database: $e');
    }
  }

  // Run the app wrapped in ProviderScope for state management
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
