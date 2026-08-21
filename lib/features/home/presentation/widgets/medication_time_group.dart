import 'package:flutter/material.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../../domain/entities/scheduled_dose.dart';
import 'medication_card.dart';

class MedicationTimeGroup extends StatelessWidget {
  final String time24h;
  final List<ScheduledDose> doses;
  final Function(String scheduleId) onTake;
  final Function(String scheduleId) onSkip;
  final bool isReadOnly;

  const MedicationTimeGroup({
    super.key,
    required this.time24h,
    required this.doses,
    required this.onTake,
    required this.onSkip,
    this.isReadOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayTime = DateTimeUtils.formatTimeString(time24h);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time Slot Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
            child: Row(
              children: [
                Icon(
                  Icons.access_time_filled_rounded,
                  size: 16,
                  color: colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  displayTime,
                  style: textTheme.labelLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Cards under this time slot
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: doses.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final dose = doses[index];
              return MedicationCard(
                dose: dose,
                onTake: () => onTake(dose.scheduleId),
                onSkip: () => onSkip(dose.scheduleId),
                isReadOnly: isReadOnly,
              );
            },
          ),
        ],
      ),
    );
  }
}
