import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/med_type_config.dart';

class TypeSelector extends StatelessWidget {
  final MedTypeConfig config;
  final String selectedTypeId;
  final Function(String typeId) onTypeSelected;

  const TypeSelector({
    super.key,
    required this.config,
    required this.selectedTypeId,
    required this.onTypeSelected,
  });

  IconData _getIcon(String typeId) {
    switch (typeId.toLowerCase()) {
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
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: config.types.length,
      itemBuilder: (context, index) {
        final type = config.types[index];
        final isSelected = type.id.toLowerCase() == selectedTypeId.toLowerCase();

        return GestureDetector(
          onTap: () => onTypeSelected(type.id),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accent : AppColors.cardFill.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.accent : AppColors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getIcon(type.id),
                  size: 22,
                  color: isSelected ? AppColors.white : AppColors.accent,
                ),
                const SizedBox(height: 4),
                Text(
                  type.displayName,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelSmall.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? AppColors.white : AppColors.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
