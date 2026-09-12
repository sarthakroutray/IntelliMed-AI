import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/patient_repository.dart';
import '../formatting.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/result_viewers.dart';

/// Full structured view of one lab report.
///
/// Fetches the detail route (which adds `file_url`) and renders the envelope.
/// Handles both stored envelope shapes: server-pipeline records carry a
/// `stage1` OCR tree we deliberately never render; app records don't.
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({
    super.key,
    required this.repository,
    required this.summary,
  });

  final PatientRepository repository;

  /// The list row, so the screen can render immediately while detail loads.
  final LabReport summary;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  bool _loading = true;
  String? _error;
  LabReport? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final report = await widget.repository.getLabReport(widget.summary.id);
      if (!mounted) return;
      setState(() {
        _report = report;
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

  Future<void> _openFile() async {
    final url = _report?.fileUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _report ?? widget.summary;
    final envelope = report.result;

    return Scaffold(
      appBar: AppBar(title: const Text('Lab report')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report.filename, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    formatDateTime(report.uploadedAt),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Chip(label: report.fromApp ? 'From app' : 'Web upload'),
                      if (envelope.hasStage1)
                        const _Chip(label: 'Server-extracted'),
                      if (envelope.testCount > 0)
                        _Chip(label: '${envelope.testCount} measurements'),
                    ],
                  ),
                  if (report.fileUrl != null && report.fileUrl!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openFile,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open original document'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading && _report == null)
              const LoadingView(message: 'Loading structured result…')
            else ...[
              if (_error != null) ...[
                InlineBanner(
                  tone: BannerTone.warning,
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not refresh from the server',
                  message:
                      '$_error Showing the details already loaded on this device.',
                ),
                const SizedBox(height: 12),
              ],
              if (envelope.isEmpty && _error != null)
                ErrorView(message: _error!, onRetry: _load)
              else
                ResultEnvelopeView(envelope: envelope),
            ],
            const SizedBox(height: 16),
            const InlineBanner(
              tone: BannerTone.info,
              icon: Icons.info_outline,
              message:
                  'This is structured context extracted from the document, for '
                  'review with your doctor. It is not a diagnosis.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt(brightness),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.border(brightness)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
