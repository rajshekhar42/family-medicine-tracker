import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../../domain/entities/scheduled_dose.dart';

class MedicationCard extends StatelessWidget {
  final ScheduledDose dose;
  final VoidCallback onTake;
  final VoidCallback onSkip;
  final bool isReadOnly;

  const MedicationCard({
    super.key,
    required this.dose,
    required this.onTake,
    required this.onSkip,
    this.isReadOnly = false,
  });

  void _showEditStatusBottomSheet(BuildContext context) {
    final isTaken = dose.status == 'Taken';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.cardFill,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Update Log Status',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Do you want to update the status of "${dose.medicineName}"?',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              if (isTaken)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onSkip();
                  },
                  icon: const Icon(Icons.cancel, color: AppColors.white),
                  label: const Text('Mark as Skipped'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onTake();
                  },
                  icon: const Icon(Icons.check_circle, color: AppColors.white),
                  label: const Text('Mark as Taken'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getMedicineIcon(String type) {
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

  @override
  Widget build(BuildContext context) {
    final hasLogged = dose.status != null;
    final isTaken = dose.status == 'Taken';
    final isSkipped = dose.status == 'Skipped';

    final dosageStr = dose.dosage.trim();
    final quantityStr = dose.quantity.trim();
    final freqStr = _getDisplayFrequency(dose.frequency);
    final List<String> detailsParts = [];
    if (dosageStr.isNotEmpty) detailsParts.add(dosageStr);
    if (quantityStr.isNotEmpty) detailsParts.add(quantityStr);
    detailsParts.add(freqStr);
    final detailsText = detailsParts.join(' • ');

    Widget cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isTaken
            ? AppColors.green.withOpacity(0.08)
            : isSkipped
            ? AppColors.red.withOpacity(0.08)
            : AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isTaken
              ? AppColors.green.withOpacity(0.3)
              : isSkipped
              ? AppColors.red.withOpacity(0.3)
              : AppColors.cardFill.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left Action: Skip Button (Only visible if not logged yet and not read-only)
          if (!hasLogged && !isReadOnly)
            SkipButton(onPressed: onSkip)
          else if (hasLogged)
            // Indicator status icon
            Icon(
              isTaken ? Icons.check_circle : Icons.cancel,
              color: isTaken ? AppColors.green : AppColors.red,
              size: 28,
            )
          else
            // Read-only and not logged yet: show a neutral pending icon
            Icon(
              Icons.radio_button_unchecked_rounded,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
              size: 28,
            ),

          const SizedBox(width: 16),

          // Medication Name & Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dose.medicineName,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: hasLogged
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      _getMedicineIcon(dose.medicineType),
                      size: 14,
                      color: isTaken
                          ? AppColors.green
                          : isSkipped
                          ? AppColors.red
                          : AppColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        detailsText,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Right Action: Take Button (Only visible if not logged yet and not read-only)
          if (!hasLogged && !isReadOnly)
            TakeButton(onPressed: onTake)
          else if (isTaken && dose.takenAt != null)
            Text(
              'Taken at\n${DateTimeUtils.formatTime(dose.takenAt!)}',
              textAlign: TextAlign.right,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.green,
                fontWeight: FontWeight.w500,
              ),
            )
          else if (isSkipped)
            Text(
              'Skipped',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );

    // Apply swipe actions using Dismissible if not logged yet and not read-only
    if (!hasLogged && !isReadOnly) {
      return Dismissible(
        key: Key(dose.scheduleId + dose.date),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onTake();
            return false; // Handled programmatically
          } else if (direction == DismissDirection.endToStart) {
            onSkip();
            return false; // Handled programmatically
          }
          return false;
        },
        background: Container(
          decoration: BoxDecoration(
            color: AppColors.green.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
          child: const Icon(Icons.check, color: AppColors.green, size: 30),
        ),
        secondaryBackground: Container(
          decoration: BoxDecoration(
            color: AppColors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerRight,
          child: const Icon(Icons.close, color: AppColors.red, size: 30),
        ),
        child: cardContent,
      );
    }

    // Wrap with double-tap gesture detector to allow editing status if logged and not read-only
    if (hasLogged && !isReadOnly) {
      return GestureDetector(
        onDoubleTap: () => _showEditStatusBottomSheet(context),
        child: cardContent,
      );
    }

    return cardContent;
  }

  String _getDisplayFrequency(String frequency) {
    final lower = frequency.toLowerCase();
    if (lower.contains('day') || lower.contains('daily')) {
      return 'Daily';
    }
    if (lower.contains('week')) {
      return 'Weekly';
    }
    if (lower.contains('month')) {
      return 'Monthly';
    }
    return frequency;
  }
}

class SkipButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double size;

  const SkipButton({
    super.key,
    required this.onPressed,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Skip dose',
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      icon: SizedBox(
        width: size - 12,
        height: size - 12,
        child: CustomPaint(
          painter: CircleActionPainter(
            label: 'SKIP',
            circleColor: AppColors.red,
            textColor: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class TakeButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double size;

  const TakeButton({
    super.key,
    required this.onPressed,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Take dose',
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      icon: SizedBox(
        width: size - 12,
        height: size - 12,
        child: CustomPaint(
          painter: CircleActionPainter(
            label: 'TAKE',
            circleColor: AppColors.green,
            textColor: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class CircleActionPainter extends CustomPainter {
  final String label;
  final Color circleColor;
  final Color textColor;

  CircleActionPainter({
    required this.label,
    required this.circleColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    final scaleX = size.width / 64.0;
    final scaleY = size.height / 64.0;
    canvas.scale(scaleX, scaleY);

    // 1. Draw circular background (soft opacity matching the theme)
    final bgPaint = Paint()
      ..color = circleColor.withOpacity(0.1)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(32, 32), 32, bgPaint);

    // 2. Draw circle stroke
    final circlePaint = Paint()
      ..color = circleColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(const Offset(32, 32), 29.5, circlePaint);

    // 3. Draw text label centered inside the circle
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: 12.5,
          fontWeight: FontWeight.bold,
          fontFamily: 'Arial',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    final textOffset = Offset(
      32 - textPainter.width / 2,
      32 - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CircleActionPainter oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.circleColor != circleColor ||
        oldDelegate.textColor != textColor;
  }
}
