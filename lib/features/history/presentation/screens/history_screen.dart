import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../providers/history_provider.dart';
import '../../domain/entities/adherence_report.dart';
import '../../../home/domain/entities/scheduled_dose.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeProfile = ref.watch(activeProfileProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Adherence History'),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.cardFill,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  activeProfile?.profileName ?? 'User',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.transparent,
          centerTitle: true,
          bottom: const TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            tabs: [
              Tab(text: 'By Date'),
              Tab(text: 'By Medicine'),
            ],
          ),
        ),
        body: const TabBarView(
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
  const _ByDateTab();

  void _selectDate(BuildContext context, WidgetRef ref, DateTime initialDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.accent,
              onPrimary: AppColors.white,
              onSurface: AppColors.textPrimary,
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
                icon: const Icon(Icons.chevron_left, color: AppColors.accent),
                onPressed: () {
                  ref.read(historySelectedDateProvider.notifier).state =
                      selectedDate.subtract(const Duration(days: 1));
                },
              ),
              GestureDetector(
                onTap: () => _selectDate(context, ref, selectedDate),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.cardFill),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: AppColors.accent),
                onPressed: () {
                  ref.read(historySelectedDateProvider.notifier).state =
                      selectedDate.add(const Duration(days: 1));
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
                return const Center(
                  child: Text(
                    'No medications scheduled for this date.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: doses.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final dose = doses[index];
                  return _buildDoseTile(dose);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
          ),
        ),
      ],
    );
  }

  Widget _buildDoseTile(ScheduledDose dose) {
    final bool hasLogged = dose.status != null;
    final bool isTaken = dose.status == 'Taken';
    final bool isSkipped = dose.status == 'Skipped';

    Color statusColor = AppColors.textSecondary;
    IconData statusIcon = Icons.help_outline;
    String statusText = 'Not logged';

    if (isTaken) {
      statusColor = AppColors.green;
      statusIcon = Icons.check_circle;
      statusText = dose.takenAt != null
          ? 'Taken at ${DateTimeUtils.formatTime(dose.takenAt!)}'
          : 'Taken';
    } else if (isSkipped) {
      statusColor = AppColors.red;
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
          style: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Scheduled at ${dose.scheduledTime} • ${dose.dosage}',
          style: AppTextStyles.bodySmall,
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
  const _ByMedicineTab();

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

  Color _getAdherenceColor(double rate) {
    if (rate >= 90.0) return AppColors.green;
    if (rate >= 70.0) return Colors.orange;
    return AppColors.red;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsState = ref.watch(adherenceReportsProvider);

    return reportsState.when(
      data: (reports) {
        if (reports.isEmpty) {
          return const Center(
            child: Text(
              'No medications added yet.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(20.0),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final medAdherence = reports[index];
            final color = _getAdherenceColor(medAdherence.adherenceRate);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                leading: Icon(_getIcon(medAdherence.type), color: AppColors.accent, size: 28),
                title: Text(
                  medAdherence.medicineName,
                  style: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${medAdherence.logs.length} logs recorded',
                  style: AppTextStyles.bodySmall,
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${medAdherence.adherenceRate.toStringAsFixed(0)}% Adherence',
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
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'No logs recorded for this medication yet.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                            color: isTaken ? AppColors.green : AppColors.red,
                            size: 20,
                          ),
                          title: Text(
                            '$formattedDate at ${log.time}',
                            style: AppTextStyles.bodyMedium,
                          ),
                          trailing: Text(
                            log.status,
                            style: TextStyle(
                              color: isTaken ? AppColors.green : AppColors.red,
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
