import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../onboarding/domain/entities/profile.dart';
import '../../../../onboarding/presentation/providers/onboarding_provider.dart';
import '../../../../sync/presentation/providers/sync_provider.dart';
import 'delete_profile_dialog.dart';

/// Shows the dialog that allows editing a profile's display name and viewing
/// its App Code. For non-owner profiles, a Delete Profile option is also shown.
void showEditProfileDialog(
  BuildContext context,
  WidgetRef ref,
  Profile profile,
) {
  final nameController = TextEditingController(text: profile.profileName);
  bool isLoading = false;
  String? errorMessage;

  String? parentAppCode = profile.appCode;
  if ((parentAppCode == null || parentAppCode.isEmpty) && !profile.isOwner) {
    final connections = ref.read(caretakerConnectionsProvider).value ?? [];
    for (final conn in connections) {
      if (conn['parent_name'] == profile.profileName || conn['parent_uid'] == profile.id) {
        parentAppCode = conn['parent_app_code'] as String?;
        break;
      }
    }
  }
  final appCodeController = TextEditingController(text: parentAppCode ?? '');

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.background,
            title: const Text(
              'Edit Profile Name',
              style: AppTextStyles.titleMedium,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (errorMessage != null) ...[
                  Text(
                    errorMessage!,
                    style: const TextStyle(
                      color: AppColors.red,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                const Text('Profile Name', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  autocorrect: false,
                  autofillHints: null,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Enter profile name'),
                  enabled: !isLoading,
                ),
                if (parentAppCode != null && parentAppCode.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    profile.isOwner ? 'App Code' : 'Parent App Code',
                    style: AppTextStyles.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: appCodeController,
                    readOnly: true,
                    enabled: false,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.cardFill.withOpacity(0.3),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.cardFill.withOpacity(0.6)),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: AppColors.accent),
                        tooltip: 'Copy Code',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: parentAppCode!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('App Code copied to clipboard')),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actionsPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 20, top: 8),
            actions: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: isLoading ? null : () => Navigator.pop(context),
                        child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: isLoading
                            ? null
                            : () async {
                                final name = nameController.text.trim();
                                if (name.isEmpty) {
                                  setState(() => errorMessage = 'Name cannot be empty');
                                  return;
                                }

                                final profiles = ref.read(profilesListProvider).value ?? [];
                                final isDuplicateName = profiles.any(
                                  (p) => p.id != profile.id &&
                                      p.profileName.trim().toLowerCase() == name.toLowerCase(),
                                );
                                if (isDuplicateName) {
                                  setState(() => errorMessage =
                                      'A profile with the name "$name" already exists. Please enter a unique name.');
                                  return;
                                }

                                setState(() {
                                  isLoading = true;
                                  errorMessage = null;
                                });

                                try {
                                  await ref.read(profilesListProvider.notifier).updateProfileName(
                                        profile: profile,
                                        newName: name,
                                      );
                                  if (context.mounted) Navigator.pop(context);
                                } catch (e) {
                                  setState(() {
                                    isLoading = false;
                                    errorMessage = 'Failed to update name: $e';
                                  });
                                }
                              },
                        child: isLoading
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.white,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ],
                  ),
                  if (!profile.isOwner) ...[
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.cardFill),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.red),
                        label: const Text(
                          'Delete Profile',
                          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.red),
                        ),
                        onPressed: isLoading
                            ? null
                            : () {
                                Navigator.pop(context);
                                showDeleteProfileDialog(context, ref, profile);
                              },
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      );
    },
  );
}
