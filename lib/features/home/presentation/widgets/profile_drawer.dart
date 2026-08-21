import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'dialogs/logout_dialog.dart';

class ProfileDrawer extends ConsumerWidget {
  ProfileDrawer({super.key});

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
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.92),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You can trigger sync again after $seconds seconds',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
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
    Future.delayed(Duration(seconds: 2), () {
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final greenColor = isDark ? Color(0xFF66BB6A) : Color(0xFF81C784);
    final activeProfile = ref.watch(activeProfileProvider);
    final profilesState = ref.watch(profilesListProvider);
    final authState = ref.watch(authProvider);
    final syncState = ref.watch(syncStateProvider);

    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header with Active User Info
            Container(
              padding: const EdgeInsets.all(24.0),
              width: double.infinity,
              color: colorScheme.surface.withOpacity(0.2),
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
                          backgroundColor: colorScheme.secondary.withOpacity(
                            0.2,
                          ),
                          child: Text(
                            (activeProfile?.profileName.isNotEmpty ?? false)
                                ? activeProfile!.profileName[0].toUpperCase()
                                : '?',
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.secondary,
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
                              style: textTheme.titleSmall?.copyWith(
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
                                  color: colorScheme.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Read-only Profile',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colorScheme.error,
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
                            Text('PROFILES', style: textTheme.titleSmall),
                            if (isCaretaker)
                              IconButton(
                                icon: Icon(
                                  Icons.add_circle_outline,
                                  color: colorScheme.secondary,
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

                        final isCaretakerItem =
                            profile.profileType == 'Caretaker';

                        if (isCaretakerItem) {
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.surface
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: isSelected
                                  ? Border.all(
                                      color: colorScheme.secondary.withOpacity(
                                        0.3,
                                      ),
                                      width: 1.5,
                                    )
                                  : null,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: colorScheme.secondary
                                            .withOpacity(0.35),
                                        offset: const Offset(0, 2),
                                        blurRadius: 6,
                                        spreadRadius: 0,
                                      ),
                                      BoxShadow(
                                        color: Colors.white.withOpacity(0.6),
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
                                          ? colorScheme.secondary
                                          : colorScheme.surface,
                                      child: Text(
                                        profile.profileName[0].toUpperCase(),
                                        style: TextStyle(
                                          color: isSelected
                                              ? Colors.white
                                              : colorScheme.onSurface,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        profile.profileName,
                                        style: textTheme.labelLarge?.copyWith(
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
                                      child: Padding(
                                        padding: EdgeInsets.all(4.0),
                                        child: Icon(
                                          Icons.edit,
                                          size: 16,
                                          color: colorScheme.onSurface
                                              .withOpacity(0.5),
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
                                ? colorScheme.surface
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: isSelected
                                ? Border.all(
                                    color: colorScheme.secondary.withOpacity(
                                      0.3,
                                    ),
                                    width: 1.5,
                                  )
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: colorScheme.secondary.withOpacity(
                                        0.35,
                                      ),
                                      offset: const Offset(0, 2),
                                      blurRadius: 6,
                                      spreadRadius: 0,
                                    ),
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.6),
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
                                            ? colorScheme.secondary
                                            : colorScheme.surface,
                                        child: Text(
                                          profile.profileName[0].toUpperCase(),
                                          style: TextStyle(
                                            color: isSelected
                                                ? Colors.white
                                                : colorScheme.onSurface,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          profile.profileName,
                                          style: textTheme.labelLarge?.copyWith(
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
                                        child:
                                            (profile.profileType == 'Caretaker')
                                            ? const SizedBox.shrink()
                                            : Text(
                                                (!profile.isOwner &&
                                                        connectionStatus ==
                                                            'pending')
                                                    ? 'Pending Approval'
                                                    : (profile.lastSync != null
                                                          ? 'Synced: ${_formatLastSyncTime(profile.lastSync!)}'
                                                          : 'Synced: Never'),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      (!profile.isOwner &&
                                                          connectionStatus ==
                                                              'pending')
                                                      ? colorScheme.error
                                                      : colorScheme.onSurface
                                                            .withOpacity(0.5),
                                                  fontWeight:
                                                      (!profile.isOwner &&
                                                          connectionStatus ==
                                                              'pending')
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                ),
                                              ),
                                      ),
                                      if (!profile.isOwner &&
                                          connectionStatus != 'pending')
                                        Container(
                                          margin: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.surface,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'Family',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: colorScheme.onSurface
                                                  .withOpacity(0.5),
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
                                        child: Padding(
                                          padding: EdgeInsets.all(4.0),
                                          child: Icon(
                                            Icons.edit,
                                            size: 16,
                                            color: colorScheme.onSurface
                                                .withOpacity(0.5),
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
                      if (!isCaretaker)
                        Builder(
                          builder: (context) {
                            final activeConns =
                                ref
                                    .watch(parentActiveConnectionsProvider)
                                    .valueOrNull ??
                                [];
                            if (activeConns.isEmpty) {
                              return const SizedBox.shrink();
                            }

                            final isDark =
                                Theme.of(context).brightness ==
                                Brightness.dark;
                            final greenColor =
                                isDark
                                    ? const Color(0xFF66BB6A)
                                    : const Color(0xFF81C784);

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children:
                                  activeConns.map((conn) {
                                    final caretakerName =
                                        conn['display_name'] as String? ??
                                        'Caretaker';
                                    final caretakerAppCode =
                                        conn['caretaker_app_code']
                                            as String? ??
                                        '';
                                    final text =
                                        caretakerAppCode.isNotEmpty
                                            ? '$caretakerName ($caretakerAppCode) is tracking your medicine doses, please consume and log on time.'
                                            : '$caretakerName is tracking your medicine doses, please consume and log on time.';

                                    return Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: greenColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: greenColor.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.verified_user_outlined,
                                            size: 14,
                                            color: greenColor,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              text,
                                              style: textTheme.bodySmall
                                                  ?.copyWith(
                                                    fontSize: 11,
                                                    color: colorScheme
                                                        .onSurface
                                                        .withValues(alpha: 0.9),
                                                    height: 1.3,
                                                    fontWeight:
                                                        FontWeight.w500,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                            );
                          },
                        ),
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
                    leading: Icon(
                      Icons.medication_outlined,
                      color: colorScheme.secondary,
                      size: 20,
                    ),
                    title: Text('Medicines List', style: textTheme.labelLarge),
                    onTap: () {
                      context.pop();
                      context.push(AppConstants.routeMedicinesList);
                    },
                  ),
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      Icons.history_outlined,
                      color: colorScheme.secondary,
                      size: 20,
                    ),
                    title: Text(
                      'Adherence History',
                      style: textTheme.labelLarge,
                    ),
                    onTap: () {
                      context.pop();
                      context.push(AppConstants.routeHistory);
                    },
                  ),
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      Icons.settings_outlined,
                      color: colorScheme.secondary,
                      size: 20,
                    ),
                    title: Text('Settings', style: textTheme.labelLarge),
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
                color: Theme.of(context).scaffoldBackgroundColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.surface.withOpacity(0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (authState.isAuthenticated) ...[
                        Row(
                          children: [
                            Icon(Icons.cloud_done, color: greenColor, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Family Sync Active',
                                style: textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: greenColor,
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
                            final isParent = owner.profileType == 'Parent';

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'MY APP CODE',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.5),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        if (isPending)
                                          SizedBox(
                                            height: 20,
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: colorScheme
                                                            .secondary,
                                                      ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Generating...',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: colorScheme.onSurface
                                                        .withValues(alpha: 0.5),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else
                                          Text(
                                            myCode,
                                            style: textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.5,
                                                ),
                                          ),
                                      ],
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.copy,
                                        size: 16,
                                        color: colorScheme.secondary,
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
                                ),
                                if (isParent && !isPending)
                                  Builder(
                                    builder: (context) {
                                      final activeConns =
                                          ref
                                              .watch(
                                                parentActiveConnectionsProvider,
                                              )
                                              .valueOrNull ??
                                          [];
                                      final isPaired = activeConns.isNotEmpty;

                                      if (!isPaired) {
                                        return Container(
                                          margin: const EdgeInsets.only(top: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colorScheme.secondary
                                                .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: colorScheme.secondary
                                                  .withValues(alpha: 0.2),
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.info_outline_rounded,
                                                size: 14,
                                                color: colorScheme.secondary,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  'Share your App Code with your family member. Once they add it in their profile menu, your data will be synced.',
                                                  style: textTheme.bodySmall
                                                      ?.copyWith(
                                                        fontSize: 11,
                                                        color: colorScheme
                                                            .onSurface
                                                            .withValues(
                                                              alpha: 0.8,
                                                            ),
                                                        height: 1.3,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }

                                      return const SizedBox.shrink();
                                    },
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
                            final colorScheme = Theme.of(context).colorScheme;
                            final textTheme = Theme.of(context).textTheme;
                            final isDark =
                                Theme.of(context).brightness == Brightness.dark;
                            final greenColor = isDark
                                ? Color(0xFF66BB6A)
                                : Color(0xFF81C784);
                            final profiles = profilesState.valueOrNull ?? [];
                            final currentProfile =
                                profiles
                                    .where((p) => p.id == activeProfile?.id)
                                    .firstOrNull ??
                                activeProfile ??
                                profiles.firstOrNull;

                            final isCaretaker =
                                currentProfile?.profileType == 'Caretaker';
                            if (isCaretaker) {
                              final hasParentProfiles = profiles.any(
                                (p) => !p.isOwner,
                              );
                              if (!hasParentProfiles) {
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondary.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: colorScheme.secondary.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 14,
                                        color: colorScheme.secondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          "Add your parent's profile first to sync and track their medicines",
                                          style: textTheme.bodySmall?.copyWith(
                                            fontSize: 11,
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.8),
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'Caretaker Profile (Family Manager)',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.5,
                                    ),
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
                                  style: textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                    color: colorScheme.onSurface.withOpacity(
                                      0.5,
                                    ),
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
                                ? colorScheme.error
                                : greenColor;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '$lastSyncText ',
                                      style: textTheme.bodySmall?.copyWith(
                                        fontSize: 10,
                                        color: colorScheme.onSurface
                                            .withOpacity(0.5),
                                      ),
                                    ),
                                    TextSpan(
                                      text: syncStatusText,
                                      style: textTheme.bodySmall?.copyWith(
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
                                    ? SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colorScheme.secondary,
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
                              icon: Icon(
                                Icons.logout,
                                size: 16,
                                color: colorScheme.error,
                              ),
                              onPressed: () =>
                                  showLogoutConfirmationDialog(context, ref),
                              tooltip: 'Sign Out',
                            ),
                          ],
                        ),
                        if (syncState.errorMessage != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            syncState.errorMessage!,
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.error,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ] else ...[
                        Row(
                          children: [
                            Icon(
                              Icons.cloud_off,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Family Sync Disabled',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final profiles = profilesState.valueOrNull ?? [];
                            final currentProfile =
                                profiles
                                    .where((p) => p.id == activeProfile?.id)
                                    .firstOrNull ??
                                activeProfile ??
                                profiles.firstOrNull;
                            final isCaretaker =
                                currentProfile?.profileType == 'Caretaker';

                            final guidanceText = isCaretaker
                                ? "Login and add your parent's profile to sync and track their medicines."
                                : "Login and share your App Code with your family member. Once they add it in their profile menu, your data will be synced.";

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.secondary.withValues(
                                  alpha: 0.08,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: colorScheme.secondary.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    size: 14,
                                    color: colorScheme.secondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      guidanceText,
                                      style: textTheme.bodySmall?.copyWith(
                                        fontSize: 11,
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.8,
                                        ),
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.secondary,
                              foregroundColor: Colors.white,
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
                                      color: Colors.white,
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
                          style: TextStyle(
                            fontSize: 10,
                            color: colorScheme.error,
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
                          color: colorScheme.surface.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CONNECTION REQUESTS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.secondary,
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
                                      icon: Icon(
                                        Icons.check,
                                        color: greenColor,
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
                                        await ref
                                            .read(syncRepositoryProvider)
                                            .markAllRowsDirty(owner.id);

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
                                        await ref
                                            .read(syncRepositoryProvider)
                                            .syncAll(owner.id);
                                      },
                                      tooltip: 'Accept',
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.close,
                                        color: colorScheme.error,
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
