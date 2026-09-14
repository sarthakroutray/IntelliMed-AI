// On-device SLM runtime.
//
// Qwen3-0.6B (Q4_0 GGUF) via llama_cpp_dart — used for the summary context on
// the capture path and for on-demand insight tasks (explain / visit prep /
// translate). It stays a summariser/explainer: it is never a structurer and
// never emits flags. Lab structure comes from lib/lab/rule_engine.dart and all
// flagging/panic detection from lib/lab/clinical_engine.dart.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Summarisation contract. Deliberately has no JSON/structuring entry point.
abstract class MedicalSummarizer {
  bool get isReady;
  Future<void> load();

  /// Compress already-structured text into summary context for review.
  Future<Map<String, dynamic>> summarize(String text);

  /// Compress already-extracted prescription instructions into summary
  /// context for review.
  Future<Map<String, dynamic>> summarizePrescription(String text);

  Future<void> close();
}

/// Build a single-turn Qwen3 ChatML prompt.
///
/// Qwen3 reasons by default, emitting a `<think>…</think>` block before the
/// answer. The `/no_think` text hint is not honoured reliably here — the model
/// still opened a reasoning block and burned the whole token budget without
/// closing it, leaving no answer. Thinking is therefore suppressed the way the
/// model was trained: prefill the assistant turn with an *empty, already
/// closed* think block, which leaves it to answer directly.
///
/// With thinking enabled the assistant turn is simply left open, so the model
/// continues from there; llama.cpp stops on the model's EOS (`<|im_end|>`).
///
/// The prompt is built by hand rather than through llama_cpp_dart's
/// `ChatMLFormat`, because that formatter re-wraps any string it is given —
/// feeding it an already-complete ChatML prompt would double-wrap it.
String buildChatMlPrompt(
  String system,
  String user, {
  bool enableThinking = true,
}) {
  final assistantOpen = enableThinking
      ? '<|im_start|>assistant\n'
      : '<|im_start|>assistant\n<think>\n\n</think>\n\n';
  return '<|im_start|>system\n$system<|im_end|>\n'
      '<|im_start|>user\n$user<|im_end|>\n'
      '$assistantOpen';
}

/// Strip a `<think>…</think>` reasoning block and echoed ChatML control tokens
/// from raw model output, returning only the answer text.
///
/// If the model opened a think block but never closed it (truncated by the
/// token cap or a timeout) there is no answer yet, so return empty rather than
/// leaking unfinished reasoning into the UI.
String stripThinking(String raw) {
  var text = raw;
  final close = text.indexOf('</think>');
  if (close >= 0) {
    text = text.substring(close + '</think>'.length);
  } else if (text.contains('<think>')) {
    return '';
  }
  return text
      .replaceAll('<|im_end|>', '')
      .replaceAll('<|im_start|>', '')
      .trim();
}

/// Qwen3-0.6B runtime on llama.cpp via the managed-isolate API
/// (`LlamaParent`), one prompt at a time.
///
/// Every task runs in NON-THINKING mode (a pre-filled, closed `<think>` block;
/// see [buildChatMlPrompt]). Qwen3's reasoning mode emits a long `<think>`
/// block before the answer, which on a CPU-only phone multiplies the wait.
///
/// [modelPath] may be a real filesystem path or a bundled asset key
/// (`assets/models/…`). Assets are extracted once to application support
/// storage because llama.cpp needs a real file path — it cannot read inside
/// the APK.
class QwenSlmRuntime implements MedicalSummarizer {
  QwenSlmRuntime({
    required this.modelPath,
    this.maxNewTokens = 512,
    this.completionTimeout = const Duration(seconds: 180),
    this.verbose = false,
  });

  final String modelPath;

  /// Hard cap on generated tokens (maps to `ContextParams.nPredict`).
  ///
  /// Kept small deliberately: on a CPU-only phone each token costs real time,
  /// and a cap that is large enough to hold a full reasoning block means every
  /// task pays for one. The tasks here ask for a few sentences, so the model
  /// stops on EOS long before this in practice; the cap only bounds the worst
  /// case (a runaway answer) so one slow task cannot stall the queue.
  final int maxNewTokens;

  /// Per-completion wall-clock budget; on expiry generation is stopped and
  /// whatever streamed so far is returned.
  final Duration completionTimeout;

  /// Whether llama.cpp's default logger stays enabled during load.
  ///
  /// Note: on Android this logger writes to stderr, which the platform drops,
  /// so it is only useful on desktop. llama_cpp_dart 0.2.2 never wires its own
  /// Dart log callback, so native messages are not visible in Flutter logs.
  final bool verbose;

  LlamaParent? _llama;
  bool _ready = false;

  /// How long to wait for a stopped generation's terminal isDone before
  /// reclaiming its slot.
  static const Duration _stopGrace = Duration(seconds: 5);

