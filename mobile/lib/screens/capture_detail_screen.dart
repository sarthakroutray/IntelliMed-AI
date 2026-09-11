import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../copy.dart';
import '../document_type.dart';
import '../formatting.dart';
import '../model_manager.dart';
import '../page_source.dart';
import '../store.dart';
import '../sync.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/feedback.dart';
import '../widgets/result_viewers.dart';
import '../widgets/status_chip.dart';

/// Renders a capture stored on this device, and lets the user correct its
/// document type, retry its sync, or delete it.
///
/// Reads the row's `result_json` — the local envelope, which carries
/// `normalized` (no Stage 3 flags) rather than `stage2`/`stage3`. ResultEnvelope
/// handles either shape.
class CaptureDetailScreen extends StatefulWidget {
  const CaptureDetailScreen({
    super.key,
    required this.rowId,
    this.models,
    this.sync,
    this.onChanged,
  });

  final int rowId;

  /// When present, the capture can be re-run with a corrected type.
  final ModelManager? models;

  /// Optional: when present, a retry-sync action is offered.
  final V2Sync? sync;
  final VoidCallback? onChanged;

  @override
  State<CaptureDetailScreen> createState() => _CaptureDetailScreenState();
}

class _CaptureDetailScreenState extends State<CaptureDetailScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, Object?>? _row;
  ResultEnvelope? _envelope;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final store = await ResultStore.instance();
    final row = await store.byId(widget.rowId);
    ResultEnvelope? envelope;
    String? error;
    if (row == null) {
      error = 'This capture is no longer stored on the device.';
    } else {
      try {
        envelope = ResultEnvelope.fromJson(
          jsonDecode('${row['result_json']}') as Map<String, dynamic>,
        );
      } catch (_) {
        error = 'The stored result could not be read.';
      }
    }
    if (!mounted) return;
    setState(() {
      _row = row;
      _envelope = envelope;
      _error = error;
      _loading = false;
    });
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _retrySync() async {
    final sync = widget.sync;
    final row = _row;
    if (sync == null || row == null) return;
    setState(() => _busy = true);
    final id = row['id'] as int;
    final store = await ResultStore.instance();
    try {
      final envelope =
          jsonDecode('${row['result_json']}') as Map<String, dynamic>;
      final serverId = await sync.postResult(
        kind: '${row['kind']}',
        envelope: envelope,
      );
      await store.markSynced(id, serverId: serverId);
      _notify('Synced to the server.');
    } on OfflineException {
      await store.markPending(id);
      _notify('Still offline — kept for later.');
    } on UnauthorizedException {
      await store.markPending(id);
      _notify('Session expired — sign in again to sync.');
    } on RouteMissingException {
      _notify('Sync endpoint not available here.');
    } catch (e) {
      await store.markFailed(id, '$e');
      _notify('Sync failed: $e');
    } finally {
      await _load();
      widget.onChanged?.call();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Offer a corrected document type, then re-run inference on the ORIGINAL
  /// image so a misidentified capture never has to be photographed again.
  Future<void> _reclassify() async {
    final models = widget.models;
    final sync = widget.sync;
    final row = _row;
    if (models == null || row == null) return;

    final path = '${row['local_path']}';
    final oldId = row['id'] as int;
    final file = File(path);

    if (!await file.exists()) {
      _notify('The original file is no longer on this device.');
      return;
    }

    if (!mounted) return;
    final mode = await showModalBottomSheet<CaptureMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Re-run as',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
            ),
            for (final option in CaptureMode.values)
              ListTile(
                leading: Icon(_iconForMode(option)),
                title: Text(option.label),
                subtitle: option == CaptureMode.auto
                    ? const Text('Detect the type from the extracted text')
                    : null,
                onTap: () => Navigator.of(ctx).pop(option),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (mode == null) return;

    setState(() => _busy = true);
    try {
      switch (mode.pinned) {
        case DocumentType.xray:
          await models.processXray(
            source: file,
            sync: sync,
            token: sync?.token,
          );
        case DocumentType.labReport:
          await models.processDocument(
            source: file,
            kind: DocumentType.labReport.wireName,
            sync: sync,
            token: sync?.token,
          );
        case DocumentType.prescription:
          await models.processDocument(
            source: file,
            kind: DocumentType.prescription.wireName,
            sync: sync,
            token: sync?.token,
          );
        case null:
          await models.processAuto(
            source: file,
            sync: sync,
            token: sync?.token,
          );
      }

      // The re-run inserted a new row for the same image; drop the old one so
      // the capture list doesn't show the same photo twice.
      final store = await ResultStore.instance();
      final rows = await store.byPath(path);
      final hasNewRow = rows.any((r) => r['id'] != oldId);
      if (hasNewRow) {
        await store.delete(oldId);
        widget.onChanged?.call();
        if (mounted) Navigator.of(context).pop();
        return;
      }
      _notify('Re-run produced no new result — the original was kept.');
    } catch (e) {
      _notify('Re-run failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final row = _row;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this capture?',
      message:
          'The result is removed from this device. Anything already synced '
          'stays on the server.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    final store = await ResultStore.instance();
    await store.delete(widget.rowId);
    // The persisted source is dead weight once its only row is gone. Safe
    // here because this row is being deleted outright — unlike the re-run
    // path, where the new row shares the same file.
    if (row != null) {
      await PageSource.removePersisted('${row['local_path']}');
    }
    widget.onChanged?.call();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = _row;
    final sync = widget.sync;
    final canReclassify = widget.models != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          row == null
              ? 'Capture'
              : DocumentTypeWire.fromWire('${row['kind']}')?.label ??
                    kindLabel('${row['kind']}'),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (canReclassify && row != null)
            IconButton(
              tooltip: 'Change document type',
              onPressed: _busy ? null : _reclassify,
              icon: const Icon(Icons.tune),
            ),
          if (row != null && sync != null)
            IconButton(
              tooltip: 'Retry sync',
              onPressed: _busy ? null : _retrySync,
              icon: const Icon(Icons.sync),
            ),
          if (row != null)
            IconButton(
              tooltip: 'Delete',
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (row != null)
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                DocumentTypeWire.fromWire('${row['kind']}')
                                        ?.label ??
                                    kindLabel('${row['kind']}'),
                                style: theme.textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            StatusChip(status: '${row['sync_status']}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatDateTime(
                            DateTime.tryParse('${row['created_at']}'),
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          reviewStatusLine('${row['sync_status']}'),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (row['error'] != null) ...[
                          const SizedBox(height: 10),
                          InlineBanner(
                            tone: BannerTone.error,
                            icon: Icons.error_outline,
                            message: '${row['error']}',
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (_error != null)
                  ErrorView(message: _error!)
                else ...[
                  _IdentificationCard(
                    envelope: _envelope,
                    onCorrect: canReclassify ? _reclassify : null,
                  ),
                  const SizedBox(height: 16),
                  _SourceCard(
                    path: '${_row!['local_path']}',
                    pageCount: _envelope?.pageCount,
                  ),
                  const SizedBox(height: 16),
                  if (_envelope != null)
                    ResultEnvelopeView(envelope: _envelope!),
                ],
                const SizedBox(height: 16),
                const InlineBanner(
                  tone: BannerTone.info,
                  icon: Icons.info_outline,
                  message:
                      'Structured context for review with your doctor. Not a '
                      'diagnosis.',
                ),
              ],
            ),
    );
  }

  static IconData _iconForMode(CaptureMode mode) => switch (mode) {
    CaptureMode.auto => Icons.auto_awesome,
    CaptureMode.labReport => Icons.science_outlined,
    CaptureMode.prescription => Icons.medication_outlined,
    CaptureMode.xray => Icons.image_outlined,
  };
}

/// The stored source file: format, and how pages are handled.
class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.path, this.pageCount});

  final String path;

  /// Pages in the source document, when the envelope recorded it.
  final int? pageCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = path.split(RegExp(r'[/\\]')).last;
    final sourceIsPdf = isPdf(path);

    return AppCard(
      child: Row(
        children: [
          Icon(
            sourceIsPdf
                ? Icons.picture_as_pdf_outlined
                : Icons.image_outlined,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pageCount != null && pageCount! > 1
                      ? '${fileTypeLabel(path)} · $pageCount pages'
                      : fileTypeLabel(path),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  sourceIsPdf
                      ? 'PDF — pages are rendered on-device before OCR.'
                      : 'Image — read directly on-device.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows how the type was decided, and offers a correction.
///
/// Detection is heuristic, so this is deliberately visible rather than hidden:
/// if it guessed wrong the user can fix it here instead of re-photographing.
class _IdentificationCard extends StatelessWidget {
  const _IdentificationCard({required this.envelope, this.onCorrect});

  final ResultEnvelope? envelope;
  final VoidCallback? onCorrect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detection = envelope?.detection;

    final auto = detection?.auto ?? false;
    final confidence = detection?.confidence;
    final reasons = detection?.reasons ?? const <String>[];
    final weak = auto && confidence != null && confidence < 0.6;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                weak ? Icons.help_outline : Icons.verified_outlined,
                size: 18,
                color: weak
                    ? AppColors.statusPendingLightFg
                    : AppColors.statusSyncedDarkFg,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  auto ? 'Auto-identified' : 'Type selected by you',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (confidence != null)
                Text(
                  '${(confidence * 100).round()}%',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Evidence: ${reasons.join(', ')}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (weak) ...[
            const SizedBox(height: 10),
            const InlineBanner(
              tone: BannerTone.warning,
              icon: Icons.warning_amber_outlined,
              message:
                  'Not much text was found, so this guess is less reliable. '
                  'Correct it if it is wrong.',
            ),
          ],
          if (onCorrect != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onCorrect,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('Change document type'),
            ),
          ],
        ],
      ),
    );
  }
}
