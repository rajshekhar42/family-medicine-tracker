import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/utils/db_helper.dart';
import '../../data/datasources/onboarding_local_datasource.dart';
import '../../data/repositories/onboarding_repository_impl.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/onboarding_repository.dart';
import '../../domain/usecases/create_profile.dart';
import '../../domain/usecases/get_owner_profile.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/crashlytics_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../sync/presentation/providers/auth_provider.dart';
import '../../../sync/presentation/providers/sync_provider.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../../../home/presentation/providers/home_provider.dart';
import '../../../medications/presentation/providers/medications_provider.dart';

// 1. Dependency Injection Providers
final onboardingLocalDataSourceProvider = Provider<OnboardingLocalDataSource>((ref) {
  if (kIsWeb) {
    return OnboardingLocalDataSourceInMemory();
  }
  return OnboardingLocalDataSourceImpl(DbHelper.instance);
});

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepositoryImpl(
    localDataSource: ref.watch(onboardingLocalDataSourceProvider),
    uuid: const Uuid(),
  );
});

final getOwnerProfileUseCaseProvider = Provider<GetOwnerProfile>((ref) {
  return GetOwnerProfile(ref.watch(onboardingRepositoryProvider));
});

final createProfileUseCaseProvider = Provider<CreateProfile>((ref) {
  return CreateProfile(ref.watch(onboardingRepositoryProvider));
});

// 2. State Notifiers
final ownerProfileProvider = AsyncNotifierProvider<OwnerProfileNotifier, Profile?>(() {
  return OwnerProfileNotifier();
});

class OwnerProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final getOwnerProfile = ref.watch(getOwnerProfileUseCaseProvider);
    final result = await getOwnerProfile();
    return result.fold(
      (failure) => throw Exception(failure.message),
      (profile) => profile,
    );
  }

  Future<void> createOwnerProfile({
    required String name,
    required String timeZone,
    String profileType = 'Parent',
  }) async {
    state = const AsyncValue.loading();
    final createProfile = ref.watch(createProfileUseCaseProvider);
    final result = await createProfile(
      name: name,
      timeZone: timeZone,
      profileType: profileType,
    );
    
    result.fold(
      (failure) {
        ref.read(crashlyticsServiceProvider).recordError(
          failure,
          StackTrace.current,
          reason: 'Failed to create owner profile',
        );
        state = AsyncValue.error(failure, StackTrace.current);
      },
      (profile) {
        ref.read(analyticsServiceProvider).logOnboardingCompleted(profile.id, profile.timeZone);
        state = AsyncValue.data(profile);
        ref.invalidate(profilesListProvider);
        
        // Auto-link App Code on onboarding completion if Google Sign-In is active
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            ref.read(authProvider.notifier).forceLinkAppCode(user);
          }
        } catch (e) {
          debugPrint('Failed to link App Code on onboarding completion: $e');
        }
      },
    );
  }
}

final profilesListProvider = AsyncNotifierProvider<ProfilesListNotifier, List<Profile>>(() {
  return ProfilesListNotifier();
});

class ProfilesListNotifier extends AsyncNotifier<List<Profile>> {
  @override
  Future<List<Profile>> build() async {
    final repository = ref.watch(onboardingRepositoryProvider);
    final result = await repository.getAllProfiles();
    return result.fold(
      (failure) => throw Exception(failure.message),
      (profiles) => profiles,
    );
  }

  Future<void> addFamilyMember(String name, String timeZone) async {
    state = const AsyncValue.loading();
    final repository = ref.watch(onboardingRepositoryProvider);
    final result = await repository.createFamilyProfile(name: name, timeZone: timeZone);
    
    result.fold(
      (failure) {
        ref.read(crashlyticsServiceProvider).recordError(
          failure,
          StackTrace.current,
          reason: 'Failed to add family member',
        );
        state = AsyncValue.error(failure, StackTrace.current);
      },
      (profile) async {
        ref.read(analyticsServiceProvider).logFamilyMemberAdded(profile.id, profile.timeZone, false);
        ref.invalidateSelf();
      },
    );
  }

  Future<void> addSyncedFamilyMember({
    required String id,
    required String name,
    required String timeZone,
    required String appCode,
  }) async {
    state = const AsyncValue.loading();
    final repository = ref.watch(onboardingRepositoryProvider);
    final result = await repository.createSyncedFamilyProfile(
      id: id,
      name: name,
      timeZone: timeZone,
      appCode: appCode,
    );
    
    result.fold(
      (failure) {
        ref.read(crashlyticsServiceProvider).recordError(
          failure,
          StackTrace.current,
          reason: 'Failed to add synced family member',
        );
        state = AsyncValue.error(failure, StackTrace.current);
      },
      (profile) async {
        ref.read(analyticsServiceProvider).logFamilyMemberAdded(profile.id, profile.timeZone, true);
        ref.invalidateSelf();
      },
    );
  }

  Future<void> updateProfileName({
    required Profile profile,
    required String newName,
  }) async {
    state = const AsyncValue.loading();
    final repository = ref.watch(onboardingRepositoryProvider);
    final result = await repository.updateProfileName(
      profileId: profile.id,
      newName: newName,
    );

    result.fold(
      (failure) {
        ref.read(crashlyticsServiceProvider).recordError(
          failure,
          StackTrace.current,
          reason: 'Failed to update profile name',
        );
        state = AsyncValue.error(failure, StackTrace.current);
      },
      (_) {
        final activeProfile = ref.read(activeProfileProvider);
        if (activeProfile != null && activeProfile.id == profile.id) {
          final updated = activeProfile.copyWith(profileName: newName);
          ref.read(activeProfileProvider.notifier).setActiveProfile(updated);
        }
        if (profile.isOwner) {
          ref.invalidate(ownerProfileProvider);
        }
        ref.invalidate(caretakerConnectionsProvider);
        ref.invalidateSelf();
      },
    );
  }

  Future<void> deleteParentProfile(Profile profile) async {
    if (profile.isOwner) return;

    state = const AsyncValue.loading();
    final repository = ref.watch(onboardingRepositoryProvider);
    final result = await repository.deleteParentProfile(profileId: profile.id);

    result.fold(
      (failure) {
        ref.read(crashlyticsServiceProvider).recordError(
          failure,
          StackTrace.current,
          reason: 'Failed to delete parent profile',
        );
        state = AsyncValue.error(failure, StackTrace.current);
      },
      (_) {
        final activeProfile = ref.read(activeProfileProvider);
        final ownerProfileState = ref.read(ownerProfileProvider);
        final ownerProfile = ownerProfileState.valueOrNull;

        // If active profile was the deleted parent profile, switch back to owner profile
        if (activeProfile != null && activeProfile.id == profile.id && ownerProfile != null) {
          ref.read(activeProfileProvider.notifier).setActiveProfile(ownerProfile);
        }

        ref.invalidate(caretakerConnectionsProvider);
        ref.invalidate(homeDosesProvider);
        ref.invalidate(medicinesListProvider);
        ref.invalidateSelf();
      },
    );
  }
}
