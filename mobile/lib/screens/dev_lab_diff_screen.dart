// Developer tool (Me > Developer): run the on-device lab engine and the
// server-side reference pipeline over the same file and show both structured
// results side by side.
//
// This is the fastest way to evaluate the on-device rule engine against real
// documents: any divergence between the two columns is a port/heuristic bug.
// It uploads the raw file, so it is explicitly developer-only and requires a
// configured backend URL and a signed-in session.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/patient_repository.dart';
import '../model_manager.dart';
import '../page_source.dart';
import '../schemas.dart';

class DevLabDiffScreen extends StatefulWidget {
  const DevLabDiffScreen({
    super.key,
    required this.models,
    required this.repository,
  });

  final ModelManager models;
  final PatientRepository repository;

  @override
  State<DevLabDiffScreen> createState() => _DevLabDiffScreenState();
}

class _DevLabDiffScreenState extends State<DevLabDiffScreen> {
  bool _busy = false;
  String _notice =
      'Pick a lab report image or PDF to run both engines on it.';
  Map<String, dynamic>? _local;
  Map<String, dynamic>? _localStructure;
  Map<String, dynamic>? _server;

  Future<void> _run() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: uploadExtensions,
    );
    if (picked == null) return;

    setState(() {
      _busy = true;
      _notice = 'Running both engines…';
      _local = null;
      _localStructure = null;
      _server = null;
    });

    final bytes = await picked.readAsBytes();
    var notice = 'Comparison ready.';

    try {
      final temp = await PageSource.writeTemp(bytes, picked.name);
      try {
        final preview = await widget.models.localLabPreview(source: temp);
        _local = preview['normalized'] as Map<String, dynamic>;
        _localStructure = preview['structure'] as Map<String, dynamic>;
      } finally {
        try {
          await temp.delete();
        } catch (_) {
          // Scratch file cleanup is best-effort.
        }
      }
    } catch (e) {
      notice = 'On-device engine failed: $e';
    }

    try {
      final response = await widget.repository.uploadLabReport(
        bytes: bytes,
        filename: picked.name,
      );
      _server = _serverDocument(response);
      if (_server == null) notice = 'Server returned no structured stage2.';
    } on ApiException catch (e) {
      notice = '${e.message} (server column unavailable)';
    } catch (e) {
      notice = 'Server upload failed: $e';
    }

    if (!mounted) return;
    setState(() {
      _notice = notice;
      _busy = false;
    });
  }

  /// The server envelope is `{..., result: {stage1, stage2, stage3, ...}}`;
  /// stage2 is the un-annotated structure comparable to the on-device output.
  Map<String, dynamic>? _serverDocument(Map<String, dynamic> response) {
    final result = response['result'];
    if (result is! Map) return null;
    for (final key in ['stage2', 'normalized', 'stage3']) {
      final value = result[key];
      if (value is Map) return value.map((k, v) => MapEntry('$k', v));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = _local;
    final server = _server;

    return Scaffold(
      appBar: AppBar(title: const Text('Lab engine diff')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_notice, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _run,
              icon: const Icon(Icons.compare_arrows, size: 18),
              label: Text(_busy ? 'Running…' : 'Pick a file and compare'),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _DiffPane(
                      title: 'On-device rule engine',
                      subtitle: local == null
                          ? 'not run'
                          : '${_testCount(local)} tests · '
                              '${_localStructure?['engine']} · '
                              'confidence ${_localStructure?['confidence']}',
                      body: local == null
                          ? ''
                          : '${prettyJson(local)}\n\n'
                              'structure:\n'
                              '${prettyJson(_localStructure ?? const {})}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DiffPane(
                      title: 'Server pipeline (/api/v2/lab-reports/upload)',
                      subtitle: server == null
                          ? 'not run'
                          : '${_testCount(server)} tests · stage2',
                      body: server == null ? '' : prettyJson(server),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static int _testCount(Map<String, dynamic> document) {
    final panels = document['panels'];
    if (panels is! List) return 0;
    var total = 0;
    for (final panel in panels) {
      if (panel is Map && panel['tests'] is List) {
        total += (panel['tests'] as List).length;
      }
    }
    return total;
  }
}

class _DiffPane extends StatelessWidget {
  const _DiffPane({
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final String title;
  final String subtitle;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Expanded(
              child: body.isEmpty
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      child: SelectableText(
                        body,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
