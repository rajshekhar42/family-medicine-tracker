import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../providers/history_provider.dart';
import '../../domain/entities/adherence_report.dart';
import '../../../home/domain/entities/scheduled_dose.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';

class HistoryScreen extends ConsumerWidget {
  HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final activeProfile = ref.watch(activeProfileProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Adherence History'),
          backgroundColor: Colors.transparent,
          centerTitle: false,
          actions: [
            if (activeProfile != null)
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        activeProfile.profileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
          bottom: TabBar(
            indicatorColor: colorScheme.secondary,
            labelColor: colorScheme.secondary,
            unselectedLabelColor: colorScheme.onSurface.withValues(alpha: 0.5),
            tabs: const [
              Tab(text: 'By Date'),
              Tab(text: 'By Medicine'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ByDateTab(),
            _ByMedicineTab(),
          ],
        ),
      ),
    );
  }
}

class _ByDateTab extends ConsumerWidget {
  _ByDateTab();

  void _selectDate(BuildContext context, WidgetRef ref, DateTime initialDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now().add(Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.secondary,
              onPrimary: Colors.white,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != initialDate) {
      ref.read(historySelectedDateProvider.notifier).state = picked;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selectedDate = ref.watch(historySelectedDateProvider);
    final dosesFuture = ref.watch(historySelectedDateDosesProvider);
    final dateStr = DateFormat('EEEE, MMM d').format(selectedDate);

    return Column(
      children: [
        // Date Selector Control Bar
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left, color: colorScheme.secondary),
                onPressed: () {
                  ref.read(historySelectedDateProvider.notifier).state =
                      selectedDate.subtract(Duration(days: 1));
                },
              ),
              GestureDetector(
                onTap: () => _selectDate(context, ref, selectedDate),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colorScheme.surface),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: colorScheme.secondary),
                      SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right, color: colorScheme.secondary),
                onPressed: () {
                  ref.read(historySelectedDateProvider.notifier).state =
                      selectedDate.add(Duration(days: 1));
                },
              ),
            ],
          ),
        ),

        // List of doses
        Expanded(
          child: dosesFuture.when(
            data: (doses) {
              if (doses.isEmpty) {
                return Center(
                  child: Text(
                    'No medications scheduled for this date.',
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: doses.length,
                separatorBuilder: (context, index) => SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final dose = doses[index];
                  return _buildDoseTile(context, dose);
                },
              );
            },
            loading: () => Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }

  Widget _buildDoseTile(BuildContext context, ScheduledDose dose) {
    final bool hasLogged = dose.status != null;
    final bool isTaken = dose.status == 'Taken';
    final bool isSkipped = dose.status == 'Skipped';

    Color statusColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.5);
    IconData statusIcon = Icons.help_outline;
    String statusText = 'Not logged';

    if (isTaken) {
      statusColor = (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF66BB6A) : const Color(0xFF81C784));
      statusIcon = Icons.check_circle;
      statusText = dose.takenAt != null
          ? 'Taken at ${DateTimeUtils.formatTime(dose.takenAt!)}'
          : 'Taken';
    } else if (isSkipped) {
      statusColor = Theme.of(context).colorScheme.error;
      statusIcon = Icons.cancel;
      statusText = 'Skipped';
    }

    return Card(
      child: ListTile(
        leading: Icon(
          isTaken
              ? Icons.check_circle
              : isSkipped
                  ? Icons.cancel
                  : Icons.radio_button_unchecked,
          color: statusColor,
          size: 28,
        ),
        title: Text(
          dose.medicineName,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Scheduled at ${dose.scheduledTime} • ${dose.dosage}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              fontSize: 11,
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _ByMedicineTab extends ConsumerWidget {
  _ByMedicineTab();

  IconData _getIcon(String type) {
    switch (type.toLowerCase()) {
      case 'tablet':
        return Icons.circle_outlined;
      case 'capsule':
        return Icons.medical_services_outlined;
      case 'syrup':
        return Icons.wine_bar_outlined ?? Icons.local_activity_outlined;
      case 'powder':
        return Icons.grain_outlined;
      case 'cream':
        return Icons.color_lens_outlined;
      case 'injection':
        return Icons.vaccines_outlined;
      default:
        return Icons.medication_outlined;
    }
  }

  Color _getAdherenceColor(BuildContext context, double rate) {
    if (rate >= 90.0) return (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF66BB6A) : const Color(0xFF81C784));
    if (rate >= 70.0) return Colors.orange;
    return Theme.of(context).colorScheme.error;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final greenColor = isDark ? const Color(0xFF66BB6A) : const Color(0xFF81C784);
    final reportsState = ref.watch(adherenceReportsProvider);

    return reportsState.when(
      data: (reports) {
        if (reports.isEmpty) {
          return Center(
            child: Text(
              'No medications added yet.',
              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20.0),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final medAdherence = reports[index];
            final hasLogs = medAdherence.logs.isNotEmpty && medAdherence.adherenceRate != null;
            final color = hasLogs
                ? _getAdherenceColor(context, medAdherence.adherenceRate!)
                : colorScheme.onSurface.withValues(alpha: 0.5);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: Icon(_getIcon(medAdherence.type), color: colorScheme.secondary, size: 28),
                title: Text(
                  medAdherence.medicineName,
                  style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${medAdherence.logs.length} logs recorded',
                  style: textTheme.bodySmall,
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    hasLogs
                        ? '${medAdherence.adherenceRate!.toStringAsFixed(0)}% Adherence'
                        : 'Not logged',
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                children: [
                  const Divider(height: 1),
                  if (medAdherence.logs.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No logs recorded for this medication yet.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withOpacity(0.5)),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: medAdherence.logs.length,
                      itemBuilder: (context, logIndex) {
                        final log = medAdherence.logs[logIndex];
                        final isTaken = log.status == 'Taken';
                        
                        // Parse date for clean display: yyyy-MM-dd -> EEE, MMM d
                        String formattedDate = log.date;
                        try {
                          final parsed = DateFormat('yyyy-MM-dd').parse(log.date);
                          formattedDate = DateFormat('EEE, MMM d').format(parsed);
                        } catch (_) {}

                        return ListTile(
                          dense: true,
                          leading: Icon(
                            isTaken ? Icons.check_circle_outline : Icons.cancel_outlined,
                            color: isTaken ? greenColor : colorScheme.error,
                            size: 20,
                          ),
                          title: Text(
                            '$formattedDate at ${log.time}',
                            style: textTheme.bodyMedium,
                          ),
                          trailing: Text(
                            log.status,
                            style: TextStyle(
                              color: isTaken ? greenColor : colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}
