// Cross-language parity + unit tests for the ported Stage 2 rule engine.
//
// The parity half is the highest-value check in the lab-report plan: the same
// Stage 1 fixtures are run through the Dart port and compared against the
// output of the Python reference (`backend/lab_pipeline/slm_stage.py`),
// captured with `backend/scripts/run_stage2_fixture.py`. Regenerate the
// goldens with that script after any intentional behaviour change.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/lab/rule_engine.dart';
import 'package:intellimed_app/lab/stage1_model.dart';
import 'package:intellimed_app/schemas.dart';

const _fixtureDir = 'test/fixtures/lab';
const _fixtures = [
  'cbc_table',
  'single_cell_blob',
  'plain_text_fallback',
  'missed_rows',
];

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

LabTableRow _row(List<String> texts, {bool isHeader = false}) => LabTableRow(
  cells: [for (final t in texts) LabCell(text: t, isHeader: isHeader)],
);

LabTest _single(String text, {bool degraded = true}) =>
    parseTableRow(_row([text]), engineDegraded: degraded)!;

void main() {
  group('cross-language parity with the Python reference', () {
    for (final name in _fixtures) {
      test('$name matches backend _build_document byte-for-byte', () {
        final stage1 = LabStage1.fromJson(
          _readJson('$_fixtureDir/$name.stage1.json'),
        );
        final expected = _readJson('$_fixtureDir/$name.expected.json');
        final actual = buildLabDocument(stage1).toJson();
        expect(
          _deepEquals(actual, expected),
          isTrue,
          reason:
              'Dart and Python disagree.\nDart: '
              '${const JsonEncoder.withIndent('  ').convert(actual)}',
        );
      });
    }

    test('the Dart test-name map equals the backend TEST_NAME_MAP', () {
      final golden = _readJson('$_fixtureDir/test_name_map.json');
      final expected = golden.map((k, v) => MapEntry(k, '$v'));
      expect(testNameMap, expected);
    });

    test('the live Python reference agrees (skipped without python)', () {
      final script = '../backend/scripts/run_stage2_fixture.py';
      if (!File(script).existsSync()) {
        markTestSkipped('reference script not found at $script');
        return;
      }
      for (final name in _fixtures) {
        final fixture = '$_fixtureDir/$name.stage1.json';
        final ProcessResult result;
        try {
          result = Process.runSync('python', [script, fixture]);
        } on ProcessException catch (e) {
          markTestSkipped('python interpreter not available: ${e.message}');
          return;
        }
        expect(
          result.exitCode,
          0,
          reason: 'python reference failed: ${result.stderr}',
        );
        final expected = _readJson('$_fixtureDir/$name.expected.json');
        final actual =
            jsonDecode(result.stdout as String) as Map<String, dynamic>;
        expect(
          _deepEquals(actual, expected),
          isTrue,
          reason: '$name: live Python output differs from its committed golden',
        );
      }
    });
  });

  group('number, unit and range parsing', () {
    test('parses plain, grouped and decimal numbers', () {
      expect(parseNumber('11.2 g/dL'), 11.2);
      expect(parseNumber('1,200 mg/dL'), 1200);
      expect(parseNumber('no digits here'), isNull);
    });

    test('does not treat a digit-glued token as a number', () {
      expect(parseNumber('abc123def'), isNull);
      // '^' is not a word char, so the guard lets the leading 10 through —
      // this mirrors the Python reference exactly.
      expect(parseNumber('10^3/uL'), 10);
    });

    test('recognises units and rejects prose', () {
      expect(looksLikeUnit('mg/dL'), isTrue);
      expect(looksLikeUnit('10^3/uL'), isTrue);
      expect(looksLikeUnit('Clear'), isFalse);
    });

    test('parses a range pair, less-than and greater-than', () {
      expect(parseRange('13.0-17.0').low, 13.0);
      expect(parseRange('13.0-17.0').high, 17.0);
      expect(parseRange('<200').high, 200);
      expect(parseRange('<200').low, isNull);
      expect(parseRange('>4').low, 4);
      expect(parseRange('>4').high, isNull);
      expect(parseRange('no range here').raw, isNull);
    });
  });

  group('the cases the old single-regex extractor got wrong', () {
    test('a fused single-cell blob is split into name/value/unit/range', () {
      final t = _single('Hemoglobin (Hb) 11.2 g/dL 13.0-17.0');
      expect(t.testName, 'Hemoglobin');
      expect(t.rawTestName, 'Hemoglobin (Hb)');
      expect(t.value, 11.2);
      expect(t.unit, 'g/dL');
      expect(t.rangeLow, 13.0);
      expect(t.rangeHigh, 17.0);
      // A fused blob is a reconstruction — always low confidence.
      expect(t.ocrConfidence, 'low');
    });

    test('<200 is a printed upper bound, not a value', () {
      final t = parseTableRow(
        _row(['LDL Cholesterol', '230', 'mg/dL', '<200 H']),
        engineDegraded: false,
      )!;
      expect(t.value, 230);
      expect(t.rangeLow, isNull);
      expect(t.rangeHigh, 200);
      expect(t.rangeRaw, '<200');
    });

    test('>4 is a printed lower bound', () {
      final t = parseTableRow(
        _row(['eGFR', '72', 'mL/min', '>4']),
        engineDegraded: false,
      )!;
      expect(t.rangeLow, 4);
      expect(t.rangeHigh, isNull);
    });

    test('a comma-grouped value parses as one number', () {
      expect(parseNumber('1,200'), 1200);
      final t = _single('Creatinine 1,200 mg/dL 0.7-1.3');
      expect(t.value, 1200);
    });

    test('a source-printed H flag is captured and stripped from the name', () {
      final t = parseTableRow(
        _row(['LDL Cholesterol H', '230', 'mg/dL']),
        engineDegraded: false,
      )!;
      expect(t.flagInSource, 'H');
      expect(t.rawTestName, 'LDL Cholesterol');
    });

    test('a lower-case "h" in prose is never a flag', () {
      final t = parseTableRow(
        LabTableRow(
          cells: const [
            LabCell(text: 'haemoglobin'),
            LabCell(text: '11.2'),
            LabCell(text: 'g/dL'),
            LabCell(text: 'h'),
          ],
        ),
        engineDegraded: false,
      )!;
      expect(t.flagInSource, isNull);
    });

    test('last-token fallback resolves "S. Creatinine (Serum)"', () {
      expect(normalizeTestNameOrNull('S. Creatinine (Serum)'), 'Serum Creatinine');
      expect(normalizeTestNameOrNull('Serum Creatinine'), 'Serum Creatinine');
    });

    test('a column-header row that slipped through is dropped', () {
      final header = parseTableRow(
        _row(['Result', 'Value', 'Unit', 'Range'], isHeader: false),
        engineDegraded: false,
      );
      expect(header, isNull);
    });

    test('a fully header-marked row with no numbers is dropped', () {
      final row = LabTableRow(
        cells: [
          const LabCell(text: 'Test', isHeader: true),
          const LabCell(text: 'Result', isHeader: true),
        ],
      );
      expect(parseTableRow(row, engineDegraded: false), isNull);
    });
  });

  group('the 10-key invariant', () {
    test('every emitted test carries exactly the schema keys, no flags', () {
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
      final doc = buildLabDocument(
        LabStage1.fromJson(
          _readJson('$_fixtureDir/cbc_table.stage1.json'),
        ),
      ).toJson();
      expect(validateLabReport(doc), isEmpty);
      for (final panel in doc['panels'] as List) {
        for (final test in (panel as Map)['tests'] as List) {
          final keys = (test as Map).keys.map((k) => '$k').toSet();
          expect(keys, required);
          expect(keys.contains('abnormal'), isFalse);
          expect(keys.contains('direction'), isFalse);
        }
      }
    });
  });
}
