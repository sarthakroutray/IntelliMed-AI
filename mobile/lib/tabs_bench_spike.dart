import 'package:flutter/material.dart';

import 'cnn_ocr.dart';
import 'lab/rule_engine.dart';
import 'lab/stage1_model.dart';
import 'model_manager.dart';
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
    final doc = buildLabDocument(
      LabStage1(
        extractionEngine: 'mlkit-lines-only',
        text: _sample.text,
        elements: const [],
        tables: const [],
        warnings: const [],
      ),
    );
    final normMs = DateTime.now().difference(normStart).inMilliseconds;
    final problems = validateLabReport(doc.toJson());
    lines.add(
      'rule engine (line fallback): $normMs ms, '
      'schema=${problems.isEmpty ? 'OK' : problems.join('; ')}',
    );

    final llama = LlamaCppRuntime(modelPath: widget.models.slmGgufAsset);
    await llama.load();
    final onnx = OnnxSummarizer();
    await onnx.load();
    lines.add(
      'slm t5-q8 onnx ready=${onnx.isReady}; '
      'llama_cpp_dart ready=${llama.isReady} (future path)',
    );
    // Release the ~94 MB of native T5 sessions this run created. Without
    // this, every tap of "Run measurements" leaked another pair of sessions
    // and would eventually OOM the device.
    await onnx.close();
    await llama.close();
    lines.add(
      'inference queue max depth observed: ${widget.models.queue.maxDepthObserved}',
    );
    lines.add('online=${await V2Sync.isOnline()}');
    // Device-test triage: which backend is this build actually pointed at, and
    // does it have a usable token? A wrong API_BASE_URL is the most common
    // cause of "cannot reach the server" during device testing.
    lines.add('backend=${widget.sync.baseUrl}');
    final hasToken =
        widget.sync.token != null && widget.sync.token!.isNotEmpty;
    lines.add('auth=${hasToken ? 'token set' : 'no token (sign in required)'}');
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
  bool _busy = false;

  Future<void> _runSpike() async {
    setState(() {
      _busy = true;
      _status = 'Running on-device spike…';
    });
    final sw = Stopwatch()..start();
    String probe = 'not run';
    var ready = false;
    var loadMs = 0;
    try {
      // Reuse the shared summariser rather than constructing a second one:
      // this reflects exactly what the capture pipeline runs and avoids
      // holding two ~94 MB copies of the T5 sessions at once.
      final t5 = await widget.models.loadSlm(SlmBackend.onnx);
      loadMs = sw.elapsedMilliseconds;
      ready = t5.isReady;
      if (ready && t5 is OnnxSummarizer) {
        final out = await t5.summarize(
          'The patient was prescribed Amoxicillin 500 mg twice daily for 7 days.',
        );
        probe = '${out['medical_summary']} (${out['latency_ms']} ms)';
      }
    } catch (e) {
      probe = 'failed: $e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status =
          't5-q8 onnx: ready=$ready (load $loadMs ms)\n'
          'live probe: $probe\n'
          'Decision: T5 summariser wired (same checkpoint as backend). '
          'See docs/APP_SPIKE.md.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Spike result: T5 summariser (same checkpoint as the backend) '
          'runs on-device via flutter_onnxruntime. The button below loads it '
          'and runs a live summarisation probe.',
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy ? null : _runSpike,
          child: const Text('Run spike probe'),
        ),
        const SizedBox(height: 8),
        SelectableText(_status),
      ],
    );
  }
}
