import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../../onboarding/presentation/providers/onboarding_provider.dart';
import '../../../onboarding/data/models/profile_model.dart';
import '../../../../core/utils/app_code_generator.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/crashlytics_service.dart';
import '../../../../core/services/performance_service.dart';
import '../../../onboarding/domain/entities/profile.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../../medications/presentation/providers/medications_provider.dart';
import '../../../history/presentation/providers/history_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/db_helper.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import 'sync_provider.dart';

class AuthState {
  final User? firebaseUser;
  final GoogleSignInAccount? googleAccount;
  final Map<String, String>? authHeaders;
  final String? errorMessage;
  final bool isLoading;

  const AuthState({
    this.firebaseUser,
    this.googleAccount,
    this.authHeaders,
    this.errorMessage,
    this.isLoading = false,
  });

  bool get isAuthenticated =>
      firebaseUser != null || (kIsWeb && googleAccount != null);

  AuthState copyWith({
    User? firebaseUser,
    GoogleSignInAccount? googleAccount,
    Map<String, String>? authHeaders,
    String? errorMessage,
    bool? isLoading,
    bool clearError = false,
  }) {
    return AuthState(
      firebaseUser: firebaseUser ?? this.firebaseUser,
      googleAccount: googleAccount ?? this.googleAccount,
      authHeaders: authHeaders ?? this.authHeaders,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(ref);
  ref.listen<AsyncValue<Profile?>>(ownerProfileProvider, (previous, next) {
    final user = FirebaseAuth.instance.currentUser;
    final prevProfile = previous?.valueOrNull;
    final nextProfile = next.valueOrNull;
    if (user != null && nextProfile != null) {
      if (prevProfile?.appCode != nextProfile.appCode || prevProfile?.profileName != nextProfile.profileName) {
        notifier.forceLinkAppCode(user, isNewLogin: false);
      }
    }
  });
  return notifier;
});

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref? ref;
  bool _isLinking = false;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb
        ? '522154987711-7bqpe7i0c41nb28i43f02siq0aom6k92.apps.googleusercontent.com'
        : null,
    scopes: ['email'],
  );

  AuthNotifier(this.ref) : super(const AuthState()) {
    try {
      // Listen to Firebase auth changes if not on Web
      if (!kIsWeb) {
        FirebaseAuth.instance.authStateChanges().listen((User? user) async {
          if (user == null) {
            state = const AuthState();
          } else {
            try {
              final googleAccount = _googleSignIn.currentUser;
              final headers = await googleAccount?.authHeaders;
              state = AuthState(
                firebaseUser: user,
                googleAccount: googleAccount,
                authHeaders: headers,
              );
            } catch (e) {
              state = AuthState(firebaseUser: user);
            }
            // Set User Identifier in Crashlytics and Analytics safely (anonymized UUID)
            if (ref != null) {
              ref!.read(crashlyticsServiceProvider).setUserIdentifier(user.uid);
              ref!.read(analyticsServiceProvider).setUserId(user.uid);
            }
            // Auto link App Code if missing
            _linkAppCodeIfMissing(user, isNewLogin: false);
          }
        });
      }
    } catch (e) {
      debugPrint(
        'Firebase Auth initialization skipped in AuthNotifier constructor: $e',
      );
    }
  }

  void forceLinkAppCode(User user, {bool isNewLogin = false}) {
    _isLinking = false;
    _linkAppCodeIfMissing(user, isNewLogin: isNewLogin);
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final perf = ref?.read(performanceServiceProvider);
    await perf?.startTrace('google_signin_trace');
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Sign-in cancelled.',
        );
        await perf?.stopTrace(
          'google_signin_trace',
          attributes: {'status': 'cancelled'},
        );
        if (ref != null) {
          ref!.read(analyticsServiceProvider).logAuthEvent('login_cancelled');
        }
        return;
      }

      final Map<String, String> headers = await googleUser.authHeaders;

      if (kIsWeb) {
        // Web mock auth flow
        state = AuthState(
          googleAccount: googleUser,
          authHeaders: headers,
          isLoading: false,
        );
        await perf?.stopTrace(
          'google_signin_trace',
          attributes: {'status': 'success'},
        );
        if (ref != null) {
          ref!.read(analyticsServiceProvider).logAuthEvent('login_success');
        }
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final user = userCredential.user;

      state = AuthState(
        firebaseUser: user,
        googleAccount: googleUser,
        authHeaders: headers,
        isLoading: true,
      );

      if (ref != null && user != null) {
        ref!.read(crashlyticsServiceProvider).setUserIdentifier(user.uid);
        ref!.read(analyticsServiceProvider).setUserId(user.uid);
        ref!.read(analyticsServiceProvider).logAuthEvent('login_success');

        // Link App Code and refresh providers before turning off loading state
        await _linkAppCodeIfMissing(user, isNewLogin: true);
      }

      state = state.copyWith(isLoading: false);
      await perf?.stopTrace(
        'google_signin_trace',
        attributes: {'status': 'success'},
      );
    } catch (e, stack) {
      await perf?.stopTrace(
        'google_signin_trace',
        attributes: {'status': 'failure'},
      );
      if (ref != null) {
        ref!
            .read(analyticsServiceProvider)
            .logAuthEvent('login_failed', error: e.toString());
        ref!
            .read(crashlyticsServiceProvider)
            .recordError(e, stack, reason: 'Google sign in failed');
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Authentication failed: $e',
      );
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (ref != null && currentUser != null) {
        final profile = await ref!.read(ownerProfileProvider.future);
        if (profile != null && profile.profileType == 'Caretaker') {
          DbHelper.log(
            'AuthNotifier: Caretaker sign-out detected. Initiating parent connections and data cleanup...',
          );
          await _cleanupCaretakerConnectionsAndData(
            caretakerUid: currentUser.uid,
            caretakerAppCode: profile.appCode,
          );
        }
      }

      await _googleSignIn.signOut();
      if (!kIsWeb) {
        await FirebaseAuth.instance.signOut();
      }
      if (ref != null) {
        ref!.read(analyticsServiceProvider).logAuthEvent('logout_success');
        ref!.read(analyticsServiceProvider).setUserId(null);

        // Clear local profile's app code in SQLite on sign-out
        final profile = await ref!.read(ownerProfileProvider.future);
        if (profile != null) {
          final updatedProfile = profile.copyWith(appCode: null);
          final localDataSource = ref!.read(onboardingLocalDataSourceProvider);
          final now = DateTime.now().toUtc().millisecondsSinceEpoch;
          final model = ProfileModel.fromProfile(
            updatedProfile,
            isOwner: true,
            isDirty: 1,
            updatedAt: now,
          );
          await localDataSource.saveProfile(model);
          ref!.invalidate(ownerProfileProvider);
          ref!.invalidate(profilesListProvider);
        }
      }
      state = const AuthState();
    } catch (e, stack) {
      if (ref != null) {
        ref!
            .read(analyticsServiceProvider)
            .logAuthEvent('logout_failed', error: e.toString());
        ref!
            .read(crashlyticsServiceProvider)
            .recordError(e, stack, reason: 'Sign out failed');
      }
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Sign-out failed: $e',
      );
    }
  }

  Future<void> _cleanupCaretakerConnectionsAndData({
    required String caretakerUid,
    required String? caretakerAppCode,
  }) async {
    DbHelper.log(
      'Caretaker Cleanup: Starting cleanup of parent connections and parent profile data for Caretaker UID $caretakerUid (AppCode: $caretakerAppCode)...',
    );
    final database = FirebaseDatabase.instance;

    // 1. Delete connections & sync payloads in Firebase RTDB
    try {
      final parentsSnapshot = await database
          .ref('users/$caretakerUid/connected_parents')
          .get()
          .timeout(const Duration(seconds: 5));

      if (parentsSnapshot.exists && parentsSnapshot.value is Map) {
        final parentsMap = Map<String, dynamic>.from(
          parentsSnapshot.value as Map,
        );
        for (final entry in parentsMap.entries) {
          final parentAppCode = entry.key;
          DbHelper.log(
            'Caretaker Cleanup: Processing parent connection removal for parentAppCode: $parentAppCode',
          );

          // Fetch parentUid from /profiles/$parentAppCode
          String? parentUid;
          try {
            final parentSnap = await database
                .ref('profiles/$parentAppCode')
                .get()
                .timeout(const Duration(seconds: 4));
            if (parentSnap.exists && parentSnap.value is Map) {
              final pData = Map<String, dynamic>.from(parentSnap.value as Map);
              parentUid = pData['uid'] as String?;
            }
          } catch (e) {
            DbHelper.log(
              'Caretaker Cleanup: Failed to fetch parentUid for $parentAppCode: $e',
            );
          }

          // Remove connection entry from parent's profile node in RTDB
          if (caretakerAppCode != null && caretakerAppCode.isNotEmpty) {
            try {
              await database
                  .ref('profiles/$parentAppCode/connections/$caretakerAppCode')
                  .remove();
              DbHelper.log(
                'Caretaker Cleanup: Successfully removed connection /profiles/$parentAppCode/connections/$caretakerAppCode',
              );
            } catch (e) {
              DbHelper.log(
                'Caretaker Cleanup: Failure removing connection /profiles/$parentAppCode/connections/$caretakerAppCode: $e',
              );
            }
          }

          // Remove pending RTDB sync payloads
          if (parentUid != null && parentUid.isNotEmpty) {
            final payloadPaths = [
              'sync_payloads/$caretakerUid/$parentUid',
              'sync_payloads/$caretakerUid/${parentUid}_pull',
              'sync_payloads/$caretakerUid/${parentUid}_ack',
              'sync_payloads/$parentUid/$caretakerUid',
              'sync_payloads/$parentUid/${caretakerUid}_pull',
              'sync_payloads/$parentUid/${caretakerUid}_ack',
            ];
            for (final path in payloadPaths) {
              try {
                await database.ref(path).remove();
                DbHelper.log('Caretaker Cleanup: Removed sync payload node $path');
              } catch (e) {
                DbHelper.log(
                  'Caretaker Cleanup: Failure removing RTDB node $path: $e',
                );
              }
            }
          }
        }
      }

      // Remove connected_parents list under users node
      await database
          .ref('users/$caretakerUid/connected_parents')
          .remove();
      DbHelper.log(
        'Caretaker Cleanup: Successfully removed /users/$caretakerUid/connected_parents',
      );
    } catch (e, stack) {
      DbHelper.log(
        'Caretaker Cleanup: Exception occurred during RTDB cleanup: $e\n$stack',
      );
    }

    // 2. Delete parent profile data from local SQLite database (is_owner = 0)
    try {
      final db = await DbHelper.instance.database;
      await db.transaction((txn) async {
        final nonOwnerProfiles = await txn.query(
          AppConstants.tableProfiles,
          where: 'is_owner = 0',
        );
        DbHelper.log(
          'Caretaker Cleanup: Clearing ${nonOwnerProfiles.length} non-owner parent profile(s) from SQLite...',
        );
        for (final p in nonOwnerProfiles) {
          final pId = p['id'] as String;
          await txn.delete(
            AppConstants.tableMedicines,
            where: 'profile_id = ?',
            whereArgs: [pId],
          );
          await txn.delete(
            AppConstants.tableSchedules,
            where: 'profile_id = ?',
            whereArgs: [pId],
          );
          await txn.delete(
            AppConstants.tableMedicineLog,
            where: 'profile_id = ?',
            whereArgs: [pId],
          );
          await txn.delete(
            AppConstants.tableSettings,
            where: 'profile_id = ?',
            whereArgs: [pId],
          );
        }
        final deletedCount = await txn.delete(
          AppConstants.tableProfiles,
          where: 'is_owner = 0',
        );
        DbHelper.log(
          'Caretaker Cleanup: Deleted $deletedCount parent profile row(s) from SQLite profiles table.',
        );
      });
    } catch (e, stack) {
      DbHelper.log(
        'Caretaker Cleanup: Failure clearing parent profiles from SQLite: $e\n$stack',
      );
    }

    // 3. Invalidate Riverpod providers to refresh UI
    if (ref != null) {
      ref!.invalidate(profilesListProvider);
      ref!.invalidate(homeDosesProvider);
      ref!.invalidate(medicinesListProvider);
      ref!.invalidate(adherenceReportsProvider);
      ref!.invalidate(settingsStateProvider);
    }
    DbHelper.log('Caretaker Cleanup: Caretaker connections & parent profile data cleanup completed.');
  }

  Future<void> _linkAppCodeIfMissing(User user, {bool isNewLogin = false}) async {
    if (_isLinking) return;
    if (FirebaseAuth.instance.currentUser == null) {
      debugPrint('RTDB Link: User is not authenticated with Firebase Auth yet. Skipping RTDB link.');
      return;
    }
    _isLinking = true;
    try {
      if (ref != null) {
        final profile = await ref!.read(ownerProfileProvider.future);
        if (profile != null) {
          // Set user monitoring properties safely (anonymized)
          ref!.read(crashlyticsServiceProvider).setCustomKey('profile_type', profile.profileType);
          ref!.read(analyticsServiceProvider).setUserProperty(name: 'profile_type', value: profile.profileType);

          String? appCode = profile.appCode;
          String profileName = profile.profileName;
          final database = FirebaseDatabase.instance;

          // 1. Search via firebaseUserId (user.uid) under /users/${user.uid}
          String? restoredCode;
          try {
            final userSnap = await database.ref('users/${user.uid}').get().timeout(const Duration(seconds: 3));
            if (userSnap.exists && userSnap.value is Map) {
              final userData = Map<String, dynamic>.from(userSnap.value as Map);
              final code = userData['app_code'] as String?;
              if (code != null && code.isNotEmpty) {
                restoredCode = code;
                debugPrint('RTDB Link: Found existing appCode from /users/${user.uid}: $restoredCode');
              }
            }
          } catch (e) {
            debugPrint('RTDB Link: /users/${user.uid} lookup error: $e');
          }

          // Fallback check: Search via appCode reverse lookup under /profiles matching uid == user.uid
          if (restoredCode == null || restoredCode.isEmpty) {
            try {
              final profilesSnap = await database.ref('profiles').get().timeout(const Duration(seconds: 4));
              if (profilesSnap.exists && profilesSnap.value is Map) {
                final profilesMap = Map<String, dynamic>.from(profilesSnap.value as Map);
                for (final entry in profilesMap.entries) {
                  if (entry.value is Map) {
                    final pData = Map<String, dynamic>.from(entry.value as Map);
                    if (pData['uid'] == user.uid) {
                      restoredCode = entry.key; // Key under /profiles is appCode
                      debugPrint('RTDB Link: Found existing profile /profiles/$restoredCode for UID ${user.uid}');
                      break;
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('RTDB Link: /profiles search error: $e');
            }
          }

          if (restoredCode != null && restoredCode.isNotEmpty) {
            appCode = restoredCode;
            debugPrint('RTDB Link: Restored existing appCode from RTDB: $appCode for UID ${user.uid}');
          } else if (appCode == null || appCode == 'None' || appCode.isEmpty) {
            // 2. Generate new unique app code ONLY if no profile exists for user.uid in RTDB
            appCode = AppCodeGenerator.generate();
            debugPrint('RTDB Link: Brand new user. Generated new appCode for UID ${user.uid}: $appCode');
          }

          // Search via appcode: Update /profiles/$appCode
          await database.ref('profiles/$appCode').update({
            'uid': user.uid,
            'profile_name': profileName,
            'profile_type': profile.profileType,
            'presence': 'online',
          });

          // Search via firebaseUserId: Update /users/${user.uid}
          await database.ref('users/${user.uid}').update({
            'app_code': appCode,
            'name': profileName,
            'profile_type': profile.profileType,
            'updated_at': ServerValue.timestamp,
          });

          // Update local SQLite DB
          final updatedProfile = profile.copyWith(appCode: appCode, profileName: profileName);
          final localDataSource = ref!.read(onboardingLocalDataSourceProvider);
          final now = DateTime.now().toUtc().millisecondsSinceEpoch;
          final model = ProfileModel.fromProfile(
            updatedProfile,
            isOwner: true,
            isDirty: 1,
            updatedAt: now,
          );
          await localDataSource.saveProfile(model);

          // Update active profile if it is the owner
          final active = ref!.read(activeProfileProvider);
          if (active == null || active.isOwner) {
            ref!.read(activeProfileProvider.notifier).setActiveProfile(updatedProfile);
          }

          ref!.invalidate(ownerProfileProvider);
          ref!.invalidate(profilesListProvider);
          ref!.invalidate(homeDosesProvider);
          ref!.invalidate(medicinesListProvider);
          ref!.invalidate(adherenceReportsProvider);
          ref!.invalidate(settingsStateProvider);
          debugPrint(
            'Successfully auto-linked app_code: $appCode',
          );

          // 5. On Caretaker fresh login ONLY (isNewLogin == true): Clean up existing connections & payload nodes.
          // Routine app startups (isNewLogin == false) preserve active connections.
          if (profile.profileType == 'Caretaker' && isNewLogin) {
            debugPrint(
              'RTDB Link: Caretaker login detected. Cleaning up existing connections & payloads...',
            );
            await _cleanupCaretakerConnectionsAndData(
              caretakerUid: user.uid,
              caretakerAppCode: appCode,
            );
          }
        } else {
          debugPrint(
            'RTDB Link: Owner profile is null in SQLite, skipping linking.',
          );
        }
      }
    } catch (e, stack) {
      debugPrint(
        'Failed to link google account presence/app_code on startup: $e\n$stack',
      );
    } finally {
      _isLinking = false;
      debugPrint('RTDB Link: Finished linking process.');
    }
  }
}
