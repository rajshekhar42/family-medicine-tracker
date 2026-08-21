import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      return Consumer(
        builder: (context, ref, _) {
          final authState = ref.watch(authProvider);
          final isLoggedIn = authState.isAuthenticated && authState.firebaseUser != null;

          return StatefulBuilder(
            builder: (context, setState) {
              final colorScheme = Theme.of(context).colorScheme;
              final textTheme = Theme.of(context).textTheme;

              return AlertDialog(
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Text(
                  'Add Family Member',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Informative message when Caretaker has not completed Google Login
                      if (!isLoggedIn) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: colorScheme.secondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.secondary.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 20,
                                    color: colorScheme.secondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Google Sign-In Required',
                                      style: textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'You can add and sync family members after you log in with Google.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'To connect with family:\n'
                                '• Log in with Google in your profile menu.\n'
                                '• Ask your family member to register with a Parent profile.\n'
                                '• Have them complete their Google login and share their App Code with you.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurface.withValues(alpha: 0.75),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (errorMessage != null) ...[
                        Text(
                          errorMessage!,
                          style: TextStyle(
                            color: colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Text('App Code', style: textTheme.labelLarge),
                      const SizedBox(height: 8),
                      TextField(
                        controller: codeController,
                        autocorrect: false,
                        autofillHints: null,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 8,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: const InputDecoration(
                          hintText: 'e.g. A1234567',
                          counterText: '',
                        ),
                        enabled: !isLoading,
                      ),
                      const SizedBox(height: 16),
                      Text('Display Name', style: textTheme.labelLarge),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameController,
                        autocorrect: false,
                        autofillHints: null,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 20,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(20),
                        ],
                        decoration: const InputDecoration(
                          hintText: 'e.g. Father, Mother',
                          counterText: '',
                        ),
                        enabled: !isLoading,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isLoading ? null : () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
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

                            // App Code must start with an alphabet followed by 7 digits
                            final appCodeRegex = RegExp(r'^[A-Z]\d{7}$');
                            if (!appCodeRegex.hasMatch(code)) {
                              setState(
                                () => errorMessage =
                                    'App Code must start with a letter followed by 7 digits (e.g. A1234567).',
                              );
                              return;
                            }

                            // Display Name length check (max 20 characters)
                            if (name.length > 20) {
                              setState(
                                () => errorMessage =
                                    'Display Name cannot exceed 20 characters.',
                              );
                              return;
                            }

                            if (!isLoggedIn) {
                              setState(
                                () => errorMessage =
                                    'Please log in with Google first before adding a family member.',
                              );
                              return;
                            }

                            // Check family member count limit (max 2)
                            final profiles = ref.read(profilesListProvider).value ?? [];
                            final familyCount = profiles.where((p) => !p.isOwner).length;
                            if (familyCount >= 2) {
                              setState(
                                () => errorMessage =
                                    'Go Premium to add more than 2 Parent profiles.',
                              );
                              return;
                            }

                            // Check profile name uniqueness (case-insensitive)
                            final isDuplicateName = profiles.any(
                              (p) =>
                                  p.profileName.trim().toLowerCase() ==
                                  name.toLowerCase(),
                            );
                            if (isDuplicateName) {
                              setState(
                                () => errorMessage =
                                    'A profile with the name "$name" already exists. Please enter a unique name.',
                              );
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

                              final parentProfileType =
                                  parentProfile['profile_type'] as String? ?? 'Parent';
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
                              await ref
                                  .read(profilesListProvider.notifier)
                                  .addSyncedFamilyMember(
                                    id: parentUid,
                                    name: name,
                                    timeZone: parentProfile['presence'] ?? 'UTC',
                                    appCode: code,
                                  );

                              // Request connection in Firebase RTDB
                              final ownerProfile = profiles.firstWhere((p) => p.isOwner);
                              final currentAuthState = ref.read(authProvider);
                              if (currentAuthState.firebaseUser != null &&
                                  ownerProfile.appCode != null) {
                                await remoteDs.requestConnection(
                                  parentAppCode: code,
                                  parentName: name,
                                  caretakerAppCode: ownerProfile.appCode!,
                                  caretakerUid: currentAuthState.firebaseUser!.uid,
                                  caretakerDisplayName: ownerProfile.profileName,
                                );
                              }

                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Family pairing request sent. Awaiting Parent approval.',
                                    ),
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
                              color: Colors.white,
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
    },
  );
}
