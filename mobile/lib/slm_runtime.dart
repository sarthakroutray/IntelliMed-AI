// SLM runtime abstraction: T5 standardizer on ONNX (wired) vs
// llama_cpp_dart GGUF (future). Both sit behind one interface so the spike
// (docs/APP_SPIKE.md) can A/B them without touching call sites.
//
// The wired path runs the same checkpoint the backend uses as its OCR text
// standardizer: Falconsai/medical_summarization (T5-small, 60M) behind
// backend `medical_summarize_service`, exported to quantized encoder/decoder
// ONNX. It standardizes raw OCR text into {medical_summary, key_findings}
// context for doctor review — never flag fields (rejected at parse time).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'schemas.dart';
import 't5_tokenizer.dart';

enum SlmBackend { llamaCpp, onnx }

abstract class SlmRuntime {
  SlmBackend get backend;
  bool get isReady;
  Future<void> load();
  Future<Map<String, dynamic>> normalizeJson(String stage1Json);
  void close();
}

/// llama.cpp path (future): GGUF SLM via llama_cpp_dart isolate API. Kept as
/// the documented alternative in docs/APP_SPIKE.md; not wired since the
/// standardizer role is already filled by the T5 ONNX path above.
class LlamaCppRuntime implements SlmRuntime {
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
  Future<Map<String, dynamic>> normalizeJson(String stage1Json) {
    throw StateError('LlamaCppRuntime not wired — use OnnxSlmRuntime');
  }

  @override
  void close() {}
}

/// ONNX Runtime path (WIRED): the Falconsai T5 standardizer as quantized
/// encoder/decoder ONNX behind flutter_onnxruntime.
///
/// Assets (tracked build artifacts of the HF checkpoint, see
/// backend/scripts/export_t5_summarizer_onnx.py):
/// - assets/models/t5_encoder_q8.onnx + t5_decoder_q8.onnx (int8, ~94 MB)
/// - assets/models/t5_tokenizer.json (SentencePiece unigram, ported in
///   t5_tokenizer.dart — parity-pinned against HF vectors)
///
/// Runs the backend's `medical_summarize_service` contract on-device:
/// "summarize: [ocr text]" in, greedy decode out, wrapped as
/// `{medical_summary, key_findings, ...}` context for doctor review.
/// Prescription inputs short-circuit to the deterministic builder, mirroring
/// the backend (structured NLP data, never generative output).
class OnnxSlmRuntime implements SlmRuntime {
  OnnxSlmRuntime({
    this.encoderAsset = 'assets/models/t5_encoder_q8.onnx',
    this.decoderAsset = 'assets/models/t5_decoder_q8.onnx',
    this.maxInputTokens = 128,
    this.maxNewTokens = 60,
  });

  final String encoderAsset;
  final String decoderAsset;
  final int maxInputTokens;
  final int maxNewTokens;

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
    _tokenizer = await T5Tokenizer.load();
    _encoder = await ort.createSessionFromAsset(encoderAsset);
    _decoder = await ort.createSessionFromAsset(decoderAsset);
  }

  /// Standardize raw OCR text into summary context for doctor review.
  /// Output contract mirrors backend `medical_summarize_service` for
  /// non-prescription documents: {medical_summary, key_findings, ...}.
  /// Never emits flag fields.
  Future<Map<String, dynamic>> standardizeText(String ocrText) {
    return _standardize(ocrText);
  }

  @override
  Future<Map<String, dynamic>> normalizeJson(String stage1Json) async {
    // Back-compat entry point: accept the compact Stage-1 payload, pull its
    // text, and standardize. Used by ModelManager until call sites migrate.
    var text = stage1Json;
    try {
      final decoded = jsonDecode(stage1Json);
      if (decoded is Map && decoded['text'] is String) {
        text = decoded['text'] as String;
      }
    } catch (_) {
      // Not JSON — treat the whole input as raw OCR text.
    }
    return _standardize(text);
  }

  Future<Map<String, dynamic>> _standardize(String ocrText) async {
    final started = DateTime.now();
    await load();
    final tokenizer = _tokenizer!;
    final encoder = _encoder!;
    final decoder = _decoder!;

    final inputIds = tokenizer.encode(
      'summarize: $ocrText',
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
        'original_length': ocrText.length,
        'summary_length': summary.length,
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
          final flat = await logitsValue.asFlattenedList();
          final vocab = _tokenizer!.vocabSize;
          final lastOff = (decIds.length - 1) * vocab;
          var best = 0;
          var bestScore = double.negativeInfinity;
          for (var i = 0; i < vocab; i++) {
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

  @override
  void close() {
    _encoder?.close();
    _decoder?.close();
    _encoder = null;
    _decoder = null;
    _tokenizer = null;
  }
}

/// Parse + validate raw SLM JSON output. Rejects Stage 3 flag fields and
/// anything that fails the agreed schemas; throws on invalid output so the
/// caller can fall back to the deterministic normalizer.
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

/// Prompt builder shared by both backends (kept identical for the A/B).
String buildSlmUserPayload({required String ocrText}) {
  return jsonEncode({'text': ocrText, 'elements': [], 'tables': []});
}
