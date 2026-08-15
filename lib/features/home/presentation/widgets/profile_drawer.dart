import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../../../onboarding/presentation/providers/onboarding_provider.dart';
import '../../../onboarding/domain/entities/profile.dart';
import 'package:intl/intl.dart';
import '../../../sync/presentation/providers/auth_provider.dart';
import '../../../sync/presentation/providers/sync_provider.dart';
import 'dialogs/go_premium_dialog.dart';
import 'dialogs/add_family_member_dialog.dart';
import 'dialogs/edit_profile_dialog.dart';
import 'dialogs/delete_profile_dialog.dart';

class ProfileDrawer extends ConsumerWidget {
  const ProfileDrawer({super.key});

  void _showGoPremiumDialog(BuildContext context) =>
      showGoPremiumDialog(context);

  void _showAddFamilyMemberDialog(BuildContext context, WidgetRef ref) =>
      showAddFamilyMemberDialog(context, ref);

  void _showFloatingCooldownMessage(BuildContext context, int seconds) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 32,
        left: 24,
        right: 24,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.textPrimary.withOpacity(0.92),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppColors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You can trigger sync again after $seconds seconds',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }

  void _showEditProfileDialog(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) => showEditProfileDialog(context, ref, profile);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeProfile = ref.watch(activeProfileProvider);
    final profilesState = ref.watch(profilesListProvider);
    final authState = ref.watch(authProvider);
    final syncState = ref.watch(syncStateProvider);

    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header with Active User Info
            Container(
              padding: const EdgeInsets.all(24.0),
              width: double.infinity,
              color: AppColors.cardFill.withOpacity(0.2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                        },
                        child: CircleAvatar(
                          radius: 30,
                          backgroundColor: AppColors.accent.withOpacity(0.2),
                          child: Text(
                            (activeProfile?.profileName.isNotEmpty ?? false)
                                ? activeProfile!.profileName[0].toUpperCase()
                                : '?',
                            style: AppTextStyles.titleMedium.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              activeProfile?.profileName ?? 'User Profile',
                              style: AppTextStyles.titleSmall.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (activeProfile != null &&
                                !activeProfile.isOwner) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Read-only Profile',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Profiles list
            Expanded(
              child: profilesState.when(
                data: (profiles) {
                  final ownerProfile = profiles.firstWhere(
                    (p) => p.isOwner,
                    orElse: () => activeProfile ?? profiles.first,
                  );
                  final isCaretaker = ownerProfile.profileType == 'Caretaker';

                  return ListView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'PROFILES',
                              style: AppTextStyles.titleSmall,
                            ),
                            if (isCaretaker)
                              IconButton(
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  color: AppColors.accent,
                                ),
                                onPressed: () {
                                  final familyCount = profiles
                                      .where((p) => !p.isOwner)
                                      .length;
                                  if (familyCount >= 2) {
                                    _showGoPremiumDialog(context);
                                  } else {
                                    _showAddFamilyMemberDialog(context, ref);
                                  }
                                },
                                tooltip: 'Add Family Member',
                              ),
                          ],
                        ),
                      ),
                      ...profiles.map((profile) {
                        final isSelected = activeProfile?.id == profile.id;

                        // Check if caretaker has a pending connection request for this profile
                        String? connectionStatus;
                        if (!profile.isOwner &&
                            authState.isAuthenticated &&
                            authState.firebaseUser != null) {
                          final conns =
                              ref
                                  .watch(caretakerConnectionsProvider)
                                  .valueOrNull ??
                              [];
                          final conn = conns.firstWhere(
                            (c) => c['parent_app_code'] == profile.appCode,
                            orElse: () => <String, dynamic>{},
                          );
                          connectionStatus = conn['status'] as String?;
                        }

                        final isCaretakerItem = profile.profileType == 'Caretaker';

                        if (isCaretakerItem) {
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.cardFill
                                  : AppColors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: isSelected
                                  ? Border.all(
                                      color: AppColors.accent.withOpacity(0.3),
                                      width: 1.5,
                                    )
                                  : null,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: AppColors.accent.withOpacity(0.35),
                                        offset: const Offset(0, 2),
                                        blurRadius: 6,
                                        spreadRadius: 0,
                                      ),
                                      BoxShadow(
                                        color: AppColors.white.withOpacity(0.6),
                                        offset: const Offset(0, -1),
                                        blurRadius: 2,
                                        spreadRadius: 0,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: InkWell(
                              onTap: () {
                                ref
                                    .read(activeProfileProvider.notifier)
                                    .setActiveProfile(profile);
                                context.pop(); // Close drawer
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 13,
                                      backgroundColor: isSelected
                                          ? AppColors.accent
                                          : AppColors.cardFill,
                                      child: Text(
                                        profile.profileName[0].toUpperCase(),
                                        style: TextStyle(
                                          color: isSelected
                                              ? AppColors.white
                                              : AppColors.textPrimary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        profile.profileName,
                                        style: AppTextStyles.labelLarge.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => _showEditProfileDialog(
                                        context,
                                        ref,
                                        profile,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4.0),
                                        child: Icon(
                                          Icons.edit,
                                          size: 16,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.cardFill
                                : AppColors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: isSelected
                                ? Border.all(
                                    color: AppColors.accent.withOpacity(0.3),
                                    width: 1.5,
                                  )
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: AppColors.accent.withOpacity(0.35),
                                      offset: const Offset(0, 2),
                                      blurRadius: 6,
                                      spreadRadius: 0,
                                    ),
                                    BoxShadow(
                                      color: AppColors.white.withOpacity(0.6),
                                      offset: const Offset(0, -1),
                                      blurRadius: 2,
                                      spreadRadius: 0,
                                    ),
                                  ]
                                : null,
                          ),
                          child: InkWell(
                            onTap: () {
                              ref
                                  .read(activeProfileProvider.notifier)
                                  .setActiveProfile(profile);
                              context.pop(); // Close drawer
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // First Line: Avatar + Profile Name
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: isSelected
                                            ? AppColors.accent
                                            : AppColors.cardFill,
                                        child: Text(
                                          profile.profileName[0].toUpperCase(),
                                          style: TextStyle(
                                            color: isSelected
                                                ? AppColors.white
                                                : AppColors.textPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          profile.profileName,
                                          style: AppTextStyles.labelLarge.copyWith(
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  // Second Line: Date/Time + Family Tag + Edit Icon
                                  Row(
                                    children: [
                                      Expanded(
                                        child: (profile.profileType == 'Caretaker')
                                            ? const SizedBox.shrink()
                                            : Text(
                                                (!profile.isOwner &&
                                                        connectionStatus == 'pending')
                                                    ? 'Pending Approval'
                                                    : (profile.lastSync != null
                                                        ? 'Synced: ${_formatLastSyncTime(profile.lastSync!)}'
                                                        : 'Synced: Never'),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: (!profile.isOwner &&
                                                          connectionStatus == 'pending')
                                                      ? AppColors.red
                                                      : AppColors.textSecondary,
                                                  fontWeight: (!profile.isOwner &&
                                                          connectionStatus == 'pending')
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                      ),
                                      if (!profile.isOwner &&
                                          connectionStatus != 'pending')
                                        Container(
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.cardFill,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Family',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppColors.textSecondary,
                                              fontWeight: FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                      InkWell(
                                        onTap: () => _showEditProfileDialog(
                                          context,
                                          ref,
                                          profile,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4.0),
                                          child: Icon(
                                            Icons.edit,
                                            size: 16,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error loading profiles: $err'),
                ),
              ),
            ),

            const Divider(height: 1),

            // Navigation Links Footer
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(
                      Icons.medication_outlined,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    title: const Text(
                      'Medicines List',
                      style: AppTextStyles.labelLarge,
                    ),
                    onTap: () {
                      context.pop();
                      context.push(AppConstants.routeMedicinesList);
                    },
                  ),
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(
                      Icons.history_outlined,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    title: const Text(
                      'Adherence History',
                      style: AppTextStyles.labelLarge,
                    ),
                    onTap: () {
                      context.pop();
                      context.push(AppConstants.routeHistory);
                    },
                  ),
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(
                      Icons.settings_outlined,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    title: const Text(
                      'Settings',
                      style: AppTextStyles.labelLarge,
                    ),
                    onTap: () {
                      context.pop();
                      context.push(AppConstants.routeSettings);
                    },
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            const Divider(height: 1),

            // Cloud Sync & App Code Card
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                color: AppColors.background,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppColors.cardFill.withOpacity(0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (authState.isAuthenticated) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.cloud_done,
                              color: AppColors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Family Sync Active',
                                style: AppTextStyles.labelLarge.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: AppColors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Display generated App Code
                        profilesState.when(
                          data: (profiles) {
                            final owner = profiles.firstWhere(
                              (p) => p.isOwner,
                              orElse: () => profiles.first,
                            );
                            final rawCode = owner.appCode;
                            final isPending =
                                rawCode == null ||
                                rawCode == 'None' ||
                                rawCode.isEmpty;
                            final myCode = isPending ? 'None' : rawCode;

                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'MY APP CODE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    if (isPending)
                                      const SizedBox(
                                        height: 20,
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.accent,
                                              ),
                                            ),
                                            SizedBox(width: 6),
                                            Text(
                                              'Generating...',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      Text(
                                        myCode,
                                        style: AppTextStyles.titleMedium
                                            .copyWith(
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.5,
                                            ),
                                      ),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.copy,
                                    size: 16,
                                    color: AppColors.accent,
                                  ),
                                  onPressed: isPending
                                      ? null
                                      : () {
                                          Clipboard.setData(
                                            ClipboardData(text: myCode),
                                          );
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'App Code copied to clipboard',
                                              ),
                                            ),
                                          );
                                        },
                                  tooltip: 'Copy Code',
                                ),
                              ],
                            );
                          },
                          loading: () => const LinearProgressIndicator(),
                          error: (_, __) =>
                              const Text('Error loading app code'),
                        ),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (context) {
                            final profiles = profilesState.valueOrNull ?? [];
                            final currentProfile = profiles.where((p) => p.id == activeProfile?.id).firstOrNull 
                                ?? activeProfile 
                                ?? profiles.firstOrNull;

                            final isCaretaker = currentProfile?.profileType == 'Caretaker';
                            if (isCaretaker) {
                              return const Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'Caretaker Profile (Family Manager)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }

                            final displayLastSync = currentProfile?.lastSync;
                            final isOwner = currentProfile?.isOwner ?? true;

                            final String lastSyncText = displayLastSync != null
                                ? 'Last synced: ${_formatLastSyncTime(displayLastSync)}'
                                : 'Last synced: Never';

                            if (!isOwner) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  lastSyncText,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              );
                            }

                            final dirtyStateAsync = ref.watch(
                              syncHasDirtyRowsProvider,
                            );
                            final isDirty =
                                dirtyStateAsync.asData?.value ?? false;

                            final String syncStatusText = isDirty
                                ? '(out of sync)'
                                : '(fully synced)';
                            final Color syncStatusColor = isDirty
                                ? AppColors.red
                                : AppColors.green;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '$lastSyncText ',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        fontSize: 10,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    TextSpan(
                                      text: syncStatusText,
                                      style: AppTextStyles.bodySmall.copyWith(
                                        fontSize: 10,
                                        color: syncStatusColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                ),
                                onPressed: syncState.isSyncing
                                    ? null
                                    : () {
                                        ref
                                            .read(
                                              activeProfileProvider.notifier,
                                            )
                                            .setActiveProfile(activeProfile!);
                                        if (activeProfile!.isOwner) {
                                          ref
                                              .read(syncStateProvider.notifier)
                                              .sync();
                                        } else {
                                          final cooldown = ref
                                              .read(syncStateProvider.notifier)
                                              .requestManualPull();
                                          if (cooldown != null &&
                                              context.mounted) {
                                            _showFloatingCooldownMessage(
                                              context,
                                              cooldown,
                                            );
                                          }
                                        }
                                      },
                                icon: syncState.isSyncing
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.accent,
                                        ),
                                      )
                                    : const Icon(Icons.sync, size: 14),
                                label: Text(
                                  syncState.isSyncing
                                      ? 'Syncing...'
                                      : 'Sync Now',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                Icons.logout,
                                size: 16,
                                color: AppColors.red,
                              ),
                              onPressed: () =>
                                  ref.read(authProvider.notifier).signOut(),
                              tooltip: 'Sign Out',
                            ),
                          ],
                        ),
                        if (syncState.errorMessage != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            syncState.errorMessage!,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.red,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ] else ...[
                        const Row(
                          children: [
                            Icon(
                              Icons.cloud_off,
                              color: AppColors.textSecondary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Family Sync Disabled',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sign in to synchronize data with caretakers and restore backups.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            onPressed: authState.isLoading
                                ? null
                                : () => ref
                                      .read(authProvider.notifier)
                                      .signInWithGoogle(),
                            icon: authState.isLoading
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.white,
                                    ),
                                  )
                                : const Icon(Icons.login, size: 14),
                            label: const Text(
                              'Sign in with Google',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                      if (syncState.errorMessage != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          syncState.errorMessage!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Pending Connection Requests list (only for authenticated owner)
            if (authState.isAuthenticated &&
                activeProfile != null &&
                activeProfile.isOwner)
              ref
                  .watch(pendingConnectionsProvider)
                  .when(
                    data: (requests) {
                      if (requests.isEmpty) return const SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.cardFill.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CONNECTION REQUESTS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accent,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...requests.map((request) {
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  request['display_name'] ?? 'Caretaker',
                                ),
                                subtitle: Text(
                                  'Code: ${request['caretaker_app_code']}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.check,
                                        color: AppColors.green,
                                        size: 20,
                                      ),
                                      onPressed: () async {
                                        final profiles =
                                            ref
                                                .read(profilesListProvider)
                                                .value ??
                                            [];
                                        final owner = profiles.firstWhere(
                                          (p) => p.isOwner,
                                        );

                                        // 1. Mark all Parent SQLite profile rows as dirty (is_dirty = 1)
                                        await ref.read(syncRepositoryProvider).markAllRowsDirty(owner.id);

                                        // 2. Update connection status to active in RTDB
                                        await ref
                                            .read(syncRemoteDataSourceProvider)
                                            .acceptConnection(
                                              parentAppCode: owner.appCode!,
                                              caretakerAppCode:
                                                  request['caretaker_app_code'],
                                              caretakerUid: request['uid'],
                                              parentName: owner.profileName,
                                            );

                                        // 3. Trigger immediate push sync to Caretaker
                                        await ref.read(syncRepositoryProvider).syncAll(owner.id);
                                      },
                                      tooltip: 'Accept',
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: AppColors.red,
                                        size: 20,
                                      ),
                                      onPressed: () async {
                                        final profiles =
                                            ref
                                                .read(profilesListProvider)
                                                .value ??
                                            [];
                                        final owner = profiles.firstWhere(
                                          (p) => p.isOwner,
                                        );
                                        await ref
                                            .read(syncRemoteDataSourceProvider)
                                            .rejectConnection(
                                              parentAppCode: owner.appCode!,
                                              caretakerAppCode:
                                                  request['caretaker_app_code'],
                                              caretakerUid: request['uid'],
                                            );
                                      },
                                      tooltip: 'Reject',
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
          ],
        ),
      ),
    );
  }

  static String _formatLastSyncTime(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    final now = DateTime.now().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCompare = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final timeStr = DateFormat('h:mm a').format(dateTime);

    if (dateToCompare == today) {
      return 'Today, $timeStr';
    } else if (dateToCompare == yesterday) {
      return 'Yesterday, $timeStr';
    } else if (dateTime.year == now.year) {
      return '${DateFormat('d MMM').format(dateTime)}, $timeStr';
    } else {
      return '${DateFormat('d MMM yyyy').format(dateTime)}, $timeStr';
    }
  }
}
