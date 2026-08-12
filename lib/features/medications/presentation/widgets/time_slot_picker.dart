import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/date_time_utils.dart';

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
        const Text(
          'Dose Schedule Times',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
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
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.cardFill.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Time Slot ${index + 1}',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          displayTime,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.accent,
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
