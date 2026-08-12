import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';
import '../services/reminder_scheduler.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsStateProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.transparent,
        centerTitle: true,
      ),
      body: settingsState.when(
        data: (settings) {
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                // Reminders Section Header
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('Notifications', style: AppTextStyles.titleSmall),
                ),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Dose Reminders', style: AppTextStyles.labelLarge),
                        subtitle: const Text('Get notified exactly when a medication is scheduled.'),
                        value: settings.remindersEnabled,
                        activeColor: AppColors.accent,
                        onChanged: (val) {
                          ref.read(settingsStateProvider.notifier).updateReminders(val);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SwitchListTile(
                        title: const Text('Reminder Sound', style: AppTextStyles.labelLarge),
                        subtitle: const Text('Play sound notifications for dose alerts.'),
                        value: settings.soundEnabled,
                        activeColor: AppColors.accent,
                        // Only allow sound toggle if reminders are turned on
                        onChanged: settings.remindersEnabled
                            ? (val) {
                                ref.read(settingsStateProvider.notifier).updateSound(val);
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Adherence Rules Section
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('Adherence Rules', style: AppTextStyles.titleSmall),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Missed Dose Grace Period',
                          style: AppTextStyles.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Unlogged doses are marked "skipped" automatically after this time expires.',
                          style: AppTextStyles.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          value: settings.gracePeriodMinutes,
                          decoration: const InputDecoration(
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          items: const [
                            DropdownMenuItem(value: 15, child: Text('15 Minutes')),
                            DropdownMenuItem(value: 30, child: Text('30 Minutes')),
                            DropdownMenuItem(value: 45, child: Text('45 Minutes')),
                            DropdownMenuItem(value: 60, child: Text('60 Minutes')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              ref.read(settingsStateProvider.notifier).updateGracePeriod(val);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Info Section
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('About App', style: AppTextStyles.titleSmall),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('App Version', style: AppTextStyles.bodyMedium),
                            Text('2.0.0', style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('Developer', style: AppTextStyles.bodyMedium),
                            Text('Google DeepMind', style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Diagnostics Section
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('Notification Diagnostics', style: AppTextStyles.titleSmall),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Active Timezone', style: AppTextStyles.labelLarge),
                            Text(
                              tz.local.name,
                              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('App Local Time', style: AppTextStyles.labelLarge),
                            Text(
                              DateTime.now().toString().split('.').first,
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Exact Alarms Granted', style: AppTextStyles.labelLarge),
                            FutureBuilder<bool>(
                              future: NotificationService.instance.checkExactAlarmPermission(),
                              builder: (context, snapshot) {
                                final granted = snapshot.data ?? false;
                                return Text(
                                  granted ? 'TRUE' : 'FALSE',
                                  style: TextStyle(
                                    color: granted ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        const Text('Pending Scheduled Alarms:', style: AppTextStyles.labelLarge),
                        const SizedBox(height: 8),
                        FutureBuilder<List<PendingNotificationRequest>>(
                          future: NotificationService.instance.getPendingReminders(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (snapshot.hasError) {
                              return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red));
                            }
                            final list = snapshot.data ?? [];
                            if (list.isEmpty) {
                              return const Text(
                                'No pending scheduled notifications in OS.',
                                style: TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                              );
                            }
                            return Column(
                              children: list.map((req) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.alarm, color: AppColors.accent),
                                  title: Text(req.title ?? 'Dose Reminder', style: AppTextStyles.bodyMedium),
                                  subtitle: Text('${req.body}\nID: ${req.id}', style: AppTextStyles.bodySmall),
                                );
                              }).toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reschedule'),
                                onPressed: () async {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Rescheduling all reminders...')),
                                  );
                                  await ref.read(reminderSchedulerProvider).rescheduleAll();
                                  if (context.mounted) {
                                    (context as Element).markNeedsBuild();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.notification_important),
                                label: const Text('Test Alert (5s)'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent.withOpacity(0.2),
                                  foregroundColor: AppColors.accent,
                                ),
                                onPressed: () async {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Scheduling test notification in 5s...')),
                                  );
                                  await NotificationService.instance.scheduleTestNotification();
                                  if (context.mounted) {
                                    (context as Element).markNeedsBuild();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
