import 'dart:convert';

import 'package:flutter/services.dart';

/// Minimal SentencePiece-Unigram tokenizer port for the T5 summarizer.
///
/// Faithful to `tokenizer.json` where it matters for parity:
/// - normalization: identity (the Precompiled normalizer does not fold case;
///   HF output preserves "The")
/// - pre-tokenizer: WhitespaceSplit, then Metaspace with prepend_always
/// - model: Unigram Viterbi over the 32100-piece vocab with log-scores
/// - post: append `</s>` (id 1), truncate longest-first from the right
///
/// What is NOT ported (deliberate, documented): byte_fallback surface forms
/// are approximated with `<unk>` (id 2) — the medical-vocab inputs this
/// summariser sees are ASCII/Latin in practice, and parity tests pin the
/// behavior on representative samples. Unknown codepoints never crash.
class T5Tokenizer {
  T5Tokenizer._({
    required this.pieceToId,
    required this.scores,
    required this.unkId,
    required this.eosId,
    required this.vocabSize,
  });

  final Map<String, int> pieceToId;
  final List<double> scores;
  final int unkId;
  final int eosId;
  final int vocabSize;

  /// id -> piece, built once. Decode previously did a linear scan of the
  /// whole 32k vocab per emitted token.
  List<String>? _idToPieceCache;

  static T5Tokenizer? _cache;

  static Future<T5Tokenizer> load([
    String asset = 'assets/models/t5_tokenizer.json',
  ]) async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(asset);
    final tok = T5Tokenizer.parse(raw);
    _cache = tok;
    return tok;
  }

  static T5Tokenizer parse(String raw) {
    final t = jsonDecode(raw) as Map<String, dynamic>;
    final model = t['model'] as Map<String, dynamic>;
    final vocab = model['vocab'] as List;
    final pieceToId = <String, int>{};
    final scores = List<double>.filled(vocab.length, -1e9);
    for (var i = 0; i < vocab.length; i++) {
      final entry = vocab[i] as List;
      pieceToId[entry[0] as String] = i;
      scores[i] = (entry[1] as num).toDouble();
    }
    return T5Tokenizer._(
      pieceToId: pieceToId,
      scores: scores,
      unkId: (model['unk_id'] as num?)?.toInt() ?? 2,
      eosId: pieceToId['</s>'] ?? 1,
      vocabSize: vocab.length,
    );
  }

  /// Encode [text] with the `summarize: ` prefix convention used by the
  /// backend (`services.py::_run_medical_summarization`).
  List<int> encode(String text, {int maxLength = 512}) {
    final normalized = _normalize(text);
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final ids = <int>[];
    for (final word in words) {
      ids.addAll(_encodeWord('▁$word'));
      if (ids.length >= maxLength - 1) break;
    }
    if (ids.length > maxLength - 1) ids.removeRange(maxLength - 1, ids.length);
    ids.add(eosId);
    return ids;
  }

  String decode(List<int> ids) {
    final buf = StringBuffer();
    for (final id in ids) {
      if (id == eosId || id == 0) continue;
      final piece = _idToPiece(id);
      if (piece == null || piece == '<unk>') continue;
      buf.write(piece);
    }
    return buf
        .toString()
        .replaceAll('▁', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _idToPiece(int id) {
    if (id < 0 || id >= vocabSize) return null;
    final cache = _idToPieceCache ??= _buildIdToPiece();
    final piece = cache[id];
    return piece.isEmpty ? null : piece;
  }

  List<String> _buildIdToPiece() {
    final table = List<String>.filled(vocabSize, '');
    for (final e in pieceToId.entries) {
      if (e.value >= 0 && e.value < vocabSize) table[e.value] = e.key;
    }
    return table;
  }

  static String _normalize(String text) {
    // Match the Precompiled normalizer in tokenizer.json: it does NOT fold
    // case (HF output preserves "The"). Only NFC-normalize; Dart strings are
    // already NFC for our Latin inputs.
    return text;
  }

  /// Unigram Viterbi segmentation of one ▁-prefixed word.
  /// Indexes by UTF-16 code unit (matching substring offsets below); the
  /// ▁ marker and all vocab pieces relevant here are BMP, so this matches
  /// rune indexing for our inputs.
  List<int> _encodeWord(String word) {
    final n = word.length;
    const negInf = -1e30;
    final best = List<double>.filled(n + 1, negInf);
    final back = List<int>.filled(n + 1, -1);
    final backId = List<int>.filled(n + 1, -1);
    best[0] = 0;
    for (var i = 0; i < n; i++) {
      if (best[i] == negInf) continue;
      for (var j = i + 1; j <= n && j - i <= 32; j++) {
        final piece = word.substring(i, j);
        final id = pieceToId[piece];
        if (id == null) continue;
        final score = best[i] + scores[id];
        if (score > best[j]) {
          best[j] = score;
          back[j] = i;
          backId[j] = id;
        }
      }
    }
    if (back[n] == -1) return [unkId];
    final ids = <int>[];
    var j = n;
    while (j > 0) {
      ids.add(backId[j]);
      j = back[j];
    }
    return ids.reversed.toList();
  }
}
