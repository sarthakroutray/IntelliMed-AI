import 'package:flutter/material.dart';

import '../theme.dart';

/// Pill status badge replacing the default `Chip`, using the web app's
/// `.status-badge` tone pairs (processed / pending / failed).
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (background, foreground) = _tones(isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  (Color, Color) _tones(bool isDark) {
    final fill = AppColors.statusDarkFillAlpha;
    switch (status) {
      case 'synced':
        return isDark
            ? (
                const Color(0xFF22C55E).withValues(alpha: fill),
                AppColors.statusSyncedDarkFg,
              )
            : (AppColors.statusSyncedLightBg, AppColors.statusSyncedLightFg);
      case 'failed':
        return isDark
            ? (
                const Color(0xFFEF4444).withValues(alpha: fill),
                AppColors.statusFailedDarkFg,
              )
            : (AppColors.statusFailedLightBg, AppColors.statusFailedLightFg);
      default:
        return isDark
            ? (
                const Color(0xFFF59E0B).withValues(alpha: fill),
                AppColors.statusPendingDarkFg,
              )
            : (AppColors.statusPendingLightBg, AppColors.statusPendingLightFg);
    }
  }
}
