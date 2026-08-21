import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          final colorScheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;
          return AlertDialog(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: colorScheme.error, size: 24),
                SizedBox(width: 10),
                Text('Delete Profile', style: textTheme.titleMedium),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
                    children: [
                      const TextSpan(text: 'Are you sure you want to delete the profile '),
                      TextSpan(
                        text: '"${profile.profileName}"',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: '?\n\n'),
                      TextSpan(
                        text: 'This will permanently remove all medication data, schedules, '
                            'and dosing history for this profile from your device.',
                        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isDeleting ? null : () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: Colors.white,
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
                          color: Colors.white,
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