  /// The quant actually loaded, derived from the file name, so stored results
  /// record the truth instead of a hardcoded string.
  String get _modelLabel =>
      p.basenameWithoutExtension(modelPath).toLowerCase();

  @override
  bool get isReady => _ready;

  @override
  Future<void> load() async {
    if (_ready) return;
    final path = await _resolveModelPath(modelPath);
    final llama = LlamaParent(
      LlamaLoad(
        path: path,
        modelParams: ModelParams()
          ..nGpuLayers = 0 // CPU-only: portable across mobile GPUs/backends
          // main_gpu MUST be -1 on a CPU-only build. llama.cpp builds its
          // device list from GPU/IGPU/RPC devices only (CPU is handled
          // separately); with no GPU backend the list is empty, and the
          // default main_gpu = 0 then fails the range check in
          // llama_model_load_from_file_impl with
          //   "invalid value for main_gpu: 0 (available devices: 0)".
          // -1 clears the GPU list and selects the CPU path.
          ..mainGpu = -1,
        contextParams: ContextParams()
          ..nCtx = 2048 // bounded tasks; keeps resident RAM down
          // The whole prompt is decoded as ONE batch: llama_cpp_dart rejects
          // any prompt longer than nBatch with
          //   "Prompt tokens (N) > batch capacity (M)".
          // Input is capped (see ModelManager) so a modest batch covers it —
          // and keeping it modest matters for speed, because a context is
          // allocated per prompt and its compute buffers scale with nBatch.
          ..nBatch = 1536
          ..nUbatch = 256
          ..nPredict = maxNewTokens
          ..nThreads = _threadCount()
          ..nThreadsBatch = _threadCount(),
        samplingParams: SamplerParams()
          ..temp = 0.2 // near-deterministic for patient-facing text
          ..topK = 20
          ..topP = 0.9
          ..penaltyRepeat = 1.15,
        verbose: verbose,
      ),
    );
    try {
      await llama.init();
    } catch (e) {
      debugPrint('QwenSlmRuntime: llama.init() failed — $e');
      // Do not let a dispose failure mask the real load error.
      try {
        await llama.dispose();
      } catch (disposeError) {
        debugPrint(
          'QwenSlmRuntime: dispose after failed load threw — $disposeError',
        );
      }
      rethrow;
    }
    _llama = llama;
    _ready = true;
  }

  /// Worker threads for prompt prefill and token decode.
  ///
  /// Capped at 4: phones are big.LITTLE, and llama.cpp's per-op barrier means
  /// the slowest thread gates every step. Spreading work onto the little cores
  /// therefore makes generation slower, not faster, so we never ask for more
  /// than the typical count of performance cores.
  static int _threadCount() {
    final cores = Platform.numberOfProcessors;
    if (cores < 2) return 2;
    if (cores > 4) return 4;
    return cores;
  }

  /// Resolve an asset key to a real path, extracting it on first use.
  Future<String> _resolveModelPath(String path) async {
    final direct = File(path);
    if (await direct.exists()) return path;
    if (!path.startsWith('assets/')) {
      throw StateError(
        'SLM model not found at "$path". Provide a real file path or a '
        'bundled asset key (assets/models/…).',
      );
    }
    final support = await getApplicationSupportDirectory();
    final target = File(p.join(support.path, 'models', p.basename(path)));
    if (await target.exists()) return target.path;
    await target.parent.create(recursive: true);
    try {
      final data = await rootBundle.load(path);
      // Write to a temp file and rename so an interrupted ~372 MB extraction
      // can never leave a truncated file that a later launch would trust.
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await tmp.rename(target.path);
    } on FlutterError catch (e) {
      throw StateError(
        'Bundled SLM asset "$path" is missing from the build. Place the GGUF '
        'at mobile/$path (see mobile/tool/download_qwen3_gguf.ps1) and rebuild '
        '— original error: $e',
      );
    }
    return target.path;
  }

  /// Run one prompt and return the thinking-stripped answer.
  ///
  /// If a *thinking* run truncates before the answer (its block never closes)
  /// retry once without thinking — the cheap direction. The reverse is never
  /// done: a non-thinking task that came back empty must not escalate into a
  /// full reasoning pass, which is the slowest thing this model does.
  Future<String> _complete(
    String systemPrompt,
    String userPrompt, {
    bool enableThinking = true,
  }) async {
    final answer = await _runOnce(
      systemPrompt,
      userPrompt,
      enableThinking: enableThinking,
    );
    if (answer.isNotEmpty || !enableThinking) return answer;
    debugPrint(
      'QwenSlmRuntime: no answer within the token budget in thinking mode — '
      'retrying with /no_think',
    );
    return _runOnce(systemPrompt, userPrompt, enableThinking: false);
  }

