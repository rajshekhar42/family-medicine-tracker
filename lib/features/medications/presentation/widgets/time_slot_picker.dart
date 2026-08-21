import 'package:flutter/material.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../../../../core/theme/app_colors.dart';

class TimeSlotPicker extends StatelessWidget {
  final int slotCount;
  final List<String> selectedTimes; // Formatted as 'HH:mm'
  final Function(List<String> times) onTimesChanged;

  const TimeSlotPicker({
    super.key,
    required this.slotCount,
    required this.selectedTimes,
    required this.onTimesChanged,
  });

  Future<void> _selectTime(BuildContext context, int index) async {
    // Parse current time in HH:mm
    TimeOfDay initialTime = const TimeOfDay(hour: 8, minute: 0);
    if (index < selectedTimes.length) {
      final parts = selectedTimes[index].split(':');
      initialTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      final formattedHour = picked.hour.toString().padLeft(2, '0');
      final formattedMinute = picked.minute.toString().padLeft(2, '0');
      final timeStr = '$formattedHour:$formattedMinute';

      final updatedTimes = List<String>.from(selectedTimes);
      
      // Ensure the array has enough items
      while (updatedTimes.length < slotCount) {
        updatedTimes.add('08:00');
      }

      updatedTimes[index] = timeStr;
      onTimesChanged(updatedTimes.sublist(0, slotCount));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? AppColors.darkSurface.withValues(alpha: 0.6)
        : AppColors.cardFill.withValues(alpha: 0.7);

    // Keep internal selectedTimes sized exactly to slotCount
    final times = List<String>.generate(slotCount, (i) {
      if (i < selectedTimes.length) {
        return selectedTimes[i];
      }
      // Stagger defaults: Slot 1 -> 08:00, Slot 2 -> 14:00, Slot 3 -> 20:00, etc.
      if (i == 1) return '14:00';
      if (i == 2) return '20:00';
      return '08:00';
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dose Schedule Times',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: slotCount,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final timeStr = times[index];
            final displayTime = DateTimeUtils.formatTimeString(timeStr);

            return InkWell(
              onTap: () => _selectTime(context, index),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Time Slot ${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          displayTime,
                          style: TextStyle(
                            color: colorScheme.secondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.access_time_rounded,
                          size: 18,
                          color: colorScheme.secondary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
