import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Material 3 theme in navy / white / gold, with light and dark variants.
///
/// Latin text uses Noto Sans; Telugu glyphs fall back to Noto Sans Telugu,
/// both bundled in assets/fonts so Telugu always renders correctly.
abstract final class AppTheme {
  static const String latinFont = 'NotoSans';
  static const String teluguFont = 'NotoSansTelugu';

  /// Style for large Telugu reading/writing areas (Telugu font first).
  static TextStyle teluguBody(BuildContext context, {double size = 20}) {
    return TextStyle(
      fontFamily: teluguFont,
      fontFamilyFallback: const [latinFont],
      fontSize: size,
      height: 1.6,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navy,
      brightness: brightness,
      primary: isDark ? const Color(0xFF9CC4F0) : AppColors.navy,
      onPrimary: isDark ? AppColors.navyDeep : AppColors.white,
      secondary: AppColors.gold,
      onSecondary: AppColors.onGold,
      surface: isDark ? AppColors.darkSurface : AppColors.white,
    );

    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      fontFamily: latinFont,
      fontFamilyFallback: const [teluguFont],
      appBarTheme: AppBarThemeData(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: isDark ? const Color(0xFF13253C) : AppColors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: BorderSide(color: scheme.primary, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: AppColors.gold,
        inactiveTrackColor: scheme.primary.withValues(alpha: 0.18),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
