// On-device SLM runtime.
//
// ACTIVE: Qwen3-0.6B (Q3_K_S GGUF) via llama_cpp_dart — used for the summary
// context on the capture path and for on-demand insight tasks (explain /
// visit prep / translate). It stays a summariser/explainer: it is never a
// structurer and never emits flags. Lab structure comes from
// lib/lab/rule_engine.dart and all flagging/panic detection from
// lib/lab/clinical_engine.dart.
//
// LEGACY: the Falconsai T5-small ONNX summariser (`OnnxSummarizer`), retained
// but deprecated for A/B comparison and rollback — see docs/APP_SPIKE.md.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'schemas.dart';
import 't5_tokenizer.dart';

enum SlmBackend { llamaCpp, onnx }

/// Summarisation contract. Deliberately has no JSON/structuring entry point.
abstract class MedicalSummarizer {
  SlmBackend get backend;
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
/// Qwen3 is a causal instruction-tuned decoder: thinking is ON by default and
/// is suppressed by prefixing the user turn with `/no_think`. The assistant
/// turn is left open so the model continues from there; llama.cpp stops on the
/// model's EOS (`<|im_end|>`).
///
/// The prompt is built by hand rather than through llama_cpp_dart's
/// `ChatMLFormat`, because that formatter re-wraps any string it is given —
/// feeding it an already-complete ChatML prompt would double-wrap it.
String buildChatMlPrompt(
  String system,
  String user, {
  bool enableThinking = true,
}) {
  final effectiveUser = enableThinking ? user : '/no_think\n$user';
  return '<|im_start|>system\n$system<|im_end|>\n'
      '<|im_start|>user\n$effectiveUser<|im_end|>\n'
      '<|im_start|>assistant\n';
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
/// Task methods choose thinking vs non-thinking mode:
/// - thinking ON  → explanations, doctor-visit prep (quality matters)
/// - thinking OFF → summary, translation (`/no_think`, speed matters)
///
/// [modelPath] may be a real filesystem path or a bundled asset key
/// (`assets/models/…`). Assets are extracted once to application support
/// storage because llama.cpp needs a real file path — it cannot read inside
/// the APK.
class QwenSlmRuntime implements MedicalSummarizer {
  QwenSlmRuntime({
    required this.modelPath,
    this.maxNewTokens = 1024,
    this.completionTimeout = const Duration(seconds: 180),
    this.verbose = false,
  });

  final String modelPath;

  /// Hard cap on generated tokens (maps to `ContextParams.nPredict`).
  ///
  /// Large enough that a thinking block can close and still leave room for the
  /// answer within the 2048-token context; a cap that truncates mid-reasoning
  /// yields no answer at all once the block is stripped.
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

  @override
  SlmBackend get backend => SlmBackend.llamaCpp;

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
          // nBatch must therefore cover the longest prompt (a lab render is
          // ~400-1200 tokens), not a trickle. nUbatch stays at the usual
          // micro-batch size for prompt prefill.
          ..nBatch = 2048
          ..nUbatch = 512
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

  static int _threadCount() {
    final cores = Platform.numberOfProcessors;
    if (cores < 2) return 2;
    if (cores > 6) return 6;
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
  /// In thinking mode Qwen3 emits a `<think>` block before the answer, and how
  /// long that block runs varies with sampling. If it does not close inside
  /// [maxNewTokens] there is no answer yet, so retry once without thinking
  /// rather than handing the caller an empty string.
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
    if (answer.isNotEmpty) return answer;
    // An empty answer means the model emitted only a (possibly unclosed) think
    // block or echoed control tokens. Retry once in the other mode rather than
    // reporting the failure as "no summary".
    final retryThinking = !enableThinking;
    debugPrint(
      'QwenSlmRuntime: empty answer in '
      '${enableThinking ? 'thinking' : 'non-thinking'} mode — retrying with '
      '${retryThinking ? 'thinking enabled' : '/no_think'}',
    );
    return _runOnce(systemPrompt, userPrompt, enableThinking: retryThinking);
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
      'chars, thinkOpen=${raw.contains('<think>')}, '
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
      'model': 'qwen3-0.6b-q3_k_s',
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
      'model': 'qwen3-0.6b-q3_k_s',
      'latency_ms': DateTime.now().difference(started).inMilliseconds,
    };
  }

  /// Explain a single biomarker in 1-2 sentences for a patient.
  /// THINKING mode — the model reasons about what the test measures.
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
      enableThinking: true,
    );
  }

  /// Generate exactly 3 questions for the patient's next doctor visit.
  /// THINKING mode — synthesizes multiple flagged values.
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
      enableThinking: true,
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

