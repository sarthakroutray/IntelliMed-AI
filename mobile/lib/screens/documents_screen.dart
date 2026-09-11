import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../api/patient_repository.dart';
import '../copy.dart';
import '../formatting.dart';
import '../page_source.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/feedback.dart';
import '../widgets/filter_chips.dart';
import 'document_detail_screen.dart';

/// Server-side document management: upload, list, analyze, delete.
///
/// Uploading sends the RAW file to the backend (which stores it in Supabase and
/// runs OCR/CV/NLP/T5). It is always an explicit user action — never automatic —
/// because it moves PHI off the device. This is the one place the app handles
/// raw documents; the Capture tab stays structured-results-only.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({
    super.key,
    required this.repository,
    required this.refreshToken,
    required this.onChanged,
  });

  final PatientRepository repository;
  final int refreshToken;
  final VoidCallback onChanged;

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

enum _DocFilter { all, analysed, pending }

class _DocumentsScreenState extends State<DocumentsScreen> {
  static const _maxUploadMb = 10;

  final _picker = ImagePicker();
  final _search = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _notice;
  List<DocumentSummary> _documents = const [];
  _DocFilter _filter = _DocFilter.all;
  int _seenToken = -1;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void didUpdateWidget(covariant DocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshToken != _seenToken) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
      final docs = await widget.repository.listDocuments();
      if (!mounted) return;
      setState(() {
        _documents = docs;
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

  List<DocumentSummary> get _visible {
    final query = _search.text.trim().toLowerCase();
    return _documents.where((d) {
      final matchesQuery =
          query.isEmpty || d.filename.toLowerCase().contains(query);
      final matchesFilter = switch (_filter) {
        _DocFilter.all => true,
        _DocFilter.analysed => d.hasAnalysis,
        _DocFilter.pending => !d.hasAnalysis,
      };
      return matchesQuery && matchesFilter;
    }).toList();
  }

  Future<void> _uploadBytes({
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) async {
    final sizeMb = bytes.length / (1024 * 1024);
    if (sizeMb > _maxUploadMb) {
      setState(() {
        _notice =
            'That file is ${sizeMb.toStringAsFixed(1)} MB. The limit is '
            '$_maxUploadMb MB.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _notice =
          'Uploading and analysing… this runs OCR and AI on the server and can '
          'take a minute.';
    });
    try {
      await widget.repository.uploadDocument(
        bytes: bytes,
        filename: filename,
        contentType: contentType,
      );
      await _load();
      widget.onChanged();
      if (mounted) {
        setState(() => _notice = 'Uploaded. The document is now on the server.');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _notice = e.kind == ApiErrorKind.tooLarge
              ? 'The server rejected that file as too large.'
              : e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFile() async {
    // file_picker 12: static `pickFile` for a single file, and bytes are read
    // from the PlatformFile (the old `withData` flag is deprecated).
    // `uploadExtensions` is the set the backend's OpenDataLoader/EasyOCR
    // pipeline documents as readable — wider than that and the server would
    // fail after the file had already been sent.
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: uploadExtensions,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _uploadBytes(bytes: bytes, filename: file.name);
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 92);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    await _uploadBytes(
      bytes: bytes,
      filename: picked.name,
      contentType: 'image/jpeg',
    );
  }

  Future<void> _analyze(DocumentSummary doc) async {
    setState(() {
      _busy = true;
      _notice = 'Running analysis on the server… this can take a minute.';
    });
    try {
      await widget.repository.analyzeDocument(doc.id);
      await _load();
      widget.onChanged();
      if (mounted) setState(() => _notice = 'Analysis complete.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(DocumentSummary doc) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete this document?',
      message:
          '"${doc.filename}" and its analysis will be removed from the server. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await widget.repository.deleteDocument(doc.id);
      await _load();
      widget.onChanged();
      if (mounted) setState(() => _notice = 'Document deleted.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _notice = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = _visible;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Documents', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Files stored on the server, with AI analysis. Uploading sends the '
            'original file to your account.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Upload on its own full-width row, camera/gallery below as
                // equal halves: a single row of all three is too tight at
                // 320dp and breaks with larger text.
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Upload file'),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera, size: 18),
                        label: const Text('Camera'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library, size: 18),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${uploadExtensions.map((e) => e.toUpperCase()).join(', ')} • '
                  'up to ${_maxUploadMb}MB',
                  style: theme.textTheme.bodySmall,
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: const LinearProgressIndicator(minHeight: 5),
                  ),
                ],
              ],
            ),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 12),
            InlineBanner(
              tone: BannerTone.info,
              icon: Icons.info_outline,
              message: _notice!,
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              hintText: 'Search by filename',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          FilterChips<_DocFilter>(
            values: _DocFilter.values,
            selected: _filter,
            labelOf: (f) => switch (f) {
              _DocFilter.all => 'All',
              _DocFilter.analysed => 'Analyzed',
              _DocFilter.pending => 'Pending',
            },
            countOf: (f) => switch (f) {
              _DocFilter.all => _documents.length,
              _DocFilter.analysed =>
                _documents.where((d) => d.hasAnalysis).length,
              _DocFilter.pending =>
                _documents.where((d) => !d.hasAnalysis).length,
            },
            onSelected: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const LoadingView(message: 'Loading documents…')
          else if (_error != null)
            ErrorView(message: _error!, onRetry: _load)
          else if (visible.isEmpty)
            EmptyState(
              icon: Icons.folder_outlined,
              title: _documents.isEmpty
                  ? 'No documents yet'
                  : 'Nothing matches',
              message: _documents.isEmpty
                  ? 'Upload a medical document to store it and run AI analysis.'
                  : 'Try a different search or filter.',
            )
          else
            for (final doc in visible)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DocumentTile(
                  doc: doc,
                  busy: _busy,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DocumentDetailScreen(
                          repository: widget.repository,
                          documentId: doc.id,
                          filename: doc.filename,
                        ),
                      ),
                    );
                    await _load();
                    widget.onChanged();
                  },
                  onAnalyze: () => _analyze(doc),
                  onDelete: () => _delete(doc),
                ),
              ),
          const SizedBox(height: 12),
          Text(
            'Analysis is assistive context for review, not a diagnosis.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
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

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.doc,
    required this.busy,
    required this.onTap,
    required this.onAnalyze,
    required this.onDelete,
  });

  final DocumentSummary doc;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onAnalyze;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(_iconFor(doc), size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.filename,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  formatDateTime(doc.uploadedAt),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                _AnalysisChip(analysed: doc.hasAnalysis),
              ],
            ),
          ),
          PopupMenuButton<String>(
            enabled: !busy,
            onSelected: (value) {
              if (value == 'analyze') onAnalyze();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'analyze',
                child: Text(doc.hasAnalysis ? 'Re-analyze' : 'Analyze'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(DocumentSummary doc) {
    final name = doc.filename.toLowerCase();
    if (name.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (doc.detectedType == 'xray') return Icons.image_outlined;
    if (doc.detectedType == 'prescription') return Icons.medication_outlined;
    return Icons.description_outlined;
  }
}

class _AnalysisChip extends StatelessWidget {
  const _AnalysisChip({required this.analysed});

  final bool analysed;

  @override
  Widget build(BuildContext context) {
    final color = analysed
        ? AppColors.statusSyncedDarkFg
        : AppColors.statusPendingLightFg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        analysed ? 'ANALYSIS READY' : 'PENDING ANALYSIS',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
