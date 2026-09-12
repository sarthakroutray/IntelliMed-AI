import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/patient_repository.dart';
import '../copy.dart';
import '../formatting.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/feedback.dart';
import 'report_detail_screen.dart';
import 'trends_screen.dart';

/// Server-side structured results (v2 lab reports), including any synced from
/// this device. Read-mostly: results are never edited, but the patient can
/// delete their own report here.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.repository,
    required this.refreshToken,
    required this.isActive,
    required this.onChanged,
  });

  final PatientRepository repository;
  final int refreshToken;

  /// Whether this is the tab currently shown; inactive tabs defer their reload.
  final bool isActive;

  /// Tells the shell that server-side data changed, so Home's counts refresh
  /// the next time it is shown (not immediately in the background).
  final VoidCallback onChanged;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  String? _error;
  List<LabReport> _reports = const [];
  int _seenToken = -1;

  /// Set when this screen caused the change itself, so the token bump it
  /// triggers does not immediately refetch the list it just updated.
  bool _changedLocally = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _load();
  }

  @override
  void didUpdateWidget(covariant ReportsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive) return;
    if (_changedLocally) {
      _changedLocally = false;
      _seenToken = widget.refreshToken;
      return;
    }
    if (widget.refreshToken != _seenToken) _load();
  }

  void _notifyChanged() {
    _changedLocally = true;
    widget.onChanged();
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

  Future<void> _delete(LabReport report) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this report?',
      message:
          '"${report.filename}" and its structured result will be removed from '
          'the server. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    // Remove the row straight away and only then talk to the server — the list
    // is what the user is looking at, and waiting on the round-trip is what
    // made deletion feel slow. On failure the row is put back.
    final previous = _reports;
    setState(() {
      _reports = _reports.where((r) => r.id != report.id).toList();
    });

    try {
      await widget.repository.deleteLabReport(report.id);
      _notifyChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report deleted.')),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _reports = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
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
          Row(
            children: [
              Expanded(
                child: Text('Lab reports', style: theme.textTheme.headlineSmall),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TrendsScreen(repository: widget.repository),
                  ),
                ),
                icon: const Icon(Icons.show_chart, size: 18),
                label: const Text('Trends'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Structured results stored on the server, including captures synced '
            'from this device.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          // Only take over the screen on the first load; a background refresh
          // keeps the existing list on screen instead of blanking it.
          if (_loading && _reports.isEmpty)
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
                  onDelete: () => _delete(report),
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
  const _ReportTile({
    required this.report,
    required this.onTap,
    required this.onDelete,
  });

  final LabReport report;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
              PopupMenuButton<String>(
                tooltip: 'Report actions',
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
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
