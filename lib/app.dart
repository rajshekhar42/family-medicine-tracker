import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'main.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_constants.dart';

import 'features/medications/presentation/screens/add_medication_screen.dart';
import 'features/medications/presentation/screens/medicines_list_screen.dart';
import 'features/medications/domain/entities/medicine.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';
import 'features/onboarding/presentation/providers/onboarding_provider.dart';
import 'features/onboarding/domain/entities/profile.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/history/presentation/screens/history_screen.dart';
import 'features/sync/presentation/providers/rtdb_sync_listener.dart';
import 'features/profiles/presentation/providers/active_profile_provider.dart';
import 'features/sync/presentation/providers/sync_provider.dart';
import 'features/sync/presentation/providers/auth_provider.dart';
import 'features/settings/presentation/services/reminder_scheduler.dart';

// GoRouter routing configuration provider
final routerProvider = Provider<GoRouter>((ref) {
  final isFirebaseInitialized = Firebase.apps.isNotEmpty;
  return GoRouter(
    initialLocation: AppConstants.routeHome,
    observers: [
      if (isFirebaseInitialized)
        FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    redirect: (context, state) async {
      // Fetch owner profile status from the provider
      final profileAsyncValue = ref.read(ownerProfileProvider);
      
      // If still loading, wait for it to complete
      Profile? profile;
      if (profileAsyncValue is AsyncData<Profile?>) {
        profile = profileAsyncValue.value;
      } else {
        try {
          profile = await ref.read(ownerProfileProvider.future);
        } catch (_) {
          profile = null;
        }
      }

      final onOnboarding = state.matchedLocation == AppConstants.routeOnboarding;

      if (profile == null) {
        // Redirect to onboarding if profile is not created yet
        return onOnboarding ? null : AppConstants.routeOnboarding;
      }

      // If profile is already created and user is on onboarding screen, redirect to home
      if (onOnboarding) {
        return AppConstants.routeHome;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppConstants.routeHome,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: AppConstants.routeOnboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppConstants.routeAddMedication,
        builder: (context, state) => const AddMedicationScreen(),
      ),
      GoRoute(
        path: AppConstants.routeEditMedication,
        builder: (context, state) {
          final medicine = state.extra as Medicine?;
          return AddMedicationScreen(editingMedicine: medicine);
        },
      ),
      GoRoute(
        path: AppConstants.routeMedicinesList,
        builder: (context, state) => const MedicinesListScreen(),
      ),
      GoRoute(
        path: AppConstants.routeHistory,
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: AppConstants.routeSettings,
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Run startup sync check after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _triggerStartupSync();
      // Stop app startup trace
      try {
        if (appStartupTrace != null) {
          await appStartupTrace!.stop();
          appStartupTrace = null;
        }
      } catch (e) {
        debugPrint('Failed to stop app startup trace: $e');
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _triggerStartupSync();
    }
  }

  Future<void> _triggerStartupSync() async {
    final authState = ref.read(authProvider);
    if (!authState.isAuthenticated || authState.firebaseUser == null) {
      debugPrint('Skipping startup sync: User not authenticated.');
      return;
    }

    final activeProfile = ref.read(activeProfileProvider);
    if (activeProfile == null) return;

    final syncState = ref.read(syncStateProvider);

    if (!syncState.isSyncing) {
      debugPrint('Auto-sync triggered on startup/resume.');
      await ref.read(syncStateProvider.notifier).sync();
    }
    // Reschedule all active reminders after startup sync or directly on resume
    await ref.read(reminderSchedulerProvider).rescheduleAll();
  }

  @override
  Widget build(BuildContext context) {
    // Start listening to direct RTDB sync events
    ref.watch(rtdbSyncListenerProvider);

    // Listen for auth state restoration on cold boot to trigger auto-sync
    ref.listen<AuthState>(authProvider, (previous, next) {
      if ((previous == null || !previous.isAuthenticated) && next.isAuthenticated) {
        debugPrint('App: Auth state restored -> triggering startup sync.');
        _triggerStartupSync();
      }
    });

    // Listen for active profile restoration on cold boot to trigger auto-sync
    ref.listen<Profile?>(activeProfileProvider, (previous, next) {
      if (previous == null && next != null) {
        debugPrint('App: Active profile loaded -> triggering startup sync.');
        _triggerStartupSync();
      }
    });

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'FamilyMediCare',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class PlaceholderScreen extends StatelessWidget {
  final String title;
  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
      body: Center(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}
