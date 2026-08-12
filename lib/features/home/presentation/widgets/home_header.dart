import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../profiles/presentation/providers/active_profile_provider.dart';
import '../providers/home_provider.dart';
import 'full_calendar_dialog.dart';

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  String _getHeaderTitle(DateTime selectedDate) {
    final now = DateTime.now().toUtc();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

    final difference = selected.difference(today).inDays;

    if (difference == 0) {
      return 'Today';
    } else if (difference == 1) {
      return 'Tomorrow';
    } else if (difference == -1) {
      return 'Yesterday';
    } else {
      return DateFormat('d MMMM').format(selectedDate);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeProfile = ref.watch(activeProfileProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final title = _getHeaderTitle(selectedDate);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: GestureDetector(
              onTap: () {
                final scaffoldState = Scaffold.of(context);
                if (scaffoldState.isDrawerOpen) {
                  scaffoldState.closeDrawer();
                } else {
                  scaffoldState.openDrawer();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.cardFill,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  activeProfile?.profileName ?? 'User',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.accent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Dynamic Header Title in center top
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 32.0),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleLarge.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 22,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Calendar Icon button on top-right
          GestureDetector(
            onTap: () async {
              final pickedDate = await showDialog<DateTime>(
                context: context,
                builder: (context) => const FullCalendarDialog(),
              );
              if (pickedDate != null) {
                ref.read(selectedDateProvider.notifier).state = pickedDate;
              }
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardFill.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_today_outlined,
                size: 20,
                color: AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
