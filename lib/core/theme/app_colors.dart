import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Light theme colors ──
  static const Color primary = Color(0xFFC9A0DC); // Soft lavender/lilac
  static const Color background = Color(0xFFFDF0F5); // Light pink/blush
  static const Color cardFill = Color(0xFFE8D5F5); // Pale lavender card fill
  static const Color accent = Color(0xFF9B6DB0); // Medium purple
  static const Color textPrimary = Color(0xFF2D2D2D); // Dark charcoal
  static const Color textSecondary = Color(0xFF8E8E93); // Muted grey
  
  static const Color white = Colors.white;
  static const Color shadow = Color(0x0A000000); // 4% opacity black for subtle shadows
  static const Color transparent = Colors.transparent;

  static const Color green = Color(0xFF81C784); // Soft green for taken/adherence
  static const Color red = Color(0xFFE57373); // Soft red for skipped

  // ── Dark theme colors ──
  static const Color darkPrimary = Color(0xFFBB86FC); // Vibrant purple
  static const Color darkBackground = Color(0xFF121218); // Deep charcoal
  static const Color darkCardFill = Color(0xFF1E1E2C); // Dark navy-purple
  static const Color darkAccent = Color(0xFFCF6679); // Muted rose
  static const Color darkTextPrimary = Color(0xFFE8E0F0); // Lavender white
  static const Color darkTextSecondary = Color(0xFF9E97A8); // Soft mauve

  static const Color darkSurface = Color(0xFF252536); // Elevated surface
  static const Color darkShadow = Color(0x33000000); // 20% opacity black

  static const Color darkGreen = Color(0xFF66BB6A); // Slightly brighter green
  static const Color darkRed = Color(0xFFEF5350); // Slightly brighter red
}
