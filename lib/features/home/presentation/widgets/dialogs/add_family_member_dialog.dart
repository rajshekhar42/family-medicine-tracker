import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../onboarding/presentation/providers/onboarding_provider.dart';
import '../../../../sync/presentation/providers/auth_provider.dart';
import '../../../../sync/presentation/providers/sync_provider.dart';

/// Shows the dialog that allows a Caretaker to pair with a Parent by entering
/// the Parent's App Code and providing a local display name.
void showAddFamilyMemberDialog(BuildContext context, WidgetRef ref) {
  final nameController = TextEditingController();
  final codeController = TextEditingController();
  bool isLoading = false;
  String? errorMessage;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.background,
            title: const Text(
              'Add Family Member',
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
                const Text('App Code', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: codeController,
                  autocorrect: false,
                  autofillHints: null,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'e.g. A123456'),
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                const Text('Display Name', style: AppTextStyles.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: nameController,
                  autocorrect: false,
                  autofillHints: null,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Father, Mother',
                  ),
                  enabled: !isLoading,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final code = codeController.text.trim().toUpperCase();
                        final name = nameController.text.trim();

                        if (code.isEmpty || name.isEmpty) {
                          setState(() => errorMessage = 'Both fields are required');
                          return;
                        }

                        // Check family member count limit (max 2)
                        final profiles = ref.read(profilesListProvider).value ?? [];
                        final familyCount = profiles.where((p) => !p.isOwner).length;
                        if (familyCount >= 2) {
                          setState(() => errorMessage = 'Go Premium to add more than 2 Parent profiles.');
                          return;
                        }

                        // Check profile name uniqueness (case-insensitive)
                        final isDuplicateName = profiles.any(
                          (p) => p.profileName.trim().toLowerCase() == name.toLowerCase(),
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
                          // Validate App Code exists in Firebase RTDB
                          final remoteDs = ref.read(syncRemoteDataSourceProvider);
                          final parentProfile = await remoteDs.lookupProfileByAppCode(code);

                          if (parentProfile == null) {
                            setState(() {
                              isLoading = false;
                              errorMessage = 'Invalid App Code. Profile not found.';
                            });
                            return;
                          }

                          final parentProfileType = parentProfile['profile_type'] as String? ?? 'Parent';
                          if (parentProfileType == 'Caretaker') {
                            setState(() {
                              isLoading = false;
                              errorMessage =
                                  'This App Code belongs to a Caretaker profile and cannot be added as a Parent.';
                            });
                            return;
                          }

                          final parentUid = parentProfile['uid'] as String;

                          // Add family member locally in SQLite
                          await ref.read(profilesListProvider.notifier).addSyncedFamilyMember(
                                id: parentUid,
                                name: name,
                                timeZone: parentProfile['presence'] ?? 'UTC',
                                appCode: code,
                              );

                          // Request connection in Firebase RTDB
                          final ownerProfile = profiles.firstWhere((p) => p.isOwner);
                          final authState = ref.read(authProvider);
                          if (authState.firebaseUser != null && ownerProfile.appCode != null) {
                            await remoteDs.requestConnection(
                              parentAppCode: code,
                              parentName: name,
                              caretakerAppCode: ownerProfile.appCode!,
                              caretakerUid: authState.firebaseUser!.uid,
                              caretakerDisplayName: ownerProfile.profileName,
                            );
                          }

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Family pairing request sent. Awaiting Parent approval.'),
                              ),
                            );
                          }
                        } catch (e) {
                          setState(() {
                            isLoading = false;
                            errorMessage = 'Failed to pair profile: $e';
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
                    : const Text('Add'),
              ),
            ],
          );
        },
      );
    },
  );
}

