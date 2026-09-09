import 'package:flutter/material.dart';

import 'cnn_ocr.dart';
import 'model_manager.dart';
import 'normalize.dart';
import 'schemas.dart';
import 'slm_runtime.dart';
import 'sync.dart';

/// Bench tab: real-device measurement harness.
///
/// Records (a) eager vs lazy CNN load latency, (b) normalization latency on a
/// pasted OCR sample, (c) SLM backend readiness, (d) queue depth observed.
/// No arbiter work begins until these numbers exist — see docs/MEMORY_REPORT.md.
class BenchTab extends StatefulWidget {
  const BenchTab({super.key, required this.models, required this.sync});

  final ModelManager models;
  final V2Sync sync;

  @override
  State<BenchTab> createState() => _BenchTabState();
}

class _BenchTabState extends State<BenchTab> {
  final _sample = TextEditingController(
    text: 'Hemoglobin 11.2 g/dL 13.0-17.0\nWBC 7.5 4.0-11.0\nGlucose 98 mg/dL',
  );
  String _report = 'No measurements yet.';
  bool _busy = false;

  Future<void> _runBench() async {
    setState(() {
      _busy = true;
      _report = 'Measuring…';
    });
    final lines = <String>[];
    final eagerStart = DateTime.now();
    final eager = await CnnClassifier.load(
      modelAsset: widget.models.cnnAsset,
      backend: CnnBackend.onnx,
    );
    lines.add(
      'cnn (onnx resnet50) eager load: ${DateTime.now().difference(eagerStart).inMilliseconds} ms '
      '(ready=${eager.isReady})',
    );
    await eager.close();
    final lazyStart = DateTime.now();
    final lazy = await CnnClassifier.load(
      modelAsset: widget.models.cnnAsset,
      lazy: true,
      backend: CnnBackend.onnx,
    );
    lines.add(
      'cnn lazy handle: ${DateTime.now().difference(lazyStart).inMilliseconds} ms '
      '(ready=${lazy.isReady}; first-classify timing recorded on use)',
    );
    await lazy.close();
    final normStart = DateTime.now();
    final doc = normalizeLabText(_sample.text);
    final normMs = DateTime.now().difference(normStart).inMilliseconds;
    final problems = validateLabReport(doc);
    lines.add(
      'deterministic normalization: $normMs ms, '
      'schema=${problems.isEmpty ? 'OK' : problems.join('; ')}',
    );

    final llama = LlamaCppRuntime(modelPath: widget.models.slmGgufAsset);
    await llama.load();
    final onnx = OnnxSlmRuntime();
    await onnx.load();
    lines.add(
      'slm t5-q8 onnx ready=${onnx.isReady}; '
      'llama_cpp_dart ready=${llama.isReady} (future path)',
    );
    lines.add(
      'inference queue max depth observed: ${widget.models.queue.maxDepthObserved}',
    );
    lines.add('online=${await V2Sync.isOnline()}');
    setState(() {
      _report = lines.join('\n');
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Paste OCR sample text, then run the harness on-device.'),
        const SizedBox(height: 8),
        TextField(controller: _sample, maxLines: 5),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _runBench,
          child: const Text('Run measurements'),
        ),
        const SizedBox(height: 8),
        SelectableText(_report),
      ],
    );
  }
}

/// Spike tab: documents the llama_cpp_dart vs ONNX decision inputs and shows
/// live readiness. The written decision lives in docs/APP_SPIKE.md — this tab
/// only surfaces the current state on this device.
class SpikeTab extends StatefulWidget {
  const SpikeTab({super.key, required this.models});

  final ModelManager models;

  @override
  State<SpikeTab> createState() => _SpikeTabState();
}

class _SpikeTabState extends State<SpikeTab> {
  String _status = 'Spike not run on this device yet.';

  Future<void> _runSpike() async {
    final t5 = OnnxSlmRuntime();
    final sw = Stopwatch()..start();
    await t5.load();
    final t5Ms = sw.elapsedMilliseconds;
    String probe = 'not run';
    if (t5.isReady) {
      try {
        final out = await t5.standardizeText(
          'The patient was prescribed Amoxicillin 500 mg twice daily for 7 days.',
        );
        probe = '${out['medical_summary']} (${out['latency_ms']} ms)';
      } catch (e) {
        probe = 'failed: $e';
      }
    }
    setState(() {
      _status =
          't5-q8 onnx: ready=${t5.isReady} (load $t5Ms ms)\n'
          'live probe: $probe\n'
          'Decision: T5 standardizer wired (same checkpoint as backend). '
          'See docs/APP_SPIKE.md.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Spike result: T5 standardizer (same checkpoint as the backend) '
          'runs on-device via flutter_onnxruntime. The button below loads it '
          'and runs a live standardization probe.',
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _runSpike,
          child: const Text('Run spike probe'),
        ),
        const SizedBox(height: 8),
        SelectableText(_status),
      ],
    );
  }
}
