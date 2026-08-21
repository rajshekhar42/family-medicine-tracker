import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../sync/presentation/providers/auth_provider.dart';

/// Shows a confirmation dialog with a warning message before signing out.
void showLogoutConfirmationDialog(BuildContext context, WidgetRef ref) {
  bool isLoggingOut = false;

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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: colorScheme.error,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  'Sign Out',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Are you sure you want to sign out?',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Signing out will pause family synchronization, shared medicine tracking, and cloud backups until you sign in again.',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isLoggingOut ? null : () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isLoggingOut
                    ? null
                    : () async {
                        setState(() => isLoggingOut = true);
                        try {
                          await ref.read(authProvider.notifier).signOut();
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to sign out: $e'),
                                backgroundColor: colorScheme.error,
                              ),
                            );
                          }
                        }
                      },
                child: isLoggingOut
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Sign Out',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          );
        },
      );
    },
  );
}
