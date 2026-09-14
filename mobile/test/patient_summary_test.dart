// Tests for the multi-record patient summary: envelope -> record extraction,
// the deterministic latest-per-key roll-up, the record cards used by the map
// step, chunking under the model's prompt budget, and the clipboard rendering.

import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/api/models.dart';
import 'package:intellimed_app/patient_summary.dart';

Map<String, dynamic> _test(
  String name,
  num? value, {
  String? unit,
  bool abnormal = false,
  String? direction,
  String? severity,
  bool panic = false,
  String? flag,
}) => {
  'test_name': name,
  'raw_test_name': name,
  'value': value,
  'unit': unit,
  'range_low': null,
  'range_high': null,
  'range_raw': null,
  'flag_in_source': ?flag,
  'ocr_confidence': 'high',
  'source_bbox': null,
  if (abnormal) 'abnormal': true,
  'direction': ?direction,
  'severity': ?severity,
  if (panic) 'is_panic_value': true,
};

Map<String, dynamic> _envelope({
  List<Map<String, dynamic>> tests = const [],
  List<Map<String, dynamic>> items = const [],
  List<Map<String, dynamic>> patterns = const [],
  String? summary,
  String kind = 'lab_report',
  String? name,
  num? age,
}) => {
  'kind': kind,
  'engine': 'rule-engine-v2+qwen-summary',
  'stage3': {
    'document_type': kind,
    'patient_context': {
      'name': name,
      'age': age,
      'sex': null,
      'report_date': null,
    },
    'lab_name': 'City Lab',
    'panels': [
      {'panel_name': 'Ungrouped', 'tests': tests},
      if (items.isNotEmpty) {'panel_name': 'Prescribed items', 'items': items},
    ],
    'flagged_patterns': patterns,
  },
  if (summary != null)
    'summary_context': {
      'medical_summary': summary,
      'key_findings': const <String>[],
    },
};

PatientRecord _record(
  Map<String, dynamic> envelope, {
  required DateTime date,
  String sourceLabel = 'This device',
}) => PatientRecord.fromEnvelope(
  ResultEnvelope.fromJson(envelope),
  date: date,
  sourceLabel: sourceLabel,
);

Map<String, dynamic> _med(String medication, String dosage, String frequency) =>
    {
      'medication': medication,
      'dosage': dosage,
      'frequency': frequency,
    };

Map<String, dynamic> _pattern(String name, String severity) => {
  'pattern_name': name,
  'surfaced_text': name,
  'match_type': 'all',
  'panel_name': 'Ungrouped',
  'severity': severity,
  'category': 'Haematology',
  'clinical_implication': 'Review.',
  'differential_diagnosis': const <String>[],
  'triggering_tests': const <Map<String, dynamic>>[],
};

