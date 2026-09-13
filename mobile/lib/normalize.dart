import 'dart:convert';

import 'package:flutter/foundation.dart';

// Deterministic on-device normalizer for prescriptions. Lab reports are no
// longer normalized here: their structure comes from the rule engine
// (lib/lab/rule_engine.dart), because the flat-text regex this file used to
// hold could not represent a table, a fused blob or a source flag.

final _rxLineRe = RegExp(
  r'^(.+?)\s+(\d+(?:\.\d+)?\s*(?:mg|ml|mcg|g|iu|units?))\s*(.*)$',
  caseSensitive: false,
);

Map<String, dynamic> normalizePrescriptionText(String ocrText) {
  final items = <Map<String, dynamic>>[];
  for (final rawLine in ocrText.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final m = _rxLineRe.firstMatch(line);
    if (m == null) continue;
    final med = m.group(1)!.trim();
    if (med.length < 3) continue;
    items.add({
      'medication': med.toLowerCase(),
      if (m.group(2) != null) 'dosage': m.group(2)!.trim(),
      if (m.group(3) != null && m.group(3)!.trim().isNotEmpty)
        'frequency': m.group(3)!.trim(),
    });
  }
  return {
    'document_type': 'prescription',
    'patient_context': {
      'name': null,
      'age': null,
      'sex': null,
      'report_date': null,
    },
    'panels': [
      {'panel_name': 'Prescribed items', 'items': items},
    ],
  };
}

/// Off-main-thread prescription normalization for the inference queue.
Future<Map<String, dynamic>> normalizePrescriptionInBackground(String text) =>
    compute(normalizePrescriptionText, text);

/// Deterministic rendering of a prescription for the summariser.
///
/// Mirrors renderLabText (lab/render.dart): the structured items the
/// deterministic normalizer extracted come first, so a mis-parsed line can
/// never become a medication in the summary. [context] (the document's own
/// text) is appended afterwards so the model can also summarise the details the
/// item extractor does not capture — timing, duration, tests, follow-up — with
/// exact repeats of item lines dropped. Falls back to [fallback] (the raw OCR
/// text) when nothing was extracted.
String renderPrescriptionText(
  Map<String, dynamic> normalized, {
  String fallback = '',
  String context = '',
}) {
  final lines = <String>[];
  final panels = normalized['panels'];
  if (panels is List) {
    for (final panel in panels) {
      if (panel is! Map) continue;
      final items = panel['items'];
      if (items is! List) continue;
      for (final item in items) {
        if (item is! Map) continue;
        final parts = [item['medication'], item['dosage'], item['frequency']]
            .where((v) => v != null && '$v'.trim().isNotEmpty)
            .map((v) => '$v'.trim());
        if (parts.isNotEmpty) lines.add(parts.join(' '));
      }
    }
  }

  if (lines.isEmpty) return fallback.isNotEmpty ? fallback : context;

  final buffer = StringBuffer('Prescribed items:\n${lines.join('\n')}');
  final extra = _uncoveredContextLines(context, lines);
  if (extra.isNotEmpty) {
    buffer.write('\n\nOther text on the prescription:\n$extra');
  }
  return buffer.toString();
}

/// [context] lines that are not already covered by the rendered [items],
/// de-duplicated and in order.
List<String> _uncoveredContextLines(String context, List<String> items) {
  final covered = items.map((l) => l.toLowerCase()).toSet();
  final seen = <String>{};
  final kept = <String>[];
  for (final raw in context.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final key = line.toLowerCase();
    if (covered.contains(key) || !seen.add(key)) continue;
    kept.add(line);
  }
  return kept;
}

/// Canonical result envelope stored locally and POSTed to /api/v2/*.
///
/// [detection] records how the document type was decided (and whether the user
/// chose it). It is provenance for the reviewing doctor; the backend ignores
/// the key.
///
/// [structure] records how the lab structure was reconstructed on-device (OCR
/// engine, table/test counts, derived confidence, pages without tables), so a
/// reviewer can tell a clean geometric extraction from a degraded line-only
/// reconstruction. The backend ignores unknown keys.
///
/// [pageCount] / [pagesTruncated] describe a multipage source (a PDF). They are
/// also provenance: the server only ever receives the structured result, so
/// without these a reviewer could not tell that a 30-page PDF was capped at
/// [maxPdfPages].
Map<String, dynamic> buildResultEnvelope({
  required String kind,
  required Map<String, dynamic> normalized,
  required String ocrText,
  required String engine,
  required int latencyMs,
  Map<String, dynamic>? stage3,
  Map<String, dynamic>? summaryContext,
  Map<String, dynamic>? detection,
  Map<String, dynamic>? structure,
  List<String>? warnings,
  int pageCount = 1,
  bool pagesTruncated = false,
}) {
  return {
    'kind': kind,
    'engine': engine,
    'latency_ms': latencyMs,
    'normalized': normalized,
    // ignore: use_null_aware_elements (? form is invalid: key is non-nullable)
    if (stage3 != null) 'stage3': stage3,
    // ignore: use_null_aware_elements (? form is invalid: key is non-nullable)
    if (summaryContext != null) 'summary_context': summaryContext,
    // ignore: use_null_aware_elements (? form is invalid: key is non-nullable)
    if (detection != null) 'detection': detection,
    // ignore: use_null_aware_elements (? form is invalid: key is non-nullable)
    if (structure != null) 'structure': structure,
    // ignore: use_null_aware_elements (? form is invalid: key is non-nullable)
    if (warnings != null && warnings.isNotEmpty) 'warnings': warnings,
    'page_count': pageCount,
    // ignore: use_null_aware_elements (? form is invalid: key is non-nullable)
    if (pagesTruncated) 'pages_truncated': true,
    'ocr_excerpt': ocrText.length > 500 ? ocrText.substring(0, 500) : ocrText,
    'source': 'app',
  };
}

String encodeEnvelope(Map<String, dynamic> envelope) => jsonEncode(envelope);
