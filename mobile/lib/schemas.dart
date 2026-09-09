import 'dart:convert';

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

const testNameMap = <String, String>{
  'hb': 'Hemoglobin',
  'hgb': 'Hemoglobin',
  'wbc': 'White Blood Cell Count',
  'tlc': 'White Blood Cell Count',
  'rbc': 'Red Blood Cell Count',
  'plt': 'Platelet Count',
  'hct': 'Hematocrit',
  'pcv': 'Hematocrit',
  'mcv': 'Mean Corpuscular Volume',
  'mch': 'Mean Corpuscular Hemoglobin',
  'mchc': 'Mean Corpuscular Hemoglobin Concentration',
  'rdw': 'Red Cell Distribution Width',
  'esr': 'Erythrocyte Sedimentation Rate',
  'crp': 'C-Reactive Protein',
  'fbs': 'Fasting Blood Glucose',
  'hba1c': 'Glycated Hemoglobin (HbA1c)',
  'sgot': 'Aspartate Aminotransferase (AST)',
  'sgpt': 'Alanine Aminotransferase (ALT)',
  'tsh': 'Thyroid Stimulating Hormone',
  'hdl': 'HDL Cholesterol',
  'ldl': 'LDL Cholesterol',
  'creatinine': 'Serum Creatinine',
  'creat': 'Serum Creatinine',
  'urea': 'Blood Urea',
};

String normalizeTestName(String raw) {
  final key = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').trim();
  return testNameMap[key] ?? raw.trim();
}

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
