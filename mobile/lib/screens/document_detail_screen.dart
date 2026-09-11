import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/patient_repository.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/result_viewers.dart';

/// Full view of one server-side document: file metadata, AI analysis, sharing.
class DocumentDetailScreen extends StatefulWidget {
  const DocumentDetailScreen({
    super.key,
    required this.repository,
    required this.documentId,
    this.filename,
  });

  final PatientRepository repository;
  final int documentId;

  /// Shown in the app bar while the detail loads.
  final String? filename;

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  DocumentDetail? _document;

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
      final doc = await widget.repository.getDocument(widget.documentId);
      if (!mounted) return;
      setState(() {
        _document = doc;
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

  Future<void> _analyze() async {
    setState(() => _busy = true);
    try {
      await widget.repository.analyzeDocument(widget.documentId);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openFile() async {
    final url = _document?.fileUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the document.')),
      );
    }
  }

  Future<void> _openShareSheet() async {
    final doc = _document;
    if (doc == null) return;

    final selected = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ShareSheet(
        repository: widget.repository,
        documentId: doc.id,
        filename: doc.fileName ?? widget.filename ?? 'Document',
      ),
    );
    if (selected == null) return;

    // Apply the diff: the sheet returns the desired set of doctor ids.
    setState(() => _busy = true);
    try {
      final current = await widget.repository.listSharedDoctors(doc.id);
      final currentIds = current.map((d) => d.doctorId).toSet();
      for (final id in selected.difference(currentIds)) {
        await widget.repository.shareDocument(doc.id, id);
      }
      for (final id in currentIds.difference(selected)) {
        await widget.repository.unshareDocument(doc.id, id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sharing updated.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = _document;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          doc?.fileName ?? widget.filename ?? 'Document',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (doc != null) ...[
            IconButton(
              tooltip: 'Share with doctors',
              onPressed: _busy ? null : _openShareSheet,
              icon: const Icon(Icons.share_outlined),
            ),
            IconButton(
              tooltip: doc.isPending ? 'Run analysis' : 'Re-run analysis',
              onPressed: _busy ? null : _analyze,
              icon: const Icon(Icons.auto_awesome_outlined),
            ),
          ],
        ],
      ),
      body: _loading
          ? const LoadingView(message: 'Loading document…')
          : _error != null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [ErrorView(message: _error!, onRetry: _load)],
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (doc != null) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                doc.fileName ?? 'Document',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            if (doc.status != null)
                              Text(
                                doc.status!,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (doc.fileType != null) doc.fileType!,
                            if (doc.timestamp != null) doc.timestamp!,
                          ].join(' • '),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (doc.fileUrl != null && doc.fileUrl!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _openFile,
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Open original'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (doc.isPending)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: InlineBanner(
                        tone: BannerTone.warning,
                        icon: Icons.hourglass_empty,
                        title: 'Not analyzed yet',
                        message:
                            'Run analysis to extract text, medications and '
                            'classifier output from this document.',
                      ),
                    ),
                  DocumentAnalysisView(analysis: doc.analysis),
                ],
                const SizedBox(height: 16),
                const InlineBanner(
                  tone: BannerTone.info,
                  icon: Icons.info_outline,
                  message:
                      'Extracted text and findings are assistive context for '
                      'review with your doctor. Not a diagnosis.',
                ),
              ],
            ),
    );
  }
}

/// Bottom sheet listing linked doctors with a checkbox each.
class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.repository,
    required this.documentId,
    required this.filename,
  });

  final PatientRepository repository;
  final int documentId;
  final String filename;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _loading = true;
  String? _error;
  List<LinkedDoctor> _doctors = const [];
  Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repository.listLinkedDoctors(),
        widget.repository.listSharedDoctors(widget.documentId),
      ]);
      final doctors = results[0] as List<LinkedDoctor>;
      final shared = results[1] as List<SharedDoctor>;
      if (!mounted) return;
      setState(() {
        _doctors = doctors;
        _selected = shared.map((d) => d.doctorId).toSet();
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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Share document', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              widget.filename,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            // Flexible + scrollable: a patient may have many linked doctors,
            // and an unbounded list would overflow the sheet.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_loading)
                      const LoadingView()
                    else if (_error != null)
                      ErrorView(message: _error!, onRetry: _load)
                    else if (_doctors.isEmpty)
                      const EmptyState(
                        icon: Icons.group_outlined,
                        title: 'No linked doctors',
                        message:
                            'Generate an access code from Me, share it with your '
                            'doctor, and they will appear here.',
                      )
                    else
                      for (final doctor in _doctors)
                        CheckboxListTile(
                          value: _selected.contains(doctor.id),
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _selected.add(doctor.id);
                            } else {
                              _selected.remove(doctor.id);
                            }
                          }),
                          title: Text(
                            doctor.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            doctor.email,
                            overflow: TextOverflow.ellipsis,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _loading || _error != null
                        ? null
                        : () => Navigator.of(context).pop(_selected),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
