// Tests for Stage 3 clinical & arithmetic engine in Dart.
// Verifies full parity with backend/tests/test_arithmetic_engine.py.

import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/lab/clinical_engine.dart';
import 'package:intellimed_app/lab/rule_engine.dart';

LabTest _test(
  String name,
  double value, {
  String? unit,
  double? low,
  double? high,
}) =>
    LabTest(
      testName: name,
      rawTestName: name,
      value: value,
      unit: unit,
      rangeLow: low,
      rangeHigh: high,
      rangeRaw: low != null && high != null ? '$low-$high' : null,
      flagInSource: null,
      ocrConfidence: 'high',
      sourceBbox: const {'page': 1, 'bbox': [100.0, 100.0, 200.0, 120.0]},
    );

LabDocument _doc(
  List<LabTest> tests, {
  int age = 45,
  String sex = 'male',
  String panel = 'Biochemistry',
}) =>
    LabDocument(
      documentType: 'lab_report',
      patientContext: PatientContext(
        name: 'Alex',
        age: age,
        sex: sex,
        reportDate: '12-04-2024',
      ),
      labName: 'Metropolitan Labs',
      panels: [LabPanel(panelName: panel, tests: tests)],
    );

void main() {
  group('Stage 3 Arithmetic Calculations', () {
    test('eGFR male calculation via CKD-EPI 2021', () {
      final doc = _doc(
        [_test('Serum Creatinine', 1.8, unit: 'mg/dL', low: 0.7, high: 1.3)],
        age: 45,
        sex: 'male',
      );
      final annotated = calculateDerivedIndices(doc);
      final derivedPanel = annotated.panels.firstWhere(
        (p) => p.panelName == 'Calculated / Derived Indices',
      );
      final egfr = derivedPanel.tests.firstWhere(
        (t) => t.testName == 'Estimated Glomerular Filtration Rate',
      );
      expect(egfr.value, isNotNull);
      expect(egfr.value!, greaterThan(40.0));
      expect(egfr.value!, lessThan(50.0));
      expect(egfr.unit, 'mL/min/1.73m2');
    });

    test('eGFR female calculation via CKD-EPI 2021', () {
      final doc = _doc(
        [_test('Serum Creatinine', 1.0, unit: 'mg/dL', low: 0.5, high: 1.1)],
        age: 60,
        sex: 'female',
      );
      final annotated = calculateDerivedIndices(doc);
      final derivedPanel = annotated.panels.firstWhere(
        (p) => p.panelName == 'Calculated / Derived Indices',
      );
      final egfr = derivedPanel.tests.firstWhere(
        (t) => t.testName == 'Estimated Glomerular Filtration Rate',
      );
      expect(egfr.value, isNotNull);
      expect(egfr.value!, greaterThan(60.0));
      expect(egfr.value!, lessThan(75.0));
    });

    test('Serum Anion Gap calculation', () {
      final doc = _doc([
        _test('Sodium', 140.0, unit: 'mEq/L', low: 135.0, high: 145.0),
        _test('Chloride', 102.0, unit: 'mEq/L', low: 96.0, high: 106.0),
        _test('Bicarbonate', 18.0, unit: 'mEq/L', low: 22.0, high: 29.0),
      ]);
      final annotated = calculateDerivedIndices(doc);
      final derivedPanel = annotated.panels.firstWhere(
        (p) => p.panelName == 'Calculated / Derived Indices',
      );
      final agap = derivedPanel.tests.firstWhere(
        (t) => t.testName == 'Serum Anion Gap',
      );
      expect(agap.value, 20.0);
      expect(agap.unit, 'mEq/L');
    });

    test('De Ritis Ratio (AST/ALT) calculation', () {
      final doc = _doc([
        _test('Aspartate Aminotransferase (AST)', 80.0, unit: 'U/L'),
        _test('Alanine Aminotransferase (ALT)', 32.0, unit: 'U/L'),
      ]);
      final annotated = calculateDerivedIndices(doc);
      final derivedPanel = annotated.panels.firstWhere(
        (p) => p.panelName == 'Calculated / Derived Indices',
      );
      final deRitis = derivedPanel.tests.firstWhere(
        (t) => t.testName == 'AST/ALT (De Ritis) Ratio',
      );
      expect(deRitis.value, 2.5);
    });

    test('Corrected Calcium calculation', () {
      final doc = _doc([
        _test('Calcium', 8.0, unit: 'mg/dL', low: 8.5, high: 10.5),
        _test('Serum Albumin', 2.5, unit: 'g/dL', low: 3.5, high: 5.0),
      ]);
      final annotated = calculateDerivedIndices(doc);
      final derivedPanel = annotated.panels.firstWhere(
        (p) => p.panelName == 'Calculated / Derived Indices',
      );
      final corrCa = derivedPanel.tests.firstWhere(
        (t) => t.testName == 'Corrected Calcium',
      );
      expect(corrCa.value, 9.2);
    });

    test('BUN / Creatinine Ratio calculation', () {
      final doc = _doc([
        _test('Blood Urea Nitrogen', 45.0, unit: 'mg/dL'),
        _test('Serum Creatinine', 1.5, unit: 'mg/dL'),
      ]);
      final annotated = calculateDerivedIndices(doc);
      final derivedPanel = annotated.panels.firstWhere(
        (p) => p.panelName == 'Calculated / Derived Indices',
      );
      final ratio = derivedPanel.tests.firstWhere(
        (t) => t.testName == 'BUN/Creatinine Ratio',
      );
      expect(ratio.value, 30.0);
    });

    test('Non-HDL Cholesterol calculation', () {
      final doc = _doc([
        _test('Total Cholesterol', 240.0, unit: 'mg/dL'),
        _test('HDL Cholesterol', 45.0, unit: 'mg/dL'),
      ]);
      final annotated = calculateDerivedIndices(doc);
      final derivedPanel = annotated.panels.firstWhere(
        (p) => p.panelName == 'Calculated / Derived Indices',
      );
      final nonHdl = derivedPanel.tests.firstWhere(
        (t) => t.testName == 'Non-HDL Cholesterol',
      );
      expect(nonHdl.value, 195.0);
    });

    test('Mentzer Index calculation', () {
      final doc = _doc([
        _test('Mean Corpuscular Volume', 65.0, unit: 'fL'),
        _test('Red Blood Cell Count', 5.5, unit: '10^6/uL'),
      ], panel: 'CBC');
      final annotated = calculateDerivedIndices(doc);
      final derivedPanel = annotated.panels.firstWhere(
        (p) => p.panelName == 'Calculated / Derived Indices',
      );
      final mentzer = derivedPanel.tests.firstWhere(
        (t) => t.testName == 'Mentzer Index',
      );
      expect(mentzer.value, 11.82);
    });
  });

  group('Stage 3 Arithmetic Consistency Checks', () {
    test('detects Bilirubin sum mismatch', () {
      final doc = _doc([
        _test('Total Bilirubin', 5.0, unit: 'mg/dL'),
        _test('Direct Bilirubin', 1.0, unit: 'mg/dL'),
        _test('Indirect Bilirubin', 1.0, unit: 'mg/dL'),
      ]);
      final warnings = verifyArithmeticConsistency(doc);
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('Bilirubin arithmetic mismatch'));
    });

    test('clean when Bilirubin sums correctly', () {
      final doc = _doc([
        _test('Total Bilirubin', 2.5, unit: 'mg/dL'),
        _test('Direct Bilirubin', 0.5, unit: 'mg/dL'),
        _test('Indirect Bilirubin', 2.0, unit: 'mg/dL'),
      ]);
      final warnings = verifyArithmeticConsistency(doc);
      expect(warnings, isEmpty);
    });
  });

  group('Stage 3 Panic & Flagging', () {
    test('flags critical panic hyperkalemia', () {
      final doc = _doc([
        _test('Potassium', 6.5, unit: 'mEq/L', low: 3.5, high: 5.0),
      ]);
      final flagged = flagSingleValues(doc);
      final t = (flagged['panels'] as List)[0]['tests'][0];
      expect(t['abnormal'], isTrue);
      expect(t['direction'], 'high');
      expect(t['is_panic_value'], isTrue);
      expect(t['severity'], 'critical');
    });

    test('flags critical panic thrombocytopenia', () {
      final doc = _doc([
        _test('Platelet Count', 15.0, unit: '10^3/uL', low: 150.0, high: 450.0),
      ], panel: 'CBC');
      final flagged = flagSingleValues(doc);
      final t = (flagged['panels'] as List)[0]['tests'][0];
      expect(t['abnormal'], isTrue);
      expect(t['direction'], 'low');
      expect(t['is_panic_value'], isTrue);
      expect(t['severity'], 'critical');
    });
  });

  group('Stage 3 Clinical Pattern Rules', () {
    test('triggers microcytic hypochromic anemia pattern', () {
      final doc = _doc([
        _test('Hemoglobin', 9.5, unit: 'g/dL', low: 13.0, high: 17.0),
        _test('Mean Corpuscular Volume', 72.0, unit: 'fL', low: 80.0, high: 100.0),
        _test('Mean Corpuscular Hemoglobin', 23.0, unit: 'pg', low: 27.0, high: 33.0),
      ], panel: 'CBC');
      final result = annotateLabDocument(doc);
      final names = result.patterns.map((p) => p.patternName).toList();
      expect(names, contains('microcytic_hypochromic_anemia'));
    });

    test('triggers high anion gap metabolic acidosis pattern', () {
      final doc = _doc([
        _test('Sodium', 142.0, unit: 'mEq/L', low: 135.0, high: 145.0),
        _test('Chloride', 98.0, unit: 'mEq/L', low: 96.0, high: 106.0),
        _test('Bicarbonate', 16.0, unit: 'mEq/L', low: 22.0, high: 29.0),
      ]);
      final result = annotateLabDocument(doc);
      final names = result.patterns.map((p) => p.patternName).toList();
      expect(names, contains('high_anion_gap_metabolic_acidosis'));
    });

    test('triggers alcoholic liver pattern via AST/ALT ratio', () {
      final doc = _doc([
        _test('Aspartate Aminotransferase (AST)', 150.0, unit: 'U/L', low: 10.0, high: 40.0),
        _test('Alanine Aminotransferase (ALT)', 60.0, unit: 'U/L', low: 10.0, high: 45.0),
      ], panel: 'Liver Function');
      final result = annotateLabDocument(doc);
      final names = result.patterns.map((p) => p.patternName).toList();
      expect(names, contains('alcoholic_liver_pattern'));
    });
  });
}
