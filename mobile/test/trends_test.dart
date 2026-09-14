// Tests for the longitudinal trends model: canonical grouping, the unit-change
// split (the one real correctness trap), reference bands, extraction from both
// envelope shapes, and the local/server merge that must not double-count a
// synced capture.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/api/models.dart';
import 'package:intellimed_app/trends.dart';

Map<String, dynamic> _test(
  String name,
  num? value, {
  String? unit,
  num? low,
  num? high,
  String? flag,
}) => {
  'test_name': name,
  'raw_test_name': name,
  'value': value,
  'unit': unit,
  'range_low': low,
  'range_high': high,
  'range_raw': null,
  'flag_in_source': flag,
  'ocr_confidence': 'high',
  'source_bbox': null,
};

Map<String, dynamic> _envelope(List<Map<String, dynamic>> tests) => {
  'kind': 'lab_report',
  'normalized': {
    'document_type': 'lab_report',
    'patient_context': {'name': null},
    'panels': [
      {'panel_name': 'Ungrouped', 'tests': tests},
    ],
  },
};

Map<String, Object?> _row({
  required int id,
  required String createdAt,
  required Map<String, dynamic> envelope,
  int? serverId,
  String kind = 'lab_report',
}) => {
  'id': id,
  'kind': kind,
  'local_path': '/tmp/$id.png',
  'result_json': jsonEncode(envelope),
  'sync_status': 'pending',
  'server_id': serverId,
  'created_at': createdAt,
};

TrendPoint _point(
  String name,
  double value,
  DateTime date, {
  String? unit,
  double? low,
  double? high,
}) => TrendPoint(
  testName: name,
  value: value,
  date: date,
  unit: unit,
  rangeLow: low,
  rangeHigh: high,
);

