import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../onboarding/domain/entities/profile.dart';
import '../../../../onboarding/presentation/providers/onboarding_provider.dart';

/// Shows a confirmation dialog before permanently deleting a non-owner profile.
///
/// Deletes all locally stored data for [profile] and removes the RTDB
/// connection link via [OnboardingRepository].
void showDeleteProfileDialog(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) {
  bool isDeleting = false;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.background,
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 24),
                SizedBox(width: 10),
                Text('Delete Profile', style: AppTextStyles.titleMedium),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    children: [
                      const TextSpan(text: 'Are you sure you want to delete the profile '),
                      TextSpan(
                        text: '"${profile.profileName}"',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: '?\n\n'),
                      const TextSpan(
                        text: 'This will permanently remove all medication data, schedules, '
                            'and dosing history for this profile from your device.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: AppColors.white,
                ),
                onPressed: isDeleting
                    ? null
                    : () async {
                        setState(() => isDeleting = true);
                        try {
                          await ref
                              .read(profilesListProvider.notifier)
                              .deleteParentProfile(profile);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '"${profile.profileName}" profile has been deleted.',
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          setState(() => isDeleting = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to delete profile: $e')),
                            );
                          }
                        }
                      },
                child: isDeleting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      );
    },
  );
}
