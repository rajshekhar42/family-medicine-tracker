import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/scheduled_dose.dart';
import '../providers/home_provider.dart';
import '../widgets/home_header.dart';
import '../widgets/weekly_date_strip.dart';
import '../widgets/medication_time_group.dart';
import '../widgets/empty_state.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../widgets/profile_drawer.dart';
import '../../../sync/presentation/providers/sync_provider.dart';
import '../../../sync/presentation/providers/auth_provider.dart';
import '../../../onboarding/presentation/providers/onboarding_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Perform auto-skip checks on initial screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoSkip();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed, triggering missed dose grace-period check...');
      _checkAutoSkip();
    }
  }

  Future<void> _checkAutoSkip() async {
    final activeProfile = ref.read(activeProfileProvider);
    if (activeProfile == null) return;

    final autoSkip = ref.read(autoSkipServiceProvider);
    await autoSkip.checkAndAutoSkipDoses(profileId: activeProfile.id);
    
    // Refresh dashboard list after auto-skips are processed
    ref.invalidate(homeDosesProvider);
  }

  Map<String, List<ScheduledDose>> _groupDosesByTime(List<ScheduledDose> doses) {
    final Map<String, List<ScheduledDose>> grouped = {};
    for (final dose in doses) {
      grouped.putIfAbsent(dose.scheduledTime, () => []).add(dose);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final dosesState = ref.watch(homeDosesProvider);
    final activeProfile = ref.watch(activeProfileProvider);
    final isReadOnly = activeProfile != null && !activeProfile.isOwner;
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      
      // Profile and navigation menu Drawer
      drawer: const ProfileDrawer(),
      
      body: SafeArea(
        child: Column(
          children: [
            // Header: Avatar, title, calendar icon
            const HomeHeader(),
            
            // Weekly date strip Sun-Sat
            const WeeklyDateStrip(),
            
            // Pending connection requests banner (Home Screen Banner)
            if (authState.isAuthenticated && activeProfile != null && activeProfile.isOwner)
              ref.watch(pendingConnectionsProvider).when(
                data: (requests) {
                  if (requests.isEmpty) return const SizedBox.shrink();
                  return Column(
                    children: requests.map((request) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.accent.withOpacity(0.85),
                              AppColors.accent.withOpacity(0.95),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accent.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.people_alt_outlined, color: AppColors.white, size: 22),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Connection Request',
                                      style: AppTextStyles.labelLarge.copyWith(
                                        color: AppColors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Accept pairing request from ${request['display_name'] ?? 'Caretaker'} (Code: ${request['caretaker_app_code']})?',
                                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white.withOpacity(0.9)),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(color: AppColors.white.withOpacity(0.5)),
                                      ),
                                    ),
                                    onPressed: () async {
                                      final profiles = ref.read(profilesListProvider).value ?? [];
                                      final owner = profiles.firstWhere((p) => p.isOwner);
                                      await ref.read(syncRemoteDataSourceProvider).rejectConnection(
                                            parentAppCode: owner.appCode!,
                                            caretakerAppCode: request['caretaker_app_code'],
                                            caretakerUid: request['uid'],
                                          );
                                    },
                                    child: const Text('Reject'),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.white,
                                      foregroundColor: AppColors.accent,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      elevation: 0,
                                    ),
                                    onPressed: () async {
                                      final profiles = ref.read(profilesListProvider).value ?? [];
                                      final owner = profiles.firstWhere((p) => p.isOwner);

                                      // 1. Mark all Parent SQLite profile rows as dirty (is_dirty = 1)
                                      await ref.read(syncRepositoryProvider).markAllRowsDirty(owner.id);

                                      // 2. Update connection status to active in RTDB
                                      await ref.read(syncRemoteDataSourceProvider).acceptConnection(
                                            parentAppCode: owner.appCode!,
                                            caretakerAppCode: request['caretaker_app_code'],
                                            caretakerUid: request['uid'],
                                            parentName: owner.profileName,
                                          );

                                      // 3. Trigger immediate push sync to Caretaker
                                      await ref.read(syncRepositoryProvider).syncAll(owner.id);
                                    },
                                    child: const Text(
                                      'Accept',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

            const SizedBox(height: 12),
            
            // Time-Grouped Medication List or Empty State
            Expanded(
              child: dosesState.when(
                data: (doses) {
                  if (doses.isEmpty) {
                    return const EmptyState();
                  }

                  final groupedDoses = _groupDosesByTime(doses);
                  final sortedTimes = groupedDoses.keys.toList()..sort();

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    itemCount: sortedTimes.length,
                    itemBuilder: (context, index) {
                      final timeKey = sortedTimes[index];
                      final timeDoses = groupedDoses[timeKey]!;

                      return MedicationTimeGroup(
                        time24h: timeKey,
                        doses: timeDoses,
                        isReadOnly: isReadOnly,
                        onTake: (scheduleId) {
                          ref.read(homeDosesProvider.notifier).takeDose(scheduleId);
                        },
                        onSkip: (scheduleId) {
                          ref.read(homeDosesProvider.notifier).skipDose(scheduleId);
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.accent,
                  ),
                ),
                error: (error, stackTrace) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(
                      'Failed to load schedule: $error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.red),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      // FAB anchored bottom-right (hidden if read-only profile is active)
      floatingActionButton: isReadOnly
          ? null
          : FloatingActionButton(
              onPressed: () {
                context.push(AppConstants.routeAddMedication);
              },
              child: const Icon(Icons.add, size: 30),
            ),
    );
  }
}
