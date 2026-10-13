import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary
  static const primary = Color.fromARGB(255, 103, 59, 246);
  static const primaryLight = Color.fromARGB(255, 96, 165, 250);
  static const primaryDark = Color.fromARGB(255, 37, 99, 235);

  /// Brand purple lifted for text and icons on dark backgrounds, where
  /// [primary] is too dark to read.
  static const primaryOnDark = Color(0xFFB9A8FF);

  // Accent - soft green from screenshots
  static const accent = Color(0xFFD4EDDA);
  static const accentDark = Color(0xFF2D5A3D);

  // Neutrals - Light
  static const backgroundLight = Color(0xFFF8F7FC);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const cardLight = Color(0xFFF5F5F7);
  static const textPrimaryLight = Color(0xFF1A1A2E);
  static const textSecondaryLight = Color(0xFF6B7280);
  static const borderLight = Color(0xFFE5E7EB);

  // Neutrals - Dark
  static const backgroundDark = Color(0xFF0F0F1A);
  static const surfaceDark = Color(0xFF1A1A2E);
  static const cardDark = Color(0xFF252540);
  static const textPrimaryDark = Color(0xFFF9FAFB);
  static const textSecondaryDark = Color(0xFF9CA3AF);
  static const borderDark = Color(0xFF374151);

  // Glass
  static const glassLight = Color(0x80FFFFFF);
  static const glassDark = Color(0x40FFFFFF);
  static const glassBorderLight = Color(0x30FFFFFF);
  static const glassBorderDark = Color(0x15FFFFFF);

  // Gradient backgrounds
  static const gradientLightStart = Color(0xFFEDE9FE);
  static const gradientLightEnd = Color(0xFFFCE7F3);
  static const gradientDarkStart = Color(0xFF1E1B4B);
  static const gradientDarkEnd = Color(0xFF312E81);

  // Status
  static const success = Color(0xFF10B981);
  static const error = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);

  // Session card accent colors
  static const sessionGreen = Color(0xFFD1FAE5);
  static const sessionBlue = Color(0xFFDBEAFE);
  static const sessionPurple = Color(0xFFEDE9FE);
  static const sessionPink = Color(0xFFFCE7F3);
  static const sessionOrange = Color(0xFFFFEDD5);
}

extension AccentColors on BuildContext {
  /// Brand color for selected text and icons, readable in both themes.
  Color get accentText => Theme.of(this).brightness == Brightness.dark
      ? AppColors.primaryOnDark
      : AppColors.primary;
}
