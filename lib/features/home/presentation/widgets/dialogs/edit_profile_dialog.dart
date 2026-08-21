import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          final colorScheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;
          return AlertDialog(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            title: Text(
              'Edit Profile Name',
              style: textTheme.titleMedium,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (errorMessage != null) ...[
                  Text(
                    errorMessage!,
                    style: TextStyle(
                      color: colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 10),
                ],
                Text('Profile Name', style: textTheme.labelLarge),
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
                    hintText: 'Enter profile name',
                    counterText: '',
                  ),
                  enabled: !isLoading,
                ),
                if (parentAppCode != null && parentAppCode.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    profile.isOwner ? 'App Code' : 'Parent App Code',
                    style: textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: appCodeController,
                    readOnly: true,
                    enabled: false,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colorScheme.surface.withOpacity(0.3),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.surface.withOpacity(0.6)),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.copy, size: 18, color: colorScheme.secondary),
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
                        child: Text('Cancel', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5))),
                      ),
                      SizedBox(width: 8),
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
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text('Save'),
                      ),
                    ],
                  ),
                  if (!profile.isOwner) ...[
                    SizedBox(height: 16),
                    Divider(color: colorScheme.surface),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(color: colorScheme.error, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        icon: Icon(Icons.delete_outline, size: 18, color: colorScheme.error),
                        label: Text(
                          'Delete Profile',
                          style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.error),
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
