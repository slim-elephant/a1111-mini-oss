import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'glass_tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.backgroundLight,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.primaryLight,
          surface: AppColors.surfaceLight,
          error: AppColors.error,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: AppColors.textPrimaryLight,
          onError: Colors.white,
        ),
        fontFamily: '.SF Pro Display',
        textTheme: _textTheme(AppColors.textPrimaryLight, AppColors.textSecondaryLight),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: AppColors.textPrimaryLight),
          titleTextStyle: TextStyle(
            color: AppColors.textPrimaryLight,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.cardLight,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GlassTokens.radiusLg),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cardLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            borderSide: const BorderSide(color: AppColors.borderLight, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: const TextStyle(color: AppColors.textSecondaryLight, fontSize: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            ),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: CircleBorder(),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.borderLight,
          thickness: 0.5,
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: AppColors.surfaceLight,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(GlassTokens.radiusXl)),
          ),
        ),
      );

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.backgroundDark,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFF6D5CE7),
          onPrimaryContainer: Colors.white,
          secondary: AppColors.primaryLight,
          onSecondary: Color(0xFF0F172A),
          secondaryContainer: Color(0xFF6D5CE7),
          onSecondaryContainer: Colors.white,
          surface: AppColors.surfaceDark,
          onSurface: AppColors.textPrimaryDark,
          onSurfaceVariant: Color(0xFFE5E7EB),
          surfaceContainerHighest: AppColors.cardDark,
          error: AppColors.error,
          onError: Colors.white,
          outline: AppColors.borderDark,
        ),
        fontFamily: '.SF Pro Display',
        textTheme: _textTheme(AppColors.textPrimaryDark, AppColors.textSecondaryDark),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: AppColors.textPrimaryDark),
          titleTextStyle: TextStyle(
            color: AppColors.textPrimaryDark,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.cardDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GlassTokens.radiusLg),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.cardDark,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            borderSide: const BorderSide(color: AppColors.borderDark, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: const TextStyle(color: AppColors.textSecondaryDark, fontSize: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
            ),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: CircleBorder(),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.borderDark,
          thickness: 0.5,
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: AppColors.surfaceDark,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(GlassTokens.radiusXl)),
          ),
        ),
        chipTheme: ChipThemeData(
          brightness: Brightness.dark,
          backgroundColor: AppColors.cardDark,
          selectedColor: AppColors.primary,
          disabledColor: AppColors.cardDark,
          checkmarkColor: Colors.white,
          side: const BorderSide(color: AppColors.borderDark),
          labelStyle: const TextStyle(
            color: AppColors.textPrimaryDark,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          secondaryLabelStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          color: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.primary;
            return AppColors.cardDark;
          }),
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AppColors.primaryOnDark,
          selectionColor: AppColors.primaryOnDark.withValues(alpha: 0.35),
          selectionHandleColor: AppColors.primaryOnDark,
        ),
        listTileTheme: const ListTileThemeData(
          selectedColor: AppColors.primaryOnDark,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.primaryOnDark),
        ),
      );

  static TextTheme _textTheme(Color primary, Color secondary) => TextTheme(
        headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: primary),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primary),
        headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: primary),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: primary),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: primary),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: primary),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: secondary),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: primary),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: secondary),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: secondary),
      );
}