/// ONNX Runtime path (WIRED): the Falconsai T5 summariser as quantized
/// encoder/decoder ONNX behind flutter_onnxruntime.
///
/// Assets (tracked build artifacts of the HF checkpoint, see
/// backend/scripts/export_t5_summarizer_onnx.py):
/// - assets/models/t5_encoder_q8.onnx + t5_decoder_q8.onnx (int8, ~94 MB)
/// - assets/models/t5_tokenizer.json (SentencePiece unigram, ported in
///   t5_tokenizer.dart — parity-pinned against HF vectors)
///
/// Runs the backend's `medical_summarize_service` contract on-device:
/// "summarize: [text]" in, greedy decode out, wrapped as
/// `{medical_summary, key_findings, ...}` context for doctor review.
/// Prescription inputs short-circuit to the deterministic builder, mirroring
/// the backend (structured NLP data, never generative output).
@Deprecated(
  'Replaced by QwenSlmRuntime. Kept for A/B comparison and rollback — '
  'see docs/APP_SPIKE.md.',
)
class OnnxSummarizer implements MedicalSummarizer {
  OnnxSummarizer({
    this.encoderAsset = 'assets/models/t5_encoder_q8.onnx',
    this.decoderAsset = 'assets/models/t5_decoder_q8.onnx',
    this.maxInputTokens = 128,
    this.maxNewTokens = 60,
    this.noRepeatNgramSize = 3,
  });

  final String encoderAsset;
  final String decoderAsset;
  final int maxInputTokens;
  final int maxNewTokens;

  /// Block a token if it would complete a repeated [noRepeatNgramSize]-gram,
  /// matching the backend's `no_repeat_ngram_size=3`.
  final int noRepeatNgramSize;

  OrtSession? _encoder;
  OrtSession? _decoder;
  T5Tokenizer? _tokenizer;

  @override
  SlmBackend get backend => SlmBackend.onnx;

  @override
  bool get isReady =>
      _encoder != null && _decoder != null && _tokenizer != null;

  @override
  Future<void> load() async {
    if (isReady) return;
    final ort = OnnxRuntime();
    final tokenizer = await T5Tokenizer.load();
    OrtSession? encoder;
    try {
      encoder = await ort.createSessionFromAsset(encoderAsset);
      final decoder = await ort.createSessionFromAsset(decoderAsset);
      _tokenizer = tokenizer;
      _encoder = encoder;
      _decoder = decoder;
    } catch (e) {
      // A failure between the two loads would otherwise strand a fully
      // allocated native encoder session (~35 MB) that nothing can reach.
      await encoder?.close();
      rethrow;
    }
  }

  /// Summarise already-structured text into context for doctor review. Output
  /// contract mirrors backend `medical_summarize_service` for non-prescription
  /// documents: {medical_summary, key_findings, ...}. Never emits flag fields.
  @override
  Future<Map<String, dynamic>> summarize(String text) => _run(text);

  /// The T5 checkpoint is a summariser, not a pharmacist: prescription
  /// instructions are summarised with the same "summarize: …" contract.
  @override
  Future<Map<String, dynamic>> summarizePrescription(String text) => _run(text);

  Future<Map<String, dynamic>> _run(String text) async {
    final started = DateTime.now();
    await load();
    final tokenizer = _tokenizer!;
    final encoder = _encoder!;
    final decoder = _decoder!;

    final inputIds = tokenizer.encode(
      'summarize: $text',
      maxLength: maxInputTokens,
    );
    final attn = List<int>.filled(inputIds.length, 1);
    final encHidden = await _runEncoder(encoder, inputIds, attn);
    try {
      final outIds = await _greedyDecode(decoder, encHidden, attn);
      final summary = tokenizer.decode(outIds);
      return {
        'document_type': 'summary_context',
        'medical_summary': summary,
        'key_findings': <String>[],
        'original_length': text.length,
        'summary_length': summary.length,
        // Decode steps drive on-device latency: each step re-runs the decoder
        // over the whole prefix (no KV cache) and transfers the full
        // [1, seq, vocab] logits tensor across the platform channel, so cost
        // grows with the square of this number.
        'decode_steps': outIds.isEmpty ? 0 : outIds.length - 1,
        'input_tokens': inputIds.length,
        'latency_ms': DateTime.now().difference(started).inMilliseconds,
      };
    } finally {
      await encHidden.dispose();
    }
  }