  Future<String> _runOnce(
    String systemPrompt,
    String userPrompt, {
    required bool enableThinking,
  }) async {
    if (!_ready) throw StateError('QwenSlmRuntime not loaded');
    final llama = _llama!;
    final prompt = buildChatMlPrompt(
      systemPrompt,
      userPrompt,
      enableThinking: enableThinking,
    );

    // A dedicated scope per prompt. llama_cpp_dart keeps one long-lived
    // "default" slot that retains its KV cache and token position across
    // prompts (it only clears when the position is 0), so reusing it would
    // append every independent task to the previous conversation and
    // eventually overflow the context window. A scope owns a fresh slot, so
    // each prompt starts from an empty context.
    //
    // A scope allocates a second context, though, which can fail on a
    // memory-constrained device — and llama_cpp_dart reports that as a
    // *successful but empty* completion. Fall back once to the default slot so
    // the first prompt of a session still produces output.
    try {
      return await _generate(llama, prompt, useScope: true);
    } catch (e) {
      debugPrint(
        'QwenSlmRuntime: scoped generation failed ($e) — retrying on the '
        'default slot',
      );
      return _generate(llama, prompt, useScope: false);
    }
  }

  /// Send one prompt and return the thinking-stripped output.
  ///
  /// Waits on the completion event rather than only `waitForCompletion`: the
  /// package marks error responses `isDone`, so `waitForCompletion` resolves
  /// with no text and the failure would be read as an empty answer. The event
  /// carries `success`/`errorDetails`, so a failed generation is raised instead
  /// of silently dropped.
  Future<String> _generate(
    LlamaParent llama,
    String prompt, {
    required bool useScope,
  }) async {
    final LlamaScope? scope = useScope ? llama.getScope() as LlamaScope : null;
    final buffer = StringBuffer();
    final timer = Stopwatch()..start();
    final subscription = (scope?.stream ?? llama.stream).listen(
      buffer.write,
      onError: (Object _) {},
    );
    final done = Completer<CompletionEvent>();
    final completionSubscription = (scope?.completions ?? llama.completions)
        .listen((event) {
      if (!done.isCompleted) done.complete(event);
    });
    try {
      if (scope != null) {
        await scope.sendPrompt(prompt);
      } else {
        await llama.sendPrompt(prompt);
      }
      try {
        final event = await done.future.timeout(completionTimeout);
        if (!event.success) {
          throw StateError(
            'generation failed: ${event.errorDetails ?? 'unknown error'}',
          );
        }
      } on TimeoutException {
        // Stop the child so the model is free for the next queued task; it
        // still emits a terminal completion once the loop breaks, and the slot
        // must not be freed before then.
        await llama.stop();
        try {
          final event = await done.future.timeout(_stopGrace);
          if (!event.success) {
            throw StateError(
              'generation failed after stop: '
              '${event.errorDetails ?? 'unknown error'}',
            );
          }
        } catch (_) {
          // Best effort — return whatever streamed so far.
        }
      }
    } finally {
      await subscription.cancel();
      await completionSubscription.cancel();
      if (scope != null) {
        try {
          await scope.dispose();
        } catch (e) {
          // Never let slot cleanup mask a generation error.
          debugPrint('QwenSlmRuntime: scope dispose failed — $e');
        }
      }
    }
    final raw = buffer.toString();
    debugPrint(
      'QwenSlmRuntime: ${useScope ? 'scope' : 'default'} raw=${raw.length} '
      'chars in ${timer.elapsedMilliseconds} ms, '
      'thinkOpen=${raw.contains('<think>')}, '
      'thinkClose=${raw.contains('</think>')}',
    );
    return stripThinking(raw);
  }

  @override
  Future<Map<String, dynamic>> summarize(String text) async {
    final started = DateTime.now();
    final summary = await _complete(
      'You are a medical document normalisation engine. Summarize the '
      'following medical text in 2-3 sentences. Extract key findings as a '
      'bullet list. Do NOT interpret or diagnose. Output plain text, not JSON.',
      'Medical text:\n$text',
      enableThinking: false, // fast summary, not deep reasoning
    );
    return {
      'document_type': 'summary_context',
      'medical_summary': summary,
      'key_findings': _extractBullets(summary),
      'original_length': text.length,
      'summary_length': summary.length,
      'model': _modelLabel,
      'latency_ms': DateTime.now().difference(started).inMilliseconds,
    };
  }

