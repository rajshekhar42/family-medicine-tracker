import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../onboarding/presentation/providers/onboarding_provider.dart';
import '../../../onboarding/domain/entities/profile.dart';

final activeProfileProvider = StateNotifierProvider<ActiveProfileNotifier, Profile?>((ref) {
  final ownerProfileState = ref.watch(ownerProfileProvider);
  return ActiveProfileNotifier(ref, ownerProfileState.valueOrNull);
});

class ActiveProfileNotifier extends StateNotifier<Profile?> {
  final Ref _ref;

  ActiveProfileNotifier(this._ref, Profile? initialProfile) : super(initialProfile) {
    // Listen to changes in the owner profile (e.g., after Google Login replacement)
    _ref.listen<AsyncValue<Profile?>>(ownerProfileProvider, (previous, next) {
      final prevOwner = previous?.valueOrNull;
      final nextOwner = next.valueOrNull;
      
      // Auto-update active profile if it was null, or if it was set to the previous owner profile
      if (state == null || (prevOwner != null && state!.id == prevOwner.id)) {
        state = nextOwner;
      }
    });
  }

  void setActiveProfile(Profile profile) {
    state = profile;
  }

  void clearActiveProfile() {
    state = null;
  }
}
