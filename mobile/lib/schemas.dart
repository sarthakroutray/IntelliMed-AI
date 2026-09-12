import 'dart:convert';

import 'lab/test_names.dart';

export 'lab/test_names.dart'
    show testNameMap, normalizeLookupKey, normalizeTestNameOrNull;

// Lab report schema mirror of backend/lab_pipeline/slm_stage.py::_build_document
// plus Stage 3 annotation fields (added server-side or by the on-device
// deterministic rule pass). Prescription schema mirrors
// backend/services.py nlp prescription objects, lifted into panels so both
// document kinds share one envelope.

const labSystemPromptExcerpt = '''
You are a medical document normalization engine. Your ONLY job is to convert
extracted document text/structure into a fixed JSON schema. You do not
interpret or make clinical judgments. Output valid JSON only.
''';

String normalizeTestName(String raw) =>
    normalizeTestNameOrNull(raw) ?? raw.trim();

/// Validate a lab report document against the agreed schema.
/// Returns a list of problems; empty means schema-correct.
List<String> validateLabReport(Map<String, dynamic> doc) {
  final problems = <String>[];
  if (doc['document_type'] != 'lab_report') {
    problems.add('document_type must be "lab_report"');
  }
  for (final key in ['patient_context', 'lab_name', 'panels']) {
    if (!doc.containsKey(key)) problems.add('missing key: $key');
  }
  final panels = doc['panels'];
  if (panels is! List) {
    problems.add('panels must be a list');
    return problems;
  }
  const required = {
    'test_name',
    'raw_test_name',
    'value',
    'unit',
    'range_low',
    'range_high',
    'range_raw',
    'flag_in_source',
    'ocr_confidence',
    'source_bbox',
  };
  for (final panel in panels) {
    if (panel is! Map ||
        !panel.containsKey('panel_name') ||
        !panel.containsKey('tests')) {
      problems.add('panel missing panel_name/tests: $panel');
      continue;
    }
    for (final test in (panel['tests'] as List? ?? [])) {
      if (test is! Map) {
        problems.add('test entry must be an object');
        continue;
      }
      final missing = required.difference(test.keys.map((k) => '$k').toSet());
      if (missing.isNotEmpty) {
        problems.add('test ${test['raw_test_name']} missing keys: $missing');
      }
      if (test.containsKey('abnormal') || test.containsKey('direction')) {
        problems.add(
          'test ${test['raw_test_name']} carries Stage 3 fields '
          '(abnormal/direction) — normalization output must never contain flags',
        );
      }
    }
  }
  return problems;
}

/// Validate a prescription document: medication-centred panels.
List<String> validatePrescription(Map<String, dynamic> doc) {
  final problems = <String>[];
  if (doc['document_type'] != 'prescription') {
    problems.add('document_type must be "prescription"');
  }
  for (final key in ['patient_context', 'panels']) {
    if (!doc.containsKey(key)) problems.add('missing key: $key');
  }
  final panels = doc['panels'];
  if (panels is! List) {
    problems.add('panels must be a list');
    return problems;
  }
  for (final panel in panels) {
    if (panel is! Map ||
        panel['panel_name'] == null ||
        panel['items'] == null) {
      problems.add('panel missing panel_name/items: $panel');
      continue;
    }
    for (final item in (panel['items'] as List? ?? [])) {
      if (item is! Map || (item['medication'] as String?)?.isEmpty != false) {
        problems.add('prescription item missing medication name: $item');
      }
    }
  }
  return problems;
}

/// Pretty-print helper for review screens (never renders flag verdicts).
String prettyJson(Map<String, dynamic> doc) =>
    const JsonEncoder.withIndent('  ').convert(doc);