void main() {
  group('record extraction', () {
    test('pulls tests, medicines, patterns and the stored summary', () {
      final record = _record(
        _envelope(
          tests: [
            _test('Hemoglobin', 11.2, unit: 'g/dL', abnormal: true, direction: 'low'),
          ],
          items: [_med('amoxicillin', '500 mg', 'TID')],
          patterns: [_pattern('anaemia', 'warning')],
          summary: 'Low haemoglobin.',
          name: 'Asha',
          age: 42,
        ),
        date: DateTime(2026, 3, 1),
      );

      expect(record.kind, 'lab_report');
      expect(record.storedSummary, 'Low haemoglobin.');
      expect(record.patientName, 'Asha');
      expect(record.tests.single.name, 'Hemoglobin');
      expect(record.tests.single.abnormal, isTrue);
      expect(record.meds.single.medication, 'amoxicillin');
      expect(record.patterns.single.name, 'anaemia');
    });
  });

  group('deterministic roll-up', () {
    test('keeps the latest reading per analyte and ranks critical first', () {
      final january = _record(
        _envelope(tests: [
          _test('Hemoglobin', 11.2, unit: 'g/dL', abnormal: true, direction: 'low'),
        ]),
        date: DateTime(2026, 1, 10),
      );
      final march = _record(
        _envelope(tests: [
          _test(
            'Hemoglobin',
            9.4,
            unit: 'g/dL',
            abnormal: true,
            direction: 'low',
            severity: 'severe',
          ),
          _test('Potassium', 6.9, unit: 'mmol/L', panic: true, severity: 'critical'),
        ]),
        date: DateTime(2026, 3, 10),
      );

      final facts = buildFacts([march, january]);
      expect(facts.recordCount, 2);
      expect(facts.earliest, DateTime(2026, 1, 10));
      expect(facts.latest, DateTime(2026, 3, 10));

      // Latest Haemoglobin wins; the panic Potassium is the critical value.
      expect(facts.criticalValues.single.name, 'Potassium');
      expect(facts.abnormalHighlights.single.name, 'Hemoglobin');
      expect(facts.abnormalHighlights.single.value, 9.4);
    });

    test('keeps the latest dose for each medicine', () {
      final first = _record(
        _envelope(
          kind: 'prescription',
          items: [_med('amoxicillin', '250 mg', 'TID')],
        ),
        date: DateTime(2026, 1, 1),
      );
      final second = _record(
        _envelope(
          kind: 'prescription',
          items: [_med('Amoxicillin', '500 mg', 'BID')],
        ),
        date: DateTime(2026, 2, 1),
      );

      final facts = buildFacts([first, second]);
      expect(facts.currentMeds, hasLength(1));
      expect(facts.currentMeds.single.dosage, '500 mg');
      expect(facts.currentMeds.single.frequency, 'BID');
    });

    test('dedupes patterns keeping the more serious severity', () {
      final first = _record(
        _envelope(patterns: [_pattern('severe_anemia', 'warning')]),
        date: DateTime(2026, 1, 1),
      );
      final second = _record(
        _envelope(patterns: [_pattern('severe_anemia', 'critical')]),
        date: DateTime(2026, 2, 1),
      );

      final facts = buildFacts([first, second]);
      expect(facts.patterns, hasLength(1));
      expect(facts.patterns.single.severity, 'critical');
    });

    test('summarises a change over time for repeated analytes', () {
      final facts = buildFacts([
        _record(
          _envelope(tests: [_test('Hemoglobin', 13.1, unit: 'g/dL')]),
          date: DateTime(2026, 1, 5),
        ),
        _record(
          _envelope(tests: [_test('Hemoglobin', 11.2, unit: 'g/dL')]),
          date: DateTime(2026, 3, 5),
        ),
      ]);

      expect(facts.trendHighlights, hasLength(1));
      expect(facts.trendHighlights.single, contains('Hemoglobin'));
      expect(facts.trendHighlights.single, contains('13.1'));
      expect(facts.trendHighlights.single, contains('11.2'));
    });

    test('empty input yields an empty roll-up', () {
      final facts = buildFacts(const []);
      expect(facts.isEmpty, isTrue);
      expect(facts.countsByKind, isEmpty);
    });
  });

  group('record cards', () {
    test('prefers the stored summary and still lists medicines', () {
      final card = buildRecordCard(
        _record(
          _envelope(
            kind: 'prescription',
            items: [_med('amoxicillin', '500 mg', 'TID')],
            summary: 'Antibiotic course for five days.',
          ),
          date: DateTime(2026, 3, 1),
        ),
      );
      expect(card, contains('Prescription'));
      expect(card, contains('Antibiotic course for five days.'));
      expect(card, contains('Medicine: amoxicillin 500 mg TID'));
    });

    test('derives facts when no summary was stored', () {
      final card = buildRecordCard(
        _record(
          _envelope(tests: [
            _test('Hemoglobin', 9.4, unit: 'g/dL', abnormal: true, direction: 'low'),
          ]),
          date: DateTime(2026, 3, 1),
        ),
      );
      expect(card, contains('Hemoglobin 9.4 g/dL (below range)'));
    });
  });

  group('chunking', () {
    test('respects the budget and preserves order', () {
      final cards = [for (var i = 0; i < 10; i++) 'card-$i-xxxxxxxx'];
      final chunks = chunkCardsByBudget(cards, charBudget: 25);

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(25));
      }
      expect(chunks.first, startsWith('card-0-'));
      expect(chunks.join('\n\n'), contains('card-9-'));
    });

    test('an oversized single card is capped, never dropped', () {
      final chunks = chunkCardsByBudget(['x' * 100], charBudget: 20);
      expect(chunks, hasLength(1));
      expect(chunks.single.length, 20);
    });
  });

  group('clipboard rendering', () {
    test('includes the header, narrative, facts and disclaimer', () {
      final facts = buildFacts([
        _record(
          _envelope(
            tests: [_test('Potassium', 6.9, unit: 'mmol/L', panic: true)],
            name: 'Asha',
            age: 42,
          ),
          date: DateTime(2026, 3, 1),
        ),
      ]);
      final text = renderPatientSummaryText(facts, const [], 'A short narrative.');

      expect(text, contains('PATIENT SUMMARY'));
      expect(text, contains('Asha'));
      expect(text, contains('A short narrative.'));
      expect(text, contains('AT A GLANCE'));
      expect(text, contains('Critical values:'));
      expect(text, contains('Potassium'));
      expect(text.toLowerCase(), contains('not medical advice'));
    });

    test('says so when no narrative was generated', () {
      final facts = buildFacts([
        _record(_envelope(tests: [_test('WBC', 7.5)]), date: DateTime(2026, 3, 1)),
      ]);
      expect(
        renderPatientSummaryText(facts, const [], null),
        contains('Summary not available on this device.'),
      );
    });
  });
}
