import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'copy.dart';
import 'model_manager.dart';
import 'store.dart';

/// Capture tab: camera/gallery pick for prescriptions, lab reports, X-rays.
/// Handwriting capture is not offered as a path — printed documents only,
/// flagged in the UI as a scope note.
class CaptureTab extends StatefulWidget {
  const CaptureTab({
    super.key,
    required this.models,
    required this.onResultsChanged,
  });

  final ModelManager models;
  final VoidCallback onResultsChanged;

  @override
  State<CaptureTab> createState() => _CaptureTabState();
}

class _CaptureTabState extends State<CaptureTab> {
  final _picker = ImagePicker();
  String _kind = 'lab_report';
  String _status = 'Pick a document to begin on-device processing.';
  bool _busy = false;

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _busy = true;
      _status = 'Reading image…';
    });
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 92);
      if (picked == null) {
        setState(() {
          _status = 'No image selected.';
          _busy = false;
        });
        return;
      }
      setState(() => _status = 'Running on-device inference (queued)…');
      final Map<String, dynamic> envelope;
      if (_kind == 'xray') {
        envelope = await widget.models.processXray(image: File(picked.path));
      } else {
        envelope = await widget.models.processDocument(
          image: File(picked.path),
          kind: _kind,
        );
      }
      setState(() {
        _status =
            'Structured context ready (${envelope['latency_ms']} ms, ${envelope['engine']}) — saved ${reviewStatusLine('pending')}.';
        _busy = false;
      });
      widget.onResultsChanged();
    } catch (e) {
      setState(() {
        _status = 'Could not process image: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(patternListCaption),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'lab_report', label: Text('Lab report')),
            ButtonSegment(value: 'prescription', label: Text('Prescription')),
            ButtonSegment(value: 'xray', label: Text('X-ray')),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Camera'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_busy) const LinearProgressIndicator(),
        Text(_status),
        const SizedBox(height: 8),
        const Text(
          'Scope note: printed documents only — handwriting OCR is future work '
          'and is not attempted on-device.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

/// Results tab: local store contents with sync status chips.
class ResultsTab extends StatefulWidget {
  const ResultsTab({super.key, required this.refreshToken});

  final int refreshToken;

  @override
  State<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends State<ResultsTab> {
  List<Map<String, Object?>> _rows = [];
  int _seenToken = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeRefresh();
  }

  @override
  void didUpdateWidget(covariant ResultsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRefresh();
  }

  Future<void> _maybeRefresh() async {
    if (_seenToken == widget.refreshToken) return;
    _seenToken = widget.refreshToken;
    final store = await ResultStore.instance();
    final rows = await store.all();
    if (mounted) setState(() => _rows = rows);
  }

  Color _chipColor(String status) {
    switch (status) {
      case 'synced':
        return Colors.green.shade100;
      case 'failed':
        return Colors.red.shade100;
      default:
        return Colors.amber.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_rows.isEmpty) {
      return const Center(
        child: Text('No results yet — capture a document first.'),
      );
    }
    return ListView.builder(
      itemCount: _rows.length,
      itemBuilder: (context, i) {
        final row = _rows[i];
        final status = '${row['sync_status']}';
        return ListTile(
          leading: Chip(
            label: Text(status),
            backgroundColor: _chipColor(status),
          ),
          title: Text('${row['kind']} — row ${row['id']}'),
          subtitle: Text(reviewStatusLine(status)),
        );
      },
    );
  }
}
