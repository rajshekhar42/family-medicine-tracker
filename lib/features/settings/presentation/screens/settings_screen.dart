import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;
import '../providers/settings_provider.dart';
import '../services/notification_service.dart';
import '../services/reminder_scheduler.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsStateProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        centerTitle: true,
      ),
      body: settingsState.when(
        data: (settings) {
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24.0),
              children: [
                // ── Appearance Section ──
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('Appearance', style: theme.textTheme.titleSmall),
                ),
                Card(
                  child: SwitchListTile(
                    title: Text('Dark Mode', style: theme.textTheme.labelLarge),
                    subtitle: const Text('Switch to a rich dark color scheme.'),
                    value: settings.darkModeEnabled,
                    secondary: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) =>
                          RotationTransition(turns: animation, child: child),
                      child: Icon(
                        settings.darkModeEnabled ? Icons.dark_mode : Icons.light_mode,
                        key: ValueKey(settings.darkModeEnabled),
                        color: colorScheme.secondary,
                      ),
                    ),
                    onChanged: (val) {
                      ref.read(settingsStateProvider.notifier).updateDarkMode(val);
                    },
                  ),
                ),
                const SizedBox(height: 28),

                // ── Notifications Section ──
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('Notifications', style: theme.textTheme.titleSmall),
                ),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: Text('Dose Reminders', style: theme.textTheme.labelLarge),
                        subtitle: const Text('Get notified exactly when a medication is scheduled.'),
                        value: settings.remindersEnabled,
                        onChanged: (val) {
                          ref.read(settingsStateProvider.notifier).updateReminders(val);
                        },
                      ),
                      Divider(height: 1, indent: 16, endIndent: 16, color: theme.dividerColor),
                      SwitchListTile(
                        title: Text('Reminder Sound', style: theme.textTheme.labelLarge),
                        subtitle: const Text('Play sound notifications for dose alerts.'),
                        value: settings.soundEnabled,
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

                // ── Adherence Rules Section ──
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('Adherence Rules', style: theme.textTheme.titleSmall),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Missed Dose Grace Period',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Unlogged doses are marked "skipped" automatically after this time expires.',
                          style: theme.textTheme.bodySmall,
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

                // ── About Section ──
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('About App', style: theme.textTheme.titleSmall),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('App Version', style: theme.textTheme.bodyMedium),
                            Text('2.0.0', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6))),
                          ],
                        ),
                        Divider(height: 24, color: theme.dividerColor),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Developer', style: theme.textTheme.bodyMedium),
                            Text('Google DeepMind', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Diagnostics Section ──
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('Notification Diagnostics', style: theme.textTheme.titleSmall),
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
                            Text('Active Timezone', style: theme.textTheme.labelLarge),
                            Text(
                              tz.local.name,
                              style: TextStyle(color: colorScheme.secondary, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Divider(height: 24, color: theme.dividerColor),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('App Local Time', style: theme.textTheme.labelLarge),
                            Text(
                              DateTime.now().toString().split('.').first,
                              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
                            ),
                          ],
                        ),
                        Divider(height: 24, color: theme.dividerColor),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Exact Alarms Granted', style: theme.textTheme.labelLarge),
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
                        Divider(height: 24, color: theme.dividerColor),
                        Text('Pending Scheduled Alarms:', style: theme.textTheme.labelLarge),
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
                              return Text(
                                'No pending scheduled notifications in OS.',
                                style: TextStyle(
                                  color: colorScheme.onSurface.withOpacity(0.5),
                                  fontStyle: FontStyle.italic,
                                ),
                              );
                            }
                            return Column(
                              children: list.map((req) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.alarm, color: colorScheme.secondary),
                                  title: Text(req.title ?? 'Dose Reminder', style: theme.textTheme.bodyMedium),
                                  subtitle: Text('${req.body}\nID: ${req.id}', style: theme.textTheme.bodySmall),
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
                                  backgroundColor: colorScheme.secondary.withOpacity(0.2),
                                  foregroundColor: colorScheme.secondary,
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
