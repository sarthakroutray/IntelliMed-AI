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

    // Active SLM: Qwen3-0.6B. Loaded through the real path so this number
    // reflects what a capture or an insight request pays on first use.
    final qwen = QwenSlmRuntime(modelPath: widget.models.slmGgufAsset);
    final qwenStart = DateTime.now();
    var qwenReady = false;
    String qwenNote = '';
    try {
      await qwen.load();
      qwenReady = qwen.isReady;
    } catch (e) {
      qwenNote = ' — error: $e';
    }
    lines.add(
      'slm qwen3-0.6b load: '
      '${DateTime.now().difference(qwenStart).inMilliseconds} ms '
      '(ready=$qwenReady)$qwenNote',
    );
    await qwen.close();

    // Legacy T5 ONNX path stays measurable for A/B comparison.
    // ignore: deprecated_member_use_from_same_package
    final onnx = OnnxSummarizer();
    String onnxNote = '';
    try {
      await onnx.load();
    } catch (e) {
      onnxNote = ' — error: $e';
    }
    lines.add('slm t5-q8 onnx (legacy) ready=${onnx.isReady}$onnxNote');
    // Release the native T5 sessions this run created. Without this, every tap
    // of "Run measurements" leaked another pair of sessions.
    await onnx.close();
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
      // Reuse the shared runtime rather than constructing a second one: this
      // reflects what a capture or an insight request pays on first use.
      final runtime = await widget.models.loadSlm(SlmBackend.llamaCpp);
      loadMs = sw.elapsedMilliseconds;
      ready = runtime.isReady;
      if (ready && runtime is QwenSlmRuntime) {
        final out = await runtime.explainBiomarker(
          testName: 'Hemoglobin',
          value: '11.2',
          unit: 'g/dL',
          direction: 'low',
        );
        probe = out.isEmpty ? '(empty output)' : out;
      }
    } catch (e) {
      probe = 'failed: $e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status =
          'qwen3-0.6b: ready=$ready (load $loadMs ms)\n'
          'live probe: $probe\n'
          'Decision: Qwen3-0.6B is the on-device SLM (llama_cpp_dart). '
          'See docs/APP_SPIKE.md.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Spike result: Qwen3-0.6B (Q3_K_S GGUF) runs on-device via '
          'llama_cpp_dart and powers the summary context and AI insights. '
          'The button below loads it and runs a live explanation probe.',
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
