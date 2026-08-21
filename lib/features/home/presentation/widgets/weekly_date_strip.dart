import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/home_provider.dart';

class WeeklyDateStrip extends ConsumerStatefulWidget {
  const WeeklyDateStrip({super.key});

  @override
  ConsumerState<WeeklyDateStrip> createState() => _WeeklyDateStripState();
}

class _WeeklyDateStripState extends ConsumerState<WeeklyDateStrip> {
  late final PageController _pageController;
  late final DateTime _anchorSunday;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _anchorSunday = today.subtract(Duration(days: today.weekday % 7));

    final initialDate = ref.read(selectedDateProvider);
    final initialPage = _getPageIndexForDate(initialDate);
    _pageController = PageController(initialPage: initialPage);
  }

  int _getPageIndexForDate(DateTime date) {
    final startOfTargetWeek = DateTime(date.year, date.month, date.day).subtract(
      Duration(days: DateTime(date.year, date.month, date.day).weekday % 7),
    );
    final differenceInDays = startOfTargetWeek.difference(_anchorSunday).inDays;
    final differenceInWeeks = (differenceInDays / 7).round();
    return 10000 + differenceInWeeks;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int pageIndex) {
    final targetSunday = _anchorSunday.add(Duration(days: (pageIndex - 10000) * 7));
    
    // Check if real-world today's date is in this week
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    DateTime selectedTarget = targetSunday.add(const Duration(days: 3)); // Default to Wednesday
    for (int i = 0; i < 7; i++) {
      final day = targetSunday.add(Duration(days: i));
      if (day.year == today.year && day.month == today.month && day.day == today.day) {
        selectedTarget = today;
        break;
      }
    }

    final currentSelected = ref.read(selectedDateProvider);
    final currentSelectedPage = _getPageIndexForDate(currentSelected);
    if (currentSelectedPage != pageIndex) {
      ref.read(selectedDateProvider.notifier).state = selectedTarget;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);

    // Listen to outer date changes (e.g. from calendar dialog) to animate PageView
    ref.listen<DateTime>(selectedDateProvider, (previous, next) {
      if (next != null) {
        final targetPage = _getPageIndexForDate(next);
        if (_pageController.hasClients && _pageController.page?.round() != targetPage) {
          _pageController.animateToPage(
            targetPage,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }
    });

    return SizedBox(
      height: 85,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          final targetSunday = _anchorSunday.add(Duration(days: (index - 10000) * 7));
          return _buildWeekRow(targetSunday, selectedDate);
        },
      ),
    );
  }

  Widget _buildWeekRow(DateTime targetSunday, DateTime selectedDate) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(7, (index) {
          final day = targetSunday.add(Duration(days: index));
          final isSelected = day.year == selectedDate.year &&
              day.month == selectedDate.month &&
              day.day == selectedDate.day;

          final dayName = DateFormat('E').format(day).toUpperCase(); // SUN, MON...
          final dayNum = DateFormat('d').format(day);

          return GestureDetector(
            onTap: () {
              ref.read(selectedDateProvider.notifier).state = day;
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Day abbreviation label
                Text(
                  dayName,
                  style: textTheme.bodySmall?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? colorScheme.secondary : colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                // Highlight circle container
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected ? colorScheme.secondary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    dayNum,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? colorScheme.onSecondary : colorScheme.onSurface,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
