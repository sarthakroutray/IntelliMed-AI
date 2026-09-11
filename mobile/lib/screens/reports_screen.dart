import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/patient_repository.dart';
import '../copy.dart';
import '../formatting.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import 'report_detail_screen.dart';

/// Server-side structured results (v2 lab reports), including any synced from
/// this device. Read-only: the app never edits server results.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.repository,
    required this.refreshToken,
  });

  final PatientRepository repository;
  final int refreshToken;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  String? _error;
  List<LabReport> _reports = const [];
  int _seenToken = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != _seenToken) _load();
  }

  Future<void> _load() async {
    _seenToken = widget.refreshToken;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final reports = await widget.repository.listLabReports();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Lab reports', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Structured results stored on the server, including captures synced '
            'from this device.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const LoadingView(message: 'Loading reports…')
          else if (_error != null)
            ErrorView(message: _error!, onRetry: _load)
          else if (_reports.isEmpty)
            EmptyState(
              icon: Icons.description_outlined,
              title: 'No lab reports yet',
              message:
                  'Reports appear here once a lab report has been processed or '
                  'a capture from this device has synced.',
              actionLabel: 'Refresh',
              onAction: _load,
            )
          else
            for (final report in _reports)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReportTile(
                  report: report,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReportDetailScreen(
                        repository: widget.repository,
                        summary: report,
                      ),
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 12),
          Text(
            patternListCaption,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report, required this.onTap});

  final LabReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = report.result;
    final tests = result.testCount;
    final patterns = result.flaggedPatterns.length;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.science_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  report.filename,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (report.fromApp)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: const Text(
                    'FROM APP',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(formatDateTime(report.uploadedAt), style: theme.textTheme.bodySmall),
          if (tests > 0 || patterns > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              children: [
                if (tests > 0)
                  Text('$tests measurements', style: theme.textTheme.bodySmall),
                if (patterns > 0)
                  Text(
                    '$patterns pattern${patterns == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
