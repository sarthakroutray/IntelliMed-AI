import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/patient_repository.dart';
import '../copy.dart';
import '../formatting.dart';
import '../store.dart';
import '../theme.dart';
import '../trends.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/trend_sparkline.dart';
import 'trend_detail_screen.dart';

/// "Your values over time" — one card per analyte, from this device's captures
/// and the account's server reports, merged without double-counting a capture
/// that has synced.
///
/// Purely arithmetic over stored rows: no model, and no direction wording.
class TrendsScreen extends StatefulWidget {
  const TrendsScreen({
    super.key,
    required this.repository,
    this.refreshToken = 0,
  });

  final PatientRepository repository;
  final int refreshToken;

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  bool _loading = true;
  String? _serverError;
  List<TrendSeries> _series = const [];
  int _pointCount = 0;
  int _seenToken = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TrendsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != _seenToken) _load();
  }

  Future<void> _load() async {
    _seenToken = widget.refreshToken;
    if (mounted) setState(() => _loading = true);

    // Local first: always available offline.
    final store = await ResultStore.instance();
    final rows = await store.labReportRows();
    final points = trendPointsFromLocalRows(rows);

    var serverError = '';
    try {
      final reports = await widget.repository.listLabReports();
      // A synced capture exists both locally and on the server; skip the
      // server copy so its readings are not counted twice.
      points.addAll(
        trendPointsFromReports(reports, skipIds: syncedServerIds(rows)),
      );
    } on ApiException catch (e) {
      serverError = e.kind == ApiErrorKind.unauthorized
          ? 'Your session has expired. Sign in again from Me.'
          : e.message;
    }

    final series = buildTrendSeries(points);
    if (!mounted) return;
    setState(() {
      _series = series;
      _pointCount = points.length;
      _serverError = serverError.isEmpty ? null : serverError;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Measurements from your reports, in date order.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_serverError != null) ...[
              InlineBanner(
                tone: BannerTone.warning,
                icon: Icons.cloud_off_outlined,
                title: 'Server unavailable',
                message: '$_serverError Showing on-device data only.',
              ),
              const SizedBox(height: 16),
            ],
            if (_loading && _series.isEmpty)
              const LoadingView(message: 'Reading your results…')
            else if (_series.isEmpty)
              const EmptyState(
                icon: Icons.show_chart,
                title: 'No measurements yet',
                message:
                    'Capture or upload a lab report and its measurements will '
                    'appear here over time.',
              )
            else ...[
              if (hasUnitSplit(_series)) ...[
                const InlineBanner(
                  tone: BannerTone.warning,
                  icon: Icons.straighten,
                  message: trendUnitSplitNote,
                ),
                const SizedBox(height: 16),
              ],
              for (final series in _series)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SeriesCard(
                    series: series,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TrendDetailScreen(series: series),
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 4),
            if (_pointCount > 0)
              Text(
                '$_pointCount readings across ${_series.length} '
                '${_series.length == 1 ? 'measurement' : 'measurements'}.',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 12),
            Text(
              trendsCaption,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.series, required this.onTap});

  final TrendSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = series.latest;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        series.testName,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _UnitChip(label: series.unitLabel),
                  ],
                ),
              ),
              Text(
                latest.unit == null || latest.unit!.isEmpty
                    ? formatNumber(latest.value)
                    : '${formatNumber(latest.value)} ${latest.unit}',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${series.points.length} '
            '${series.points.length == 1 ? 'reading' : 'readings'} · '
            'latest ${formatDate(latest.date)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          TrendSparkline(series: series, height: 52),
          if (series.referenceBand != null) ...[
            const SizedBox(height: 6),
            Text(
              'Shaded band: printed range on the latest report',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(theme.brightness),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border(theme.brightness)),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}
