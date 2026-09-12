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
