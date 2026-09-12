// On-device lab extraction with a flat-text recovery pass.
//
// The structural path (structure.dart -> rule_engine.dart) is better than a
// flat-text regex WHEN the table geometry is right. The failure mode is the
// opposite: when the geometry heuristic guesses a table that is slightly off,
// the rule engine trusts it and a simple "Hemoglobin 11.2 g/dL 13-17" row can
// be lost — a regression versus the old per-line parser.
//
// This layer makes the structural path strictly additive. It re-reads the full
// OCR text two ways and merges in anything the structural pass missed:
//   * the plain-text line parser (one test per line), and
//   * the blob scanner (known test names fused into long merged text),
// deduped by canonical test name + unit. A mis-guessed table can therefore
// never extract fewer values than the flat parser did.
//
// `rule_engine.dart` is deliberately untouched so its byte-for-byte parity
// with `backend/lab_pipeline/slm_stage.py::_build_document` still holds; the
// recovery lives here and is mirrored by `_build_document_with_recovery`.

import 'ocr_model.dart';
import 'rule_engine.dart';
import 'stage1_model.dart';
import 'structure.dart';

/// On-device boxes are page-relative (0..1), so the rule engine's
/// text-inside-table tolerance must be expressed the same way — the backend's
/// 5.0 is in PDF points and would swallow a whole page here.
const onDeviceBboxTolerance = 0.01;

/// The full result of one on-device lab extraction.
class LabExtraction {
  const LabExtraction({
    required this.stage1,
    required this.document,
    required this.structuredTests,
  });

  final LabStage1 stage1;
  final LabDocument document;

  /// Tests the structural pass produced on its own.
  final int structuredTests;

  int get totalTests => countTests(document);

  /// Tests that only the flat-text recovery could find.
  int get recoveredTests => totalTests - structuredTests;
}

int countTests(LabDocument document) =>
    document.panels.fold(0, (sum, panel) => sum + panel.tests.length);

/// OCR pages -> fully recovered lab document.
LabExtraction extractLabDocument(List<OcrPage> ocrPages) {
  final stage1 = buildStage1(ocrPages);
  return extractFromStage1(stage1, bboxTolerance: onDeviceBboxTolerance);
}

/// Stage 1 -> recovered document. Exposed for tests and fixtures, where the
/// coordinate space may be the backend's PDF points rather than page-relative.
LabExtraction extractFromStage1(
  LabStage1 stage1, {
  double bboxTolerance = 5.0,
}) {
  final structured = buildLabDocument(stage1, bboxTolerance: bboxTolerance);
  final plainText = buildLabDocument(
    _linesOnly(stage1.text),
    bboxTolerance: bboxTolerance,
  );
  // A merged line like "Urea 30 mg/dL Creatinine 1.2 mg/dL" yields one test to
  // the line parser; the blob scanner finds both.
  final blobTests = scanBlobForTestRows(stage1.text, null, null, <String>{});

  final candidates = <LabTest>[
    for (final panel in plainText.panels) ...panel.tests,
    ...blobTests,
  ];
  return LabExtraction(
    stage1: stage1,
    document: mergeLabTests(structured, candidates),
    structuredTests: countTests(structured),
  );
}

/// Append every fallback row not already present in [primary], keyed by
/// canonical test name + unit. Recovered rows keep their `low` confidence and
/// land in an "Ungrouped" panel so provenance stays honest.
LabDocument mergeLabDocuments(LabDocument primary, LabDocument fallback) =>
    mergeLabTests(primary, [
      for (final panel in fallback.panels) ...panel.tests,
    ]);

/// Merge candidate rows into [primary], deduped by canonical name + unit.
LabDocument mergeLabTests(LabDocument primary, Iterable<LabTest> candidates) {
  final present = <String>{
    for (final panel in primary.panels)
      for (final test in panel.tests) _seriesKey(test),
  };
  final extras = <LabTest>[];
  for (final test in candidates) {
    if (present.add(_seriesKey(test))) extras.add(test);
  }
  if (extras.isEmpty) return primary;

  final panels = [...primary.panels];
  final index = panels.indexWhere((p) => p.panelName == 'Ungrouped');
  if (index >= 0) {
    panels[index] = LabPanel(
      panelName: 'Ungrouped',
      tests: [...panels[index].tests, ...extras],
    );
  } else {
    panels.add(LabPanel(panelName: 'Ungrouped', tests: extras));
  }
  return LabDocument(
    documentType: primary.documentType,
    patientContext: primary.patientContext,
    labName: primary.labName,
    panels: panels,
  );
}

LabStage1 _linesOnly(String text) => LabStage1(
  extractionEngine: 'mlkit-lines-only',
  text: text,
  elements: const [],
  tables: const [],
  warnings: const [],
);

String _seriesKey(LabTest test) =>
    '${test.testName.toLowerCase()}\u0000${test.unit ?? ''}';
