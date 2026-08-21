import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      
      // Color Scheme
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.white,
        secondary: AppColors.accent,
        onSecondary: AppColors.white,
        surface: AppColors.cardFill,
        onSurface: AppColors.textPrimary,
        error: AppColors.red,
        onError: AppColors.white,
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: AppColors.cardFill,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // FAB Theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),

      // Text Theme — apply light-mode colors to the base text styles
      textTheme: TextTheme(
        titleLarge: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimary),
        titleMedium: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
        titleSmall: AppTextStyles.titleSmall.copyWith(color: AppColors.textPrimary),
        bodyLarge: AppTextStyles.bodyLarge.copyWith(color: AppColors.textPrimary),
        bodyMedium: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
        bodySmall: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
        labelLarge: AppTextStyles.labelLarge.copyWith(color: AppColors.textPrimary),
        labelSmall: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary),
      ),

      // Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTextStyles.labelLarge.copyWith(color: AppColors.white),
        ),
      ),

      // Input Decoration Theme (for TextFields)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardFill.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        labelStyle: AppTextStyles.labelLarge,
      ),

      // Divider
      dividerColor: AppColors.textSecondary.withOpacity(0.2),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.accent;
          return AppColors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.accent.withOpacity(0.4);
          return AppColors.textSecondary.withOpacity(0.2);
        }),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: AppColors.darkPrimary,
      scaffoldBackgroundColor: AppColors.darkBackground,

      // Color Scheme
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkPrimary,
        onPrimary: AppColors.darkBackground,
        secondary: AppColors.darkAccent,
        onSecondary: AppColors.darkBackground,
        surface: AppColors.darkCardFill,
        onSurface: AppColors.darkTextPrimary,
        error: AppColors.darkRed,
        onError: AppColors.darkBackground,
        surfaceContainerHighest: AppColors.darkSurface,
      ),

      // Card Theme
      cardTheme: CardThemeData(
        color: AppColors.darkCardFill,
        elevation: 2,
        shadowColor: AppColors.darkShadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // FAB Theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.darkAccent,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 4,
        shape: CircleBorder(),
      ),

      // Text Theme — apply dark-mode colors to the base text styles
      textTheme: TextTheme(
        titleLarge: AppTextStyles.titleLarge.copyWith(color: AppColors.darkTextPrimary),
        titleMedium: AppTextStyles.titleMedium.copyWith(color: AppColors.darkTextPrimary),
        titleSmall: AppTextStyles.titleSmall.copyWith(color: AppColors.darkTextPrimary),
        bodyLarge: AppTextStyles.bodyLarge.copyWith(color: AppColors.darkTextPrimary),
        bodyMedium: AppTextStyles.bodyMedium.copyWith(color: AppColors.darkTextPrimary),
        bodySmall: AppTextStyles.bodySmall.copyWith(color: AppColors.darkTextSecondary),
        labelLarge: AppTextStyles.labelLarge.copyWith(color: AppColors.darkTextPrimary),
        labelSmall: AppTextStyles.labelSmall.copyWith(color: AppColors.darkTextSecondary),
      ),

      // Button Theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkPrimary,
          foregroundColor: AppColors.darkBackground,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: AppTextStyles.labelLarge.copyWith(color: AppColors.darkBackground),
        ),
      ),

      // Input Decoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface.withOpacity(0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.darkPrimary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.darkTextSecondary),
        labelStyle: AppTextStyles.labelLarge.copyWith(color: AppColors.darkTextPrimary),
      ),

      // AppBar Theme
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.darkTextPrimary,
        elevation: 0,
      ),

      // Divider
      dividerColor: AppColors.darkTextSecondary.withOpacity(0.2),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.darkPrimary;
          return AppColors.darkTextSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.darkPrimary.withOpacity(0.4);
          return AppColors.darkTextSecondary.withOpacity(0.2);
        }),
      ),

      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkCardFill,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkCardFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Dropdown
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
