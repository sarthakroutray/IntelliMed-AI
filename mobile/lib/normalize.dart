import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'schemas.dart';

// Deterministic on-device normalizer: mirrors the backend deterministic-v1
// engine (lab_pipeline/slm_stage.py::_build_document) for printed text. The
// SLM path (slm_runtime.dart) handles noisy layouts; whatever text path runs,
// output always passes through the schema validators in schemas.dart.

final _valueUnitRe = RegExp(
  r'([A-Za-z][A-Za-z .()/%^0-9\-]{2,}?)\s+(\d+(?:\.\d+)?)\s*([A-Za-z/%^µμ]+)?(?:\s+(\d+(?:\.\d+)?\s*[-–—]\s*\d+(?:\.\d+)?))?',
);

String _confidenceFor({
  required bool hasValue,
  required bool hasUnit,
  required bool knownName,
}) {
  if (!hasValue) return 'low';
  if (!hasUnit || !knownName) return 'medium';
  return 'high';
}

Map<String, dynamic> normalizeLabText(String ocrText) {
  final lines = ocrText
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final tests = <Map<String, dynamic>>[];
  for (final line in lines) {
    final m = _valueUnitRe.firstMatch(line);
    if (m == null) continue;
    final rawName = m.group(1)!.trim();
    final value = double.tryParse(m.group(2)!);
    final unit = m.group(3);
    double? low, high;
    String? rangeRaw;
    if (m.group(4) != null) {
      rangeRaw = m.group(4);
      final parts = rangeRaw!.split(RegExp(r'[-–—]'));
      if (parts.length == 2) {
        low = double.tryParse(parts[0].trim());
        high = double.tryParse(parts[1].trim());
      }
    }
    final normalized = normalizeTestName(rawName);
    final known = normalized != rawName;
    tests.add({
      'test_name': normalized,
      'raw_test_name': rawName,
      'value': value,
      'unit': unit,
      'range_low': low,
      'range_high': high,
      'range_raw': rangeRaw,
      'flag_in_source': null,
      'ocr_confidence': _confidenceFor(
        hasValue: value != null,
        hasUnit: unit != null,
        knownName: known,
      ),
      'source_bbox': null,
    });
  }
  return {
    'document_type': 'lab_report',
    'patient_context': {
      'name': null,
      'age': null,
      'sex': null,
      'report_date': null,
    },
    'lab_name': null,
    'panels': [
      {'panel_name': 'Ungrouped', 'tests': tests},
    ],
  };
}

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

/// Off-main-thread normalization entry point for the inference queue.
Future<Map<String, dynamic>> normalizeInBackground(
  (String kind, String text) args,
) {
  return compute(_normalizeSync, args);
}

Map<String, dynamic> _normalizeSync((String, String) args) {
  final (kind, text) = args;
  if (kind == 'prescription') return normalizePrescriptionText(text);
  return normalizeLabText(text);
}

/// Canonical result envelope stored locally and POSTed to /api/v2/*.
Map<String, dynamic> buildResultEnvelope({
  required String kind,
  required Map<String, dynamic> normalized,
  required String ocrText,
  required String engine,
  required int latencyMs,
  Map<String, dynamic>? summaryContext,
}) {
  return {
    'kind': kind,
    'engine': engine,
    'latency_ms': latencyMs,
    'normalized': normalized,
    // ignore: use_null_aware_elements (? form is invalid: key is non-nullable)
    if (summaryContext != null) 'summary_context': summaryContext,
    'ocr_excerpt': ocrText.length > 500 ? ocrText.substring(0, 500) : ocrText,
    'source': 'app',
  };
}

String encodeEnvelope(Map<String, dynamic> envelope) => jsonEncode(envelope);