  Future<OrtValue> _runEncoder(
    OrtSession encoder,
    List<int> inputIds,
    List<int> attn,
  ) async {
    final ids = await OrtValue.fromList(Int64List.fromList(inputIds), [
      1,
      inputIds.length,
    ]);
    final mask = await OrtValue.fromList(Int64List.fromList(attn), [
      1,
      attn.length,
    ]);
    try {
      final outputs = await encoder.run({
        'input_ids': ids,
        'attention_mask': mask,
      });
      final hidden = outputs['hidden_states'] ?? outputs.values.first;
      // Keep alive: caller disposes after decode.
      return hidden;
    } finally {
      await ids.dispose();
      await mask.dispose();
    }
  }

  Future<List<int>> _greedyDecode(
    OrtSession decoder,
    OrtValue encHidden,
    List<int> attn,
  ) async {
    final mask = await OrtValue.fromList(Int64List.fromList(attn), [
      1,
      attn.length,
    ]);
    try {
      var decIds = <int>[0]; // T5 decoder_start_token_id (pad)
      for (var step = 0; step < maxNewTokens; step++) {
        final input = await OrtValue.fromList(Int64List.fromList(decIds), [
          1,
          decIds.length,
        ]);
        try {
          final outputs = await decoder.run({
            'input_ids': input,
            'encoder_hidden_states': encHidden,
            'encoder_attention_mask': mask,
          });
          final logitsValue = outputs['logits'] ?? outputs.values.first;
          // Read the row width from the tensor itself. This is the MODEL's
          // vocab (T5 pads it to 32128), which is NOT the tokenizer's piece
          // count (32100). Striding by the tokenizer size misaligned every
          // step's logits and produced incoherent output.
          final modelVocab = logitsValue.shape.last;
          final flat = await logitsValue.asFlattenedList();
          final lastOff = flat.length - modelVocab;
          // Mirror the backend's no_repeat_ngram_size=3. Full beam search
          // (num_beams=4, as the backend uses) is too expensive on device,
          // but banning repeated trigrams removes the degenerate looping this
          // greedy decode otherwise produces.
          final banned = bannedByRepeatNgram(decIds, noRepeatNgramSize);
          var best = 0;
          var bestScore = double.negativeInfinity;
          for (var i = 0; i < modelVocab; i++) {
            if (banned.contains(i)) continue;
            final s = (flat[lastOff + i] as num).toDouble();
            if (s > bestScore) {
              bestScore = s;
              best = i;
            }
          }
          decIds = [...decIds, best];
          if (best == _tokenizer!.eosId) break;
        } finally {
          await input.dispose();
        }
      }
      return decIds;
    } finally {
      await mask.dispose();
    }
  }

  /// Token ids that would complete a repeated [n]-gram if appended to [ids].
  ///
  /// Matches HF's NoRepeatNGramLogitsProcessor: take the trailing (n-1) tokens
  /// as the prefix, then ban whatever followed every earlier occurrence of that
  /// same prefix.
  @visibleForTesting
  static Set<int> bannedByRepeatNgram(List<int> ids, int n) {
    final banned = <int>{};
    if (n < 2 || ids.length < n) return banned;
    final prefixLen = n - 1;
    for (var i = 0; i + n <= ids.length; i++) {
      var match = true;
      for (var k = 0; k < prefixLen; k++) {
        // Compare ids[i..i+prefixLen) against the trailing prefix.
        if (ids[i + k] != ids[ids.length - prefixLen + k]) {
          match = false;
          break;
        }
      }
      if (match) banned.add(ids[i + n - 1]);
    }
    return banned;
  }

  @override
  Future<void> close() async {
    final encoder = _encoder;
    final decoder = _decoder;
    _encoder = null;
    _decoder = null;
    _tokenizer = null;
    await Future.wait([
      if (encoder != null) encoder.close(),
      if (decoder != null) decoder.close(),
    ]);
  }
}

/// Parse + validate raw summariser JSON output. Rejects Stage 3 flag fields and
/// anything that fails the agreed schemas; throws on invalid output so the
/// caller can fall back to the deterministic result. (The wired ONNX path
/// produces the map directly; this guards any future JSON-emitting runtime.)
Map<String, dynamic> parseSlmOutput(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('SLM output must be a JSON object');
  }
  final doc = Map<String, dynamic>.from(decoded);
  final problems = doc['document_type'] == 'prescription'
      ? validatePrescription(doc)
      : validateLabReport(doc);
  if (problems.isNotEmpty) {
    throw FormatException(
      'SLM output failed schema validation: ${problems.join('; ')}',
    );
  }
  return doc;
}
