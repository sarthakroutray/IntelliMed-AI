// Tests for the flat-text recovery pass.
//
// The regression this guards: when structure.dart guesses a table that is
// slightly wrong, the rule engine trusts it and simple rows the old flat-text
// parser handled are lost. Recovery re-parses the full OCR text and merges any
// missing row back in, so the structural path is never worse than the flat one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/lab/extract.dart';
import 'package:intellimed_app/lab/rule_engine.dart';
import 'package:intellimed_app/lab/stage1_model.dart';
import 'package:intellimed_app/schemas.dart';

LabStage1 _stage1(String text, {List<LabTable> tables = const []}) => LabStage1(
  extractionEngine: tables.isEmpty ? 'mlkit-lines-only' : 'mlkit-geometry',
  text: text,
  elements: const [],
  tables: tables,
  warnings: const [],
);

LabTable _singleCellTable(List<String> rows) => LabTable(
  rows: [
    for (final text in rows)
      LabTableRow(cells: [LabCell(text: text)]),
  ],
);

int _testCount(LabDocument document) =>
    document.panels.fold(0, (n, p) => n + p.tests.length);

Set<String> _testNames(LabDocument document) =>
    document.panels.expand((p) => p.tests).map((t) => t.testName).toSet();

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

bool _deepEquals(Object? a, Object? b) {
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

void main() {
  group('recovery recovers rows a mis-guessed table drops', () {
    test('a table that parses to nothing does not lose simple rows', () {
      final stage1 = _stage1(
        'Hemoglobin 11.2 g/dL 13.0-17.0\n'
        'WBC 7.5 4.0-11.0\n'
        'Platelet Count 250 150-450',
        tables: [_singleCellTable(['Garbage'])],
      );

      // The bogus table is trusted by the reference engine and yields nothing.
      expect(_testCount(buildLabDocument(stage1)), 0);

      final extraction = extractFromStage1(stage1);
      expect(
        _testNames(extraction.document),
        containsAll(['Hemoglobin', 'White Blood Cell Count', 'Platelet Count']),
      );
      expect(extraction.structuredTests, 0);
      expect(extraction.recoveredTests, 3);
    });

    test('a row already captured structurally is not duplicated', () {
      final stage1 = _stage1(
        'Hemoglobin 11.2 g/dL 13.0-17.0',
        tables: [
          LabTable(
            rows: [
              LabTableRow(
                cells: const [
                  LabCell(text: 'Hemoglobin'),
                  LabCell(text: '11.2'),
                  LabCell(text: 'g/dL'),
                  LabCell(text: '13.0-17.0'),
                ],
              ),
            ],
          ),
        ],
      );

      final extraction = extractFromStage1(stage1);
      expect(_testCount(extraction.document), 1);
      expect(extraction.recoveredTests, 0);
    });

    test('recovered rows keep low confidence and land in Ungrouped', () {
      final stage1 = _stage1(
        'Creatinine 1.1 mg/dL 0.7-1.3',
        tables: [_singleCellTable(['Garbage'])],
      );
      final extraction = extractFromStage1(stage1);
      final panel = extraction.document.panels.firstWhere(
        (p) => p.panelName == 'Ungrouped',
      );
      expect(panel.tests, isNotEmpty);
      expect(panel.tests.every((t) => t.ocrConfidence == 'low'), isTrue);
    });

    test('the merged document still passes the wire schema', () {
      final stage1 = _stage1(
        'Hemoglobin 11.2 g/dL 13.0-17.0',
        tables: [_singleCellTable(['Garbage'])],
      );
      final json = extractFromStage1(stage1).document.toJson();
      expect(validateLabReport(json), isEmpty);
      expect(_testCount(extractFromStage1(stage1).document), 1);
    });

    test('blob recovery finds tests fused into a single line', () {
      // The line parser sees one test here ("Urea ..."); only the blob scanner
      // finds the second.
      final stage1 = _stage1(
        'Urea 30 mg/dL Creatinine 1.2 mg/dL',
        tables: [_singleCellTable(['Garbage'])],
      );
      final names = _testNames(extractFromStage1(stage1).document);
      expect(names, containsAll(['Blood Urea', 'Serum Creatinine']));
    });
  });

  group('recovery matches the mirrored Python recovery on the fixtures', () {
    // `.recovery.json` is produced by
    // `run_stage2_fixture.py --recovery` and enforces that the two languages
    // agree. Recovery can legitimately add rows the bare reference drops (e.g.
    // "TSH <0.01 mIU/mL", which the line parser cannot split), so this is
    // checked against the recovery golden, not the bare-reference `.expected`.
    for (final name in const [
      'cbc_table',
      'single_cell_blob',
      'plain_text_fallback',
      'missed_rows',
    ]) {
      test('$name matches its recovery golden', () {
        final stage1 = LabStage1.fromJson(
          _readJson('test/fixtures/lab/$name.stage1.json'),
        );
        final expected = _readJson('test/fixtures/lab/$name.recovery.json');
        final extraction = extractFromStage1(stage1);
        expect(_deepEquals(extraction.document.toJson(), expected), isTrue);
      });
    }
  });
}