  /// Summarise already-extracted prescription items for a patient.
  /// NON-THINKING mode — a short, faithful restatement, not reasoning.
  @override
  Future<Map<String, dynamic>> summarizePrescription(String text) async {
    final started = DateTime.now();
    final summary = await _complete(
      'You are a pharmacist assistant. Write a short, clear summary of the '
      'prescription below for the patient. Cover, when the document states '
      'it: (1) what the prescription is for, only if a reason or condition is '
      'written; (2) each medicine with its exact dose, how often to take it, '
      'and how long; (3) any other instructions written on the document, such '
      'as timing (before or after food), tests, or follow-up. Repeat the '
      'numbers exactly as written. Use only details present in the text — '
      'never invent a medicine, dose, or reason. Do not give medical advice '
      'or suggest changes. Output 3-5 sentences of plain text, not JSON.',
      'Prescription:\n$text',
      enableThinking: false,
    );
    return {
      'document_type': 'prescription_summary',
      'medical_summary': summary,
      'key_findings': _extractBullets(summary),
      'original_length': text.length,
      'summary_length': summary.length,
      'model': _modelLabel,
      'latency_ms': DateTime.now().difference(started).inMilliseconds,
    };
  }

  /// Condense a batch of record cards into a short factual note — the map step
  /// of the multi-record patient summary. NON-THINKING (faithful, not reasoned).
  Future<String> summarizeRecordBatch(String text) => _complete(
    'You are a medical writing assistant. Condense the following medical '
    'records into a short factual note for a doctor. Keep every abnormal or '
    'critical value, every medicine with its dose, and the dates. Use only '
    'what is in the records — never add a result, medicine or reason — and do '
    'not give advice. Output plain text, not JSON.',
    'Records:\n$text',
    enableThinking: false,
  );

  /// Final doctor-facing patient summary built from record cards, or from the
  /// per-batch notes when the records had to be chunked. NON-THINKING.
  Future<String> summarizePatient(String text) => _complete(
    'You are a medical writing assistant preparing a short hand-over summary '
    'for a doctor from a patient\'s records. Write 3-6 short paragraphs in '
    'plain language covering: what kinds of records this covers and their '
    'date range; the important abnormal or critical results with their '
    'values; the medicines currently prescribed with doses; any patterns or '
    'changes over time the records support; and what a doctor may want to '
    'review. Use only the facts given — never invent a result, medicine or '
    'reason, and do not conclude what condition the patient has. Do not give '
    'treatment advice. Output plain text, not JSON.',
    'Records:\n$text',
    enableThinking: false,
  );

  /// Explain a single biomarker in 1-2 sentences for a patient.
  /// NON-THINKING — a short factual restatement, not reasoning. Reasoning mode
  /// multiplies the token count (and therefore the wait) for no gain here.
  Future<String> explainBiomarker({
    required String testName,
    required String value,
    required String unit,
    String? direction,
  }) {
    final dirText = direction != null ? ' ($direction)' : '';
    return _complete(
      'You are a patient health educator. Explain the medical test result in '
      '1-2 simple sentences a patient can understand. Do NOT give medical '
      'advice or suggest treatment. Do NOT use the word "diagnos". Just explain '
      'what the test measures and what the result level generally indicates.',
      '$testName: $value $unit$dirText',
      enableThinking: false,
    );
  }

  /// Generate exactly 3 questions for the patient's next doctor visit.
  /// NON-THINKING — the flagged values are already listed for the model.
  Future<String> doctorVisitPrep({
    required List<Map<String, dynamic>> flaggedTests,
  }) {
    final listing = flaggedTests
        .map((t) =>
            '- ${t['test_name'] ?? t['testName']}: '
            '${t['value']} ${t['unit'] ?? ''} '
            '(${t['direction'] ?? 'flagged'})')
        .join('\n');
    return _complete(
      'You are a patient health educator preparing a patient for their next '
      'doctor appointment. Given the flagged lab results, generate exactly 3 '
      'specific questions the patient should ask their doctor. Number them 1-3. '
      'Keep each question to 1 sentence. Do NOT give medical advice or suggest '
      'treatment.',
      'My flagged lab results:\n$listing',
      enableThinking: false,
    );
  }

  /// Translate medication instructions into [targetLanguage].
  /// NON-THINKING mode — translation is pattern-matching, not reasoning.
  Future<String> translateInstructions({
    required String instructions,
    required String targetLanguage,
  }) {
    return _complete(
      'You are a medical translator. Translate the following medication '
      'instructions into $targetLanguage. Translate ONLY the instructions, keep '
      'drug names in English. Be precise with dosage numbers and timing.',
      instructions,
      enableThinking: false,
    );
  }

  static List<String> _extractBullets(String text) {
    return text
        .split('\n')
        .where((l) => l.trim().startsWith('-') || l.trim().startsWith('•'))
        .map((l) => l.replaceFirst(RegExp(r'^[\s\-•]+'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  @override
  Future<void> close() async {
    final llama = _llama;
    _llama = null;
    _ready = false;
    await llama?.dispose();
  }
}
