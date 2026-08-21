import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/utils/date_time_utils.dart';
import '../../domain/entities/scheduled_dose.dart';
import '../providers/swipe_hint_provider.dart';
import 'swipe_tutorial_overlay.dart';

class MedicationCard extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<MedicationCard> createState() => _MedicationCardState();
}

class _MedicationCardState extends ConsumerState<MedicationCard> {
  bool _showingTutorial = false;

  Future<void> _handleTake() async {
    final swipeHint = ref.read(swipeHintProvider.notifier);

    // Check if we should show the tutorial BEFORE firing the action,
    // so the card hasn't transitioned to "logged" state yet.
    final showHint = await swipeHint.shouldShowHint();

    // Fire the action
    widget.onTake();

    // Show the tutorial overlay if appropriate
    if (showHint && mounted) {
      setState(() => _showingTutorial = true);
      swipeHint.recordHintShown();
    }
  }

  Future<void> _handleSkip() async {
    final swipeHint = ref.read(swipeHintProvider.notifier);

    // Check if we should show the tutorial BEFORE firing the action
    final showHint = await swipeHint.shouldShowHint();

    // Fire the action
    widget.onSkip();

    // Show the tutorial overlay if appropriate
    if (showHint && mounted) {
      setState(() => _showingTutorial = true);
      swipeHint.recordHintShown();
    }
  }

  void _showEditStatusBottomSheet(BuildContext context) {
    final isTaken = widget.dose.status == 'Taken';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
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
                    color: colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Update Log Status',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Do you want to update the status of "${widget.dose.medicineName}"?',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 24),
              if (isTaken)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onSkip();
                  },
                  icon: Icon(Icons.cancel, color: colorScheme.onError),
                  label: const Text('Mark as Skipped'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
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
                    widget.onTake();
                  },
                  icon: const Icon(Icons.check_circle, color: Colors.white),
                  label: const Text('Mark as Taken'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
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
                  foregroundColor: colorScheme.secondary,
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
    final dose = widget.dose;
    final hasLogged = dose.status != null;
    final isTaken = dose.status == 'Taken';
    final isSkipped = dose.status == 'Skipped';

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use theme-aware green/red
    final greenColor = isDark ? const Color(0xFF66BB6A) : const Color(0xFF81C784);
    final redColor = isDark ? const Color(0xFFEF5350) : const Color(0xFFE57373);
    final cardBg = isDark ? colorScheme.surface : Colors.white;

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
            ? greenColor.withOpacity(0.08)
            : isSkipped
            ? redColor.withOpacity(0.08)
            : cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isTaken
              ? greenColor.withOpacity(0.3)
              : isSkipped
              ? redColor.withOpacity(0.3)
              : colorScheme.onSurface.withOpacity(0.08),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left Action: Skip Button (Only visible if not logged yet and not read-only)
          if (!hasLogged && !widget.isReadOnly)
            SkipButton(onPressed: _handleSkip, circleColor: redColor, textColor: colorScheme.onSurface)
          else if (hasLogged)
            // Indicator status icon
            Icon(
              isTaken ? Icons.check_circle : Icons.cancel,
              color: isTaken ? greenColor : redColor,
              size: 28,
            )
          else
            // Read-only and not logged yet: show a neutral pending icon
            Icon(
              Icons.radio_button_unchecked_rounded,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
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
                  style: textTheme.labelLarge?.copyWith(
                    color: hasLogged
                        ? colorScheme.onSurface.withOpacity(0.5)
                        : colorScheme.onSurface,
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
                          ? greenColor
                          : isSkipped
                          ? redColor
                          : colorScheme.secondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        detailsText,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Right Action: Take Button (Only visible if not logged yet and not read-only)
          if (!hasLogged && !widget.isReadOnly)
            TakeButton(onPressed: _handleTake, circleColor: greenColor, textColor: colorScheme.onSurface)
          else if (isTaken && dose.takenAt != null)
            Text(
              'Taken at\n${DateTimeUtils.formatTime(dose.takenAt!)}',
              textAlign: TextAlign.right,
              style: textTheme.bodySmall?.copyWith(
                color: greenColor,
                fontWeight: FontWeight.w500,
              ),
            )
          else if (isSkipped)
            Text(
              'Skipped',
              style: textTheme.bodySmall?.copyWith(
                color: redColor,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );

    // Apply swipe actions using Dismissible if not logged yet and not read-only
    if (!hasLogged && !widget.isReadOnly) {
      cardContent = Dismissible(
        key: Key(dose.scheduleId + dose.date),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await _handleTake();
            return false; // Handled programmatically
          } else if (direction == DismissDirection.endToStart) {
            await _handleSkip();
            return false; // Handled programmatically
          }
          return false;
        },
        background: Container(
          decoration: BoxDecoration(
            color: greenColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
          child: Icon(Icons.check, color: greenColor, size: 30),
        ),
        secondaryBackground: Container(
          decoration: BoxDecoration(
            color: redColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerRight,
          child: Icon(Icons.close, color: redColor, size: 30),
        ),
        child: cardContent,
      );
    }

    // Wrap with double-tap gesture detector to allow editing status if logged and not read-only
    if (hasLogged && !widget.isReadOnly) {
      cardContent = GestureDetector(
        onDoubleTap: () => _showEditStatusBottomSheet(context),
        child: cardContent,
      );
    }

    // Wrap in a Stack to overlay the tutorial animation when needed
    if (_showingTutorial) {
      return Stack(
        children: [
          cardContent,
          Positioned.fill(
            child: SwipeTutorialOverlay(
              onDismissed: () {
                if (mounted) {
                  setState(() => _showingTutorial = false);
                }
              },
            ),
          ),
        ],
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
  final Color circleColor;
  final Color textColor;

  const SkipButton({
    super.key,
    required this.onPressed,
    required this.circleColor,
    required this.textColor,
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
            circleColor: circleColor,
            textColor: textColor,
          ),
        ),
      ),
    );
  }
}

class TakeButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double size;
  final Color circleColor;
  final Color textColor;

  const TakeButton({
    super.key,
    required this.onPressed,
    required this.circleColor,
    required this.textColor,
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
            circleColor: circleColor,
            textColor: textColor,
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