void main() {
  group('series building', () {
    test('groups by canonical name so abbreviations merge', () {
      final series = buildTrendSeries([
        _point('Hb', 11.2, DateTime(2026, 1, 1), unit: 'g/dL'),
        _point('Hemoglobin', 13.0, DateTime(2026, 2, 1), unit: 'g/dL'),
      ]);
      expect(series, hasLength(1));
      expect(series.single.testName, 'Hemoglobin');
      expect(series.single.points, hasLength(2));
      expect(hasUnitSplit(series), isFalse);
    });

    test('splits a unit change into separate, incomparable series', () {
      final series = buildTrendSeries([
        _point('Hemoglobin', 11.2, DateTime(2026, 1, 1), unit: 'g/dL'),
        _point('Hemoglobin', 120, DateTime(2026, 3, 1), unit: 'g/L'),
      ]);
      expect(series, hasLength(2));
      expect(series.map((s) => s.unit), containsAll(['g/dL', 'g/L']));
      expect(hasUnitSplit(series), isTrue);
    });

    test('unit-less readings form their own series', () {
      final series = buildTrendSeries([
        _point('Platelet Count', 250, DateTime(2026, 1, 1)),
        _point('Platelet Count', 260, DateTime(2026, 2, 1), unit: '10^3/uL'),
      ]);
      expect(series, hasLength(2));
      expect(series.first.unit, isNull);
      expect(series.first.unitLabel, 'no unit');
    });

    test('orders points ascending and series by analyte then unit', () {
      final series = buildTrendSeries([
        _point('Zinc', 1, DateTime(2026, 3, 1), unit: 'ug/dL'),
        _point('Albumin', 4.2, DateTime(2026, 2, 1), unit: 'g/dL'),
        _point('Albumin', 4.0, DateTime(2026, 1, 1), unit: 'g/dL'),
      ]);
      expect(series.map((s) => s.testName), ['Albumin', 'Zinc']);
      expect(
        series.first.points.map((p) => p.value),
        [4.0, 4.2],
        reason: 'points must be in date order',
      );
    });
  });

  group('reference band', () {
    test('uses the latest printed range', () {
      final series = buildTrendSeries([
        _point('Hemoglobin', 11.2, DateTime(2026, 1, 1), unit: 'g/dL', low: 12, high: 16),
        _point('Hemoglobin', 11.8, DateTime(2026, 2, 1), unit: 'g/dL', low: 13, high: 17),
      ]).single;
      expect(series.referenceBand?.low, 13);
      expect(series.referenceBand?.high, 17);
    });

    test('is null when no reading printed a range', () {
      final series = buildTrendSeries([
        _point('Hemoglobin', 11.2, DateTime(2026, 1, 1), unit: 'g/dL'),
      ]).single;
      expect(series.referenceBand, isNull);
    });

    test('handles one-sided ranges', () {
      final series = buildTrendSeries([
        _point('LDL Cholesterol', 230, DateTime(2026, 1, 1), unit: 'mg/dL', high: 200),
      ]).single;
      expect(series.referenceBand?.low, isNull);
      expect(series.referenceBand?.high, 200);
    });
  });

  group('envelope extraction', () {
    test('reads typed tests and skips null values and unknown names', () {
      final points = trendPointsFromEnvelope(
        _envelope([
          _test('Hemoglobin', 11.2, unit: 'g/dL', low: 13, high: 17, flag: 'L'),
          _test('Unmeasured', null),
          _test('Unknown', 5),
        ]),
        date: DateTime(2026, 1, 1),
      );
      expect(points, hasLength(1));
      final point = points.single;
      expect(point.testName, 'Hemoglobin');
      expect(point.value, 11.2);
      expect(point.unit, 'g/dL');
      expect(point.flagInSource, 'L');
      expect(point.hasRange, isTrue);
    });

    test('parses this device\'s rows with a UTC-aware date and source label', () {
      final points = trendPointsFromLocalRows([
        _row(
          id: 3,
          createdAt: '2026-01-02 10:00:00',
          envelope: _envelope([_test('WBC', 7.5, unit: '10^3/uL')]),
        ),
      ]);
      expect(points, hasLength(1));
      expect(points.single.sourceLabel, 'This device');
      expect(points.single.sourceId, 3);
      expect(points.single.date.toUtc(), DateTime.utc(2026, 1, 2, 10));
    });

    test('skips other kinds and malformed rows without failing', () {
      final points = trendPointsFromLocalRows([
        _row(
          id: 1,
          createdAt: '2026-01-02 10:00:00',
          envelope: _envelope([_test('WBC', 7.5)]),
          kind: 'prescription',
        ),
        {
          'id': 2,
          'kind': 'lab_report',
          'result_json': '{not json',
          'created_at': '2026-01-03 10:00:00',
        },
      ]);
      expect(points, isEmpty);
    });
  });

  group('local + server merge', () {
    test('a synced capture is not counted twice', () {
      final rows = [
        _row(
          id: 1,
          createdAt: '2026-01-02 10:00:00',
          serverId: 7,
          envelope: _envelope([_test('Hemoglobin', 11.2, unit: 'g/dL')]),
        ),
      ];
      final reports = [
        LabReport.fromJson({
          'id': 7,
          'filename': 'cbc.pdf',
          'upload_timestamp': '2026-01-02T10:00:00.000Z',
          'result': _envelope([_test('Hemoglobin', 11.2, unit: 'g/dL')]),
        }),
        LabReport.fromJson({
          'id': 8,
          'filename': 'lipid.pdf',
          'upload_timestamp': '2026-02-02T10:00:00.000Z',
          'result': _envelope([_test('LDL Cholesterol', 230, unit: 'mg/dL')]),
        }),
      ];

      final localPoints = trendPointsFromLocalRows(rows);
      final serverPoints = trendPointsFromReports(
        reports,
        skipIds: syncedServerIds(rows),
      );

      final series = buildTrendSeries([...localPoints, ...serverPoints]);
      final hemoglobin = series.firstWhere((s) => s.testName == 'Hemoglobin');
      expect(hemoglobin.points, hasLength(1), reason: 'duplicate was merged');
      expect(series.any((s) => s.testName == 'LDL Cholesterol'), isTrue);
    });

    test('a non-lab row\'s server_id does not hide a lab report', () {
      final rows = [
        _row(
          id: 1,
          createdAt: '2026-01-02 10:00:00',
          serverId: 7,
          kind: 'xray',
          envelope: const {
            'kind': 'xray',
            'normalized': {'document_type': 'xray', 'top_pattern': 'Normal'},
          },
        ),
      ];
      // Server ids are per-table: an X-ray row must not suppress the lab report
      // that happens to share the number.
      expect(syncedServerIds(rows), isEmpty);
    });

    test('reports without a timestamp are skipped', () {
      final reports = [
        LabReport.fromJson({
          'id': 9,
          'filename': 'undated.pdf',
          'result': _envelope([_test('WBC', 7.5)]),
        }),
      ];
      expect(trendPointsFromReports(reports), isEmpty);
    });
  });

  group('sqlite timestamp', () {
    test('treats a zoneless sqlite timestamp as UTC', () {
      expect(
        parseSqliteUtc('2026-01-02 10:00:00')?.toUtc(),
        DateTime.utc(2026, 1, 2, 10),
      );
      expect(parseSqliteUtc(''), isNull);
      expect(parseSqliteUtc('not a date'), isNull);
    });
  });

  group('wording discipline', () {
    test('new trend copy never judges or diagnoses', () {
      const files = [
        'lib/trends.dart',
        'lib/patient_summary.dart',
        'lib/screens/trends_screen.dart',
        'lib/screens/trend_detail_screen.dart',
        'lib/screens/patient_summary_screen.dart',
        'lib/widgets/trend_sparkline.dart',
        'lib/copy.dart',
      ];
      // Evaluative / diagnostic framing belongs to a clinician, not the app.
      const forbidden = ['diagnos', 'improving', 'worsening', 'declining'];

      for (final path in files) {
        final lines = File(path).readAsLinesSync();
        for (final line in lines) {
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
          for (final word in forbidden) {
            expect(
              line.toLowerCase(),
              isNot(contains(word)),
              reason: '$path uses forbidden framing: "$word"',
            );
          }
        }
      }
    });
  });
}
