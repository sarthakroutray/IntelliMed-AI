// Medical summariser runtime: T5 on ONNX (wired) vs llama_cpp_dart GGUF
// (future). Both sit behind one interface so the spike (docs/APP_SPIKE.md) can
// A/B them without touching call sites.
//
// The wired checkpoint is the one the backend uses as its OCR-text summariser:
// Falconsai/medical_summarization (T5-small, 60M) behind the `summarize: `
// prefix, exported to quantized encoder/decoder ONNX. It is a *summariser* — it
// compresses prose. It is not a structurer: lab-report structure comes from the
// deterministic rule engine (lib/lab/rule_engine.dart). The interface below
// makes "ask T5 to emit structure" unrepresentable rather than discouraged.
//
// Output is {medical_summary, key_findings, ...} context for doctor review.
// Never flag fields (rejected at parse time).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

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

  Future<void> close();
}

/// llama.cpp path (future): GGUF SLM via llama_cpp_dart isolate API. Kept as
/// the documented alternative in docs/APP_SPIKE.md; not wired since the
/// summariser role is already filled by the T5 ONNX path above.
class LlamaCppRuntime implements MedicalSummarizer {
  LlamaCppRuntime({required this.modelPath});

  final String modelPath;
  bool _ready = false;

  @override
  SlmBackend get backend => SlmBackend.llamaCpp;

  @override
  bool get isReady => _ready;

  @override
  Future<void> load() async {
    _ready = false;
    debugPrint(
      'LlamaCppRuntime: not wired — T5 ONNX path is active ($modelPath)',
    );
  }

  @override
  Future<Map<String, dynamic>> summarize(String text) {
    throw StateError('LlamaCppRuntime not wired — use OnnxSummarizer');
  }

  @override
  Future<void> close() async {}
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
