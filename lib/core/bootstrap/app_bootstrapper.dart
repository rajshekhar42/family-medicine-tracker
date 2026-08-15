import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'dart:ui';
import '../../firebase_options.dart';
import '../utils/db_helper.dart';
import '../../features/settings/presentation/services/notification_service.dart';

/// Holds the in-progress Performance trace started during bootstrap so that
/// [AppBootstrapper.stopStartupTrace] can be called from the widget tree once
/// the first frame is rendered.
Trace? appStartupTrace;

/// Encapsulates all application startup initialization logic.
///
/// Responsibilities:
/// - Firebase Core initialization
/// - Firebase Performance startup trace
/// - Remote Config telemetry flag fetch
/// - Analytics, Crashlytics, and Performance collection configuration
/// - Flutter error handler binding for Crashlytics
/// - Local notification service initialization
/// - SQLite database pre-warm
///
/// Extracted from [main()] to satisfy SRP — [main.dart] is reduced to
/// wiring the DI container and calling [runApp].
class AppBootstrapper {
  AppBootstrapper._();

  /// Runs all startup initialization tasks in order.
  /// Call this before [runApp].
  static Future<void> initialize() async {
    await _initFirebase();
    await _initNotifications();
    await _initDatabase();
  }

  /// Stops the app startup Performance trace.
  /// Call this from [WidgetsBinding.addPostFrameCallback] after the first frame.
  static Future<void> stopStartupTrace() async {
    try {
      if (appStartupTrace != null) {
        await appStartupTrace!.stop();
        appStartupTrace = null;
      }
    } catch (e) {
      debugPrint('Failed to stop app_startup_trace: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static Future<void> _initFirebase() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('Firebase initialized successfully');

      await _startPerformanceTrace();
      final enableTelemetry = await _fetchTelemetryFlag();
      await _configureTelemetry(enableTelemetry);
    } catch (e) {
      debugPrint('Firebase initialization warning: $e. Using local/mock fallback.');
    }
  }

  static Future<void> _startPerformanceTrace() async {
    try {
      appStartupTrace = FirebasePerformance.instance.newTrace('app_startup_trace');
      await appStartupTrace?.start();
    } catch (e) {
      debugPrint('Failed to start app_startup_trace: $e');
    }
  }

  static Future<bool> _fetchTelemetryFlag() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 5),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await remoteConfig.setDefaults({'enable_telemetry': true});
      await remoteConfig.fetchAndActivate();
      final flag = remoteConfig.getBool('enable_telemetry');
      debugPrint('Remote Config telemetry flag: $flag');
      return flag;
    } catch (e) {
      debugPrint('Failed to configure telemetry from Remote Config: $e');
      return true;
    }
  }

  static Future<void> _configureTelemetry(bool enableTelemetry) async {
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(enableTelemetry);
      await FirebasePerformance.instance.setPerformanceCollectionEnabled(enableTelemetry);
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
        enableTelemetry && !kDebugMode,
      );

      // Bind Flutter error handler to Crashlytics
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Bind platform/async error handler to Crashlytics
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } catch (e) {
      debugPrint('Failed to configure Firebase telemetry/Crashlytics collection: $e');
    }
  }

  static Future<void> _initNotifications() async {
    await NotificationService.instance.init();
  }

  static Future<void> _initDatabase() async {
    if (!kIsWeb) {
      try {
        final db = await DbHelper.instance.database;
        debugPrint('Database initialized successfully: ${db.path}');
      } catch (e) {
        debugPrint('Failed to initialize local database: $e');
      }
    }
  }
}
