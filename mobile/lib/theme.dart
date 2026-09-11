import 'package:flutter/material.dart';

/// Design tokens lifted from the web app so the on-device UI matches it.
///
/// Mirrors `frontend/index.html` (the inline tailwind.config) and the sidebar
/// / card surfaces in `frontend/src/pages/*DashboardLayout.jsx`.
class AppColors {
  const AppColors._();

  static const primary = Color(0xFF135BEC);
  static const onPrimary = Color(0xFFFFFFFF);

  /// `bg-primary/10` — the active nav-item fill in the web sidebar.
  static Color get activeNavFill => primary.withValues(alpha: 0.10);

  static const statusSyncedLightBg = Color(0xFFD4EDDA);
  static const statusSyncedLightFg = Color(0xFF155724);
  static const statusSyncedDarkFg = Color(0xFF4ADE80);

  static const statusPendingLightBg = Color(0xFFFFF3CD);
  static const statusPendingLightFg = Color(0xFF856404);
  static const statusPendingDarkFg = Color(0xFFFBBF24);

  static const statusFailedLightBg = Color(0xFFF8D7DA);
  static const statusFailedLightFg = Color(0xFF721C24);
  static const statusFailedDarkFg = Color(0xFFF87171);

  static const statusNeutralLightBg = Color(0xFFF0F2F4);
  static const statusNeutralLightFg = Color(0xFF637588);
  static const statusNeutralDarkFg = Color(0xFF9CA3AF);

  static const statusDarkFillAlpha = 0.15;
  static const errorLight = Color(0xFFDC2626);
  static const errorDark = Color(0xFFF87171);

  static const _lightBackground = Color(0xFFF6F6F8);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceAlt = Color(0xFFF0F2F4);
  static const _lightBorder = Color(0xFFDBDFE6);
  static const _lightDivider = Color(0xFFF0F2F4);
  static const _lightTextPrimary = Color(0xFF111318);
  static const _lightTextMuted = Color(0xFF637588);

  static const _darkBackground = Color(0xFF101622);
  static const _darkSurface = Color(0xFF1A202C);
  static const _darkSurfaceAlt = Color(0xFF1F2937);
  static const _darkBorder = Color(0xFF1F2937);
  static const _darkDivider = Color(0xFF1F2937);
  static const _darkTextPrimary = Color(0xFFFFFFFF);
  static const _darkTextMuted = Color(0xFF9CA3AF);

  static Color background(Brightness b) =>
      b == Brightness.dark ? _darkBackground : _lightBackground;
  static Color surface(Brightness b) =>
      b == Brightness.dark ? _darkSurface : _lightSurface;
  static Color surfaceAlt(Brightness b) =>
      b == Brightness.dark ? _darkSurfaceAlt : _lightSurfaceAlt;
  static Color border(Brightness b) =>
      b == Brightness.dark ? _darkBorder : _lightBorder;
  static Color divider(Brightness b) =>
      b == Brightness.dark ? _darkDivider : _lightDivider;
  static Color textPrimary(Brightness b) =>
      b == Brightness.dark ? _darkTextPrimary : _lightTextPrimary;
  static Color textMuted(Brightness b) =>
      b == Brightness.dark ? _darkTextMuted : _lightTextMuted;
}

/// Corner radii matching the tailwind theme (`lg` = 8, `xl` = 12, `full`).
class AppRadius {
  const AppRadius._();

  static const card = 12.0;
  static const control = 8.0;
  static const pill = 999.0;
}

class AppTheme {
  const AppTheme._();

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = AppColors.background(brightness);
    final surface = AppColors.surface(brightness);
    final surfaceAlt = AppColors.surfaceAlt(brightness);
    final border = AppColors.border(brightness);
    final divider = AppColors.divider(brightness);
    final textPrimary = AppColors.textPrimary(brightness);
    final textMuted = AppColors.textMuted(brightness);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: brightness,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          surface: surface,
          onSurface: textPrimary,
          surfaceContainerHighest: surfaceAlt,
          surfaceContainerLow: surface,
          outline: border,
          outlineVariant: divider,
          onSurfaceVariant: textMuted,
          error: isDark ? AppColors.errorDark : AppColors.errorLight,
        );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
      side: BorderSide(color: border),
    );
    final buttonTextStyle = TextStyle(
      fontFamily: 'Manrope',
      fontWeight: FontWeight.w700,
      fontSize: 15,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Manrope',
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: textMuted),
        shape: Border(bottom: BorderSide(color: divider)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.38),
          disabledForegroundColor: AppColors.onPrimary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: controlShape,
          textStyle: buttonTextStyle,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: surface,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: border),
          shape: controlShape,
          textStyle: buttonTextStyle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: buttonTextStyle,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary.withValues(alpha: 0.10);
            }
            return surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return textMuted;
          }),
          iconColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return textMuted;
          }),
          textStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              fontFamily: 'Manrope',
              fontSize: 14,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
            );
          }),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        side: BorderSide(color: border),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: textPrimary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: TextStyle(
          fontFamily: 'Manrope',
          color: textMuted,
          fontSize: 14,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Manrope',
          color: textMuted,
          fontSize: 14,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: textPrimary,
          fontSize: 14,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface(Brightness.dark),
        contentTextStyle: const TextStyle(
          fontFamily: 'Manrope',
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: Color(0x22135BEC),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textMuted,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          color: textMuted,
          fontSize: 13,
        ),
      ),
      iconTheme: IconThemeData(color: textMuted),
      textTheme: _textTheme(textPrimary, textMuted),
    );
  }

  static TextTheme _textTheme(Color textPrimary, Color textMuted) {
    return TextTheme(
      headlineSmall: TextStyle(
        color: textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.015,
      ),
      titleLarge: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: TextStyle(
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: textPrimary, fontSize: 15),
      bodyMedium: TextStyle(color: textPrimary, fontSize: 14),
      bodySmall: TextStyle(color: textMuted, fontSize: 13),
      labelLarge: TextStyle(
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: TextStyle(
        color: textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        color: textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}
