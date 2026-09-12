import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';

import '../capture_quality.dart';
import '../copy.dart';
import '../document_type.dart';
import '../formatting.dart';
import '../model_manager.dart';
import '../page_source.dart';
import '../store.dart';
import '../sync.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/feedback.dart';
import '../widgets/filter_chips.dart';
import '../widgets/status_chip.dart';
import 'capture_detail_screen.dart';

/// On-device capture: pick a document, run inference locally, store it, and
/// sync the structured result. Also lists this device's captures.
///
/// Raw images are never uploaded here — only the structured envelope is synced.
/// (Raw uploads exist under Docs, and are always a separate, explicit action.)
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({
    super.key,
    required this.models,
    required this.sync,
    required this.refreshToken,
    required this.isActive,
    required this.onChanged,
  });

  final ModelManager models;
  final V2Sync sync;
  final int refreshToken;

  /// Whether this is the tab currently shown; inactive tabs defer their reload.
  final bool isActive;
  final VoidCallback onChanged;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _picker = ImagePicker();

  /// Auto by default: the app should work out what the document is rather than
  /// making the user classify it before they have even taken the photo.
  CaptureMode _mode = CaptureMode.auto;

  String _status = 'Pick a document to begin on-device processing.';
  bool _busy = false;
  List<Map<String, Object?>> _rows = const [];
  int _seenToken = -1;

  /// Set when this screen caused the change itself, so the token bump it
  /// triggers does not immediately re-read the list it just updated.
  bool _changedLocally = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _loadRows();
  }

  @override
  void didUpdateWidget(covariant CaptureScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive) return;
    if (_changedLocally) {
      _changedLocally = false;
      _seenToken = widget.refreshToken;
      return;
    }
    if (widget.refreshToken != _seenToken) _loadRows();
  }

  void _notifyChanged() {
    _changedLocally = true;
    widget.onChanged();
  }

  Future<void> _loadRows() async {
    _seenToken = widget.refreshToken;
    final store = await ResultStore.instance();
    final rows = await store.all(limit: 100);
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _pickCamera(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 92);
    if (picked == null) return;
    await _gateThenIngest(File(picked.path), picked.name);
  }

  /// The ML Kit document scanner is Android-only; elsewhere fall back to the
  /// plain camera picker (no perspective correction).
  bool get _canScan => defaultTargetPlatform == TargetPlatform.android;

  Future<void> _captureDocument() =>
      _canScan ? _scanDocument() : _pickCamera(ImageSource.camera);

  /// Full-screen ML Kit document scanner: automatic capture, edge detection,
  /// perspective correction and dewarp. The corrected image is what removes
  /// the skewed-page column-overlap bug at the source. Android only.
  ///
  /// Retake is offered inline: a rejected frame re-opens the scanner rather
  /// than making the user find the button again.
  Future<void> _scanDocument() async {
    setState(() {
      _busy = true;
      _status = 'Opening the document scanner…';
    });
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final scanner = DocumentScanner(
          options: DocumentScannerOptions(
            documentFormats: const {DocumentFormat.jpeg},
            mode: ScannerMode.full,
            pageLimit: 1,
            isGalleryImport: true,
          ),
        );
        DocumentScanningResult result;
        try {
          result = await scanner.scanDocument();
        } finally {
          // Always release the native scanner handle, even on failure.
          try {
            await scanner.close();
          } catch (_) {
            // Best-effort; a leaked handle is worse than a swallowed error.
          }
        }

        final images = result.images ?? const <String>[];
        if (images.isEmpty) {
          if (mounted) {
            setState(() {
              _busy = false;
              _status = 'Scan cancelled.';
            });
          }
          return;
        }

        final scanned = File(images.first);
        final name = 'scan_${DateTime.now().microsecondsSinceEpoch}.jpg';
        final assessment = await _assessImage(scanned);
        if (assessment == null || assessment.ok) {
          await _ingest(scanned, name);
          return;
        }
        if (!mounted) return;
        if (await _showQualityDialog(assessment)) {
          await _ingest(scanned, name);
          return;
        }
        // Retake: loop and re-open the scanner.
        setState(() => _status = 'Retake requested — reopen the scanner…');
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Retake requested.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Document scanner unavailable: $e';
        });
      }
    }
  }

  /// Pick any supported file: PDF or image.
  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );
    if (picked == null) return;

    final path = picked.path;
    if (path == null) {
      // Some providers hand back bytes only; stage them so the pipeline has a
      // path it can work with.
      final staged = await PageSource.writeTemp(
        await picked.readAsBytes(),
        picked.name,
      );
      await _ingest(staged, picked.name);
      return;
    }
    await _gateThenIngest(File(path), picked.name);
  }

  /// Run the quality gate on an image before inference, then ingest. PDFs are
  /// skipped: they are digital renders, not camera frames.
  Future<void> _gateThenIngest(File source, String filename) async {
    if (isSupportedImage(filename)) {
      final assessment = await _assessImage(source);
      if (assessment != null && !assessment.ok) {
        if (!mounted) return;
        if (!await _showQualityDialog(assessment)) {
          setState(() {
            _busy = false;
            _status = 'Retake requested — choose a clearer image.';
          });
          return;
        }
      }
    }
    await _ingest(source, filename);
  }

  /// Decode + assess off the main isolate. Returns null when the image cannot
  /// be read here (the pipeline reports that properly later).
  Future<CaptureAssessment?> _assessImage(File file) async {
    try {
      return await compute(assessCaptureBytes, await file.readAsBytes());
    } catch (e) {
      debugPrint('CaptureScreen: quality gate skipped — $e');
      return null;
    }
  }

  /// Returns true when the user chooses to proceed despite the issues.
  Future<bool> _showQualityDialog(CaptureAssessment assessment) async {
    final reasons = assessment.issues.map((i) => '• ${i.message}').join('\n');
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retake this photo?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This image may not read well:'),
            const SizedBox(height: 8),
            Text(reasons, style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Retake'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Use anyway'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  /// Persist the picked file, then run the queued on-device pass.
  Future<void> _ingest(File source, String filename) async {
    setState(() {
      _busy = true;
      _status = 'Preparing ${fileTypeLabel(filename)}…';
    });
    try {
      final persisted = await PageSource.persist(source, filename: filename);

      final kind = kindOf(persisted.path);
      final pageNote = kind == SourceKind.pdf ? ' (reading pages)' : '';
      setState(
        () => _status = 'Running on-device inference$pageNote — queued…',
      );

      await _run(persisted);
    } on IngestException catch (e) {
      setState(() {
        _status = e.message;
        _busy = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Could not prepare that file: $e';
        _busy = false;
      });
    }
  }

  Future<void> _run(File persisted) async {
    try {
      final Map<String, dynamic> envelope;
      switch (_mode.pinned) {
        case DocumentType.xray:
          envelope = await widget.models.processXray(
            source: persisted,
            sync: widget.sync,
            token: widget.sync.token,
          );
        case DocumentType.labReport:
          envelope = await widget.models.processDocument(
            source: persisted,
            kind: DocumentType.labReport.wireName,
            sync: widget.sync,
            token: widget.sync.token,
          );
        case DocumentType.prescription:
          envelope = await widget.models.processDocument(
            source: persisted,
            kind: DocumentType.prescription.wireName,
            sync: widget.sync,
            token: widget.sync.token,
          );
        case null:
          envelope = await widget.models.processAuto(
            source: persisted,
            sync: widget.sync,
            token: widget.sync.token,
          );
      }

      // Report the status actually written to the store (pending when offline,
      // synced when it reached the backend) rather than assuming. A genuine
      // server rejection is surfaced with its message, not swallowed.
      final store = await ResultStore.instance();
      final latest = await store.all(limit: 1);
      final row = latest.isNotEmpty ? latest.first : null;
      final syncStatus = row == null ? 'pending' : '${row['sync_status']}';
      final syncError = row?['error'];

      setState(() {
        _status = [
          _describe(envelope, requested: _mode),
          _provenance(envelope),
          reviewStatusLine(syncStatus),
          if (syncStatus == 'failed' && syncError != null) 'Sync error: $syncError',
        ].join('\n');
        _busy = false;
      });
      await _loadRows();
      _notifyChanged();
    } catch (e) {
      setState(() {
        _status = 'Could not process document: $e';
        _busy = false;
      });
    }
  }

  /// Secondary line: timing, engine, and page count when multipage.
  String _provenance(Map<String, dynamic> envelope) {
    final pageCount = envelope['page_count'];
    final truncated = envelope['pages_truncated'] == true;
    final pages = pageCount is int && pageCount > 1
        ? '$pageCount pages${truncated ? ' (first $maxPdfPages used)' : ''} · '
        : '';
    return '$pages${envelope['latency_ms']} ms · ${envelope['engine']}';
  }

  /// Lead line for the status panel, including what detection decided.
  String _describe(
    Map<String, dynamic> envelope, {
    required CaptureMode requested,
  }) {
    final kind = '${envelope['kind']}';
    final type = DocumentTypeWire.fromWire(kind);
    final label = type?.label ?? 'Result';

    final detection = envelope['detection'];
    if (requested.pinned != null) {
      return '$label — you selected this type.';
    }
    if (detection is! Map) {
      return 'Detected $label.';
    }
    final confidence = detection['confidence'];
    final pct = confidence is num ? (confidence * 100).round() : null;
    final reasons = detection['reasons'];
    final basis = reasons is List && reasons.isNotEmpty
        ? reasons.take(3).join(', ')
        : 'document layout';
    final pctLabel = pct == null ? '' : ' ($pct%)';
    final weak = pct != null && pct < 60;
    return weak
        ? 'Detected $label$pctLabel from $basis — low confidence, '
              'correct it below if that is wrong.'
        : 'Detected $label$pctLabel from $basis.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: _loadRows,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Capture', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Inference runs on this device. Only the structured result is synced.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Document type', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  'Leave on Auto and the app works out the type from the '
                  'extracted text.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                // Wrap-based, so four options never overflow a narrow screen.
                FilterChips<CaptureMode>(
                  values: CaptureMode.values,
                  selected: _mode,
                  labelOf: (m) => m.label,
                  onSelected: (m) => setState(() => _mode = m),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _captureDocument,
                        icon: const Icon(
                          Icons.document_scanner_outlined,
                          size: 18,
                        ),
                        label: Text(_canScan ? 'Scan document' : 'Camera'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pickCamera(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library, size: 18),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                if (_canScan) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Scan detects the page edges and corrects perspective '
                    'before OCR.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 10),
                // PDFs and saved images: a lab report usually arrives as a PDF
                // rather than a photo, and those pages carry the reference
                // ranges the normalizer needs.
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Choose PDF or image file'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Supports ${supportedExtensions.map((e) => e.toUpperCase()).join(', ')}.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _StatusPanel(status: _status, busy: _busy),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'This device (${_rows.length})',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (_rows.isNotEmpty)
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          await widget.sync.retryQueued();
                          await _loadRows();
                          _notifyChanged();
                        },
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('Sync now'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_rows.isEmpty)
            const EmptyState(
              icon: Icons.document_scanner_outlined,
              title: 'No captures yet',
              message: 'Capture a document above to run on-device inference.',
            )
          else
            for (final row in _rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CaptureTile(
                  row: row,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CaptureDetailScreen(
                          rowId: row['id'] as int,
                          models: widget.models,
                          sync: widget.sync,
                          onChanged: _notifyChanged,
                        ),
                      ),
                    );
                    await _loadRows();
                  },
                ),
              ),
          const SizedBox(height: 12),
          Text(
            'Scope note: printed documents only — handwriting OCR is future '
            'work and is not attempted on-device.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status, required this.busy});

  final String status;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        color: AppColors.primary.withValues(alpha: 0.06),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: AppColors.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 5),
                      Text(status, style: theme.textTheme.bodySmall),
                      if (busy) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: const LinearProgressIndicator(minHeight: 5),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({required this.row, required this.onTap});

  final Map<String, Object?> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = '${row['kind']}';
    final status = '${row['sync_status']}';

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.activeNavFill,
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
            child: Icon(_iconFor(kind), size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          // Flexible, not fixed: the type name and timestamp must be able to
          // shrink on a narrow screen next to the status chip.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DocumentTypeWire.fromWire(kind)?.label ?? kindLabel(kind),
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  formatRelative(DateTime.tryParse('${row['created_at']}')),
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(status: status),
        ],
      ),
    );
  }

  static IconData _iconFor(String kind) {
    switch (kind) {
      case 'prescription':
        return Icons.medication_outlined;
      case 'xray':
        return Icons.image_outlined;
      default:
        return Icons.science_outlined;
    }
  }
}
