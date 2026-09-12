import 'package:flutter/material.dart';

import '../api/models.dart';
import '../copy.dart';
import '../formatting.dart';
import '../theme.dart';
import '../trends.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/trend_sparkline.dart';

/// One analyte's history: a larger sparkline with the printed reference band,
/// then every reading in date order with its source for traceability.
class TrendDetailScreen extends StatelessWidget {
  const TrendDetailScreen({super.key, required this.series});

  final TrendSeries series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = series.latest;
    final band = series.referenceBand;
    final readings = series.points.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(series.testName, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UnitChip(label: series.unitLabel),
                const SizedBox(height: 10),
                Text(
                  latest.unit == null || latest.unit!.isEmpty
                      ? formatNumber(latest.value)
                      : '${formatNumber(latest.value)} ${latest.unit}',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  'Latest ${formatDate(latest.date)} · '
                  '${series.points.length} '
                  '${series.points.length == 1 ? 'reading' : 'readings'}',
                  style: theme.textTheme.bodySmall,
                ),
                if (band != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Printed range on latest report: ${_bandLabel(band)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                TrendSparkline(series: series, height: 140),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const InlineBanner(
            tone: BannerTone.info,
            icon: Icons.info_outline,
            message: trendReadingCaption,
          ),
          const SizedBox(height: 18),
          Text('Readings', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < readings.length; i++)
                  _ReadingRow(
                    point: readings[i],
                    isLatest: i == 0,
                    showDivider: i != readings.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _bandLabel(({double? low, double? high}) band) {
    if (band.low != null && band.high != null) {
      return '${formatNumber(band.low)} – ${formatNumber(band.high)}';
    }
    if (band.low != null) return '≥ ${formatNumber(band.low)}';
    if (band.high != null) return '≤ ${formatNumber(band.high)}';
    return '—';
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({
    required this.point,
    required this.isLatest,
    required this.showDivider,
  });

  final TrendPoint point;
  final bool isLatest;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = point.unit == null || point.unit!.isEmpty
        ? formatNumber(point.value)
        : '${formatNumber(point.value)} ${point.unit}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(formatDate(point.date), style: theme.textTheme.bodyMedium),
                        if (isLatest) ...[
                          const SizedBox(width: 8),
                          const _MiniBadge(label: 'latest'),
                        ],
                        if (point.flagInSource != null) ...[
                          const SizedBox(width: 8),
                          _MiniBadge(
                            label: 'marked "${point.flagInSource}" on document',
                          ),
                        ],
                      ],
                    ),
                    if (point.sourceLabel != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        point.sourceLabel!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: theme.textTheme.titleSmall),
                  if (point.hasRange)
                    Text(
                      'ref ${_rangeLabel(point)}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: AppColors.border(theme.brightness)),
      ],
    );
  }

  static String _rangeLabel(TrendPoint point) {
    if (point.rangeLow != null && point.rangeHigh != null) {
      return '${formatNumber(point.rangeLow)} – ${formatNumber(point.rangeHigh)}';
    }
    if (point.rangeLow != null) return '≥ ${formatNumber(point.rangeLow)}';
    if (point.rangeHigh != null) return '≤ ${formatNumber(point.rangeHigh)}';
    return point.rangeRaw ?? '—';
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(theme.brightness),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border(theme.brightness)),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary),
      ),
    );
  }
}
