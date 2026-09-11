import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/api/models.dart';

/// A server-pipeline lab report: has stage1 (a big OCR tree), stage2, stage3
/// with annotated per-test fields and flagged patterns.
Map<String, dynamic> pipelineEnvelope() => {
  'pipeline': 'lab-report-understanding/v2',
  'stage1': {
    'stage': 1,
    'extraction_engine': 'opendataloader-json',
    'text': 'Hemoglobin 11.2 g/dL 13.0-17.0',
    'elements': [
      {'type': 'text', 'text': 'Hb', 'bbox': [1, 2, 3, 4], 'page': 1},
    ],
    'tables': [],
    'raw': {'huge': 'blob we never render'},
    'warnings': [],
  },
  'stage2': {
    'document_type': 'lab_report',
    'patient_context': {'name': null, 'age': null, 'sex': null},
    'lab_name': 'City Labs',
    'panels': [
      {
        'panel_name': 'Complete Blood Count',
        'tests': [
          {
            'test_name': 'Hemoglobin',
            'raw_test_name': 'Hb',
            'value': 11.2,
            'unit': 'g/dL',
            'range_low': 13.0,
            'range_high': 17.0,
            'range_raw': '13.0-17.0',
            'flag_in_source': 'L',
            'ocr_confidence': 'high',
            'source_bbox': {'page': 1, 'bbox': [72.0, 210.5, 180.0, 224.0]},
          },
        ],
      },
    ],
  },
  'stage2_engine': 'deterministic-v1',
  'stage3': {
    'document_type': 'lab_report',
    'lab_name': 'City Labs',
    'patient_context': {'name': null},
    'panels': [
      {
        'panel_name': 'Complete Blood Count',
        'tests': [
          {
            'test_name': 'Hemoglobin',
            'raw_test_name': 'Hb',
            'value': 11.2,
            'unit': 'g/dL',
            'range_low': 13.0,
            'range_high': 17.0,
            'range_raw': '13.0-17.0',
            'flag_in_source': 'L',
            'ocr_confidence': 'high',
            'source_bbox': {'page': 1, 'bbox': [72.0, 210.5, 180.0, 224.0]},
            'abnormal': true,
            'direction': 'low',
          },
        ],
      },
    ],
    'flagged_patterns': [
      {
        'pattern_name': 'PLACEHOLDER_anaemia_pattern',
        'surfaced_text': 'Combined low pattern — recommend clinical review',
        'match_type': 'all',
        'panel_name': 'Complete Blood Count',
        'triggering_tests': [
          {
            'test_name': 'Hemoglobin',
            'raw_test_name': 'Hb',
            'value': 11.2,
            'unit': 'g/dL',
            'direction': 'low',
            'source_bbox': {'page': 1, 'bbox': [72.0, 210.5, 180.0, 224.0]},
          },
        ],
      },
    ],
  },
  'warnings': ['easyocr fallback used: no bounding boxes'],
  'rules_review_status':
      'UNREVIEWED PLACEHOLDERS — DO NOT USE ON REAL PATIENT DATA WITHOUT CLINICAL REVIEW',
};

/// A server app-ingest report: no stage1, but ocr_excerpt/latency/summary.
Map<String, dynamic> appEnvelope() => {
  'pipeline': 'lab-report-understanding/v2',
  'stage2': {
    'document_type': 'lab_report',
    'patient_context': {'name': null},
    'panels': [
      {
        'panel_name': 'Ungrouped',
        'tests': [
          {
            'test_name': 'White Blood Cell Count',
            'raw_test_name': 'WBC',
            'value': 7.5,
            'unit': null,
            'range_low': 4.0,
            'range_high': 11.0,
            'range_raw': '4.0-11.0',
            'flag_in_source': null,
            'ocr_confidence': 'low',
            'source_bbox': null,
          },
        ],
      },
    ],
  },
  'stage2_engine': 'app-on-device',
  'stage3': {
    'document_type': 'lab_report',
    'panels': [
      {
        'panel_name': 'Ungrouped',
        'tests': [
          {
            'test_name': 'White Blood Cell Count',
            'raw_test_name': 'WBC',
            'value': 7.5,
            'range_low': 4.0,
            'range_high': 11.0,
            'abnormal': false,
            'direction': null,
          },
        ],
      },
    ],
    'flagged_patterns': [],
  },
  'warnings': [],
  'rules_review_status': 'UNREVIEWED PLACEHOLDERS',
  'ocr_excerpt': 'WBC 7.5 4.0-11.0',
  'latency_ms': 412,
  'summary_context': {
    'medical_summary': 'CBC within normal limits.',
    'key_findings': ['No abnormalities detected'],
  },
};

/// The local on-device envelope: `normalized`, no stage2/stage3, no flags.
Map<String, dynamic> localEnvelope() => {
  'kind': 'lab_report',
  'engine': 'deterministic-v1+t5-q8',
  'latency_ms': 88,
  'normalized': {
    'document_type': 'lab_report',
    'patient_context': {'name': null},
    'panels': [
      {
        'panel_name': 'Ungrouped',
        'tests': [
          {
            'test_name': 'Hemoglobin',
            'raw_test_name': 'Hb',
            'value': 11.2,
            'unit': 'g/dL',
            'range_low': 13.0,
            'range_high': 17.0,
            'range_raw': '13.0-17.0',
            'flag_in_source': null,
            'ocr_confidence': 'high',
            'source_bbox': null,
          },
        ],
      },
    ],
  },
  'ocr_excerpt': 'Hb 11.2',
  'source': 'app',
};

void main() {
  group('pipeline envelope', () {
    test('parses panels, tests and traceable patterns', () {
      final env = ResultEnvelope.fromJson(pipelineEnvelope());

      expect(env.kind, 'lab_report');
      expect(env.hasStage1, isTrue);
      expect(env.hasStage3, isTrue);
      expect(env.labName, 'City Labs');
      expect(env.testCount, 1);

      final test0 = env.panels.first.tests.first;
      expect(test0.testName, 'Hemoglobin');
      expect(test0.value, 11.2);
      expect(test0.abnormal, isTrue);
      expect(test0.direction, 'low');
      expect(test0.rangeLabel, '13 – 17');
      expect(test0.locationLabel, 'p.1');

      expect(env.abnormalTests, hasLength(1));
      expect(env.flaggedPatterns, hasLength(1));
      final pattern = env.flaggedPatterns.first;
      expect(pattern.panelName, 'Complete Blood Count');
      expect(pattern.triggeringTests, hasLength(1));
      expect(pattern.triggeringTests.first.summary, '11.2 g/dL (low)');
    });

    test('surfaces unreviewed rule tables and extraction warnings', () {
      final env = ResultEnvelope.fromJson(pipelineEnvelope());
      expect(env.rulesUnreviewed, isTrue);
      expect(env.warnings, hasLength(1));
    });
  });

  group('app-ingest envelope', () {
    test('parses without a stage1 tree', () {
      final env = ResultEnvelope.fromJson(appEnvelope());

      expect(env.hasStage1, isFalse);
      expect(env.hasStage3, isTrue);
      expect(env.engine, 'app-on-device');
      expect(env.latencyMs, 412);
      expect(env.ocrExcerpt, 'WBC 7.5 4.0-11.0');
      expect(env.testCount, 1);
    });

    test('carries the on-device summary context', () {
      final env = ResultEnvelope.fromJson(appEnvelope());
      expect(env.summaryContext, isNotNull);
      expect(env.summaryContext!.medicalSummary, 'CBC within normal limits.');
      expect(env.summaryContext!.keyFindings, hasLength(1));
    });

    test('a within-range test is not counted as abnormal', () {
      final env = ResultEnvelope.fromJson(appEnvelope());
      final test0 = env.panels.first.tests.first;
      expect(test0.abnormal, isFalse);
      expect(test0.direction, isNull);
      expect(env.abnormalTests, isEmpty);
      // A missing unit still renders a usable range.
      expect(test0.rangeLabel, '4 – 11');
    });
  });

  group('local envelope', () {
    test('parses normalized data with no Stage 3 annotation', () {
      final env = ResultEnvelope.fromJson(localEnvelope());

      expect(env.kind, 'lab_report');
      expect(env.hasStage3, isFalse);
      expect(env.flaggedPatterns, isEmpty);
      expect(env.testCount, 1);
      // No stage3 means no comparison is available — never claim "normal".
      final test0 = env.panels.first.tests.first;
      expect(test0.abnormal, isNull);
      expect(test0.comparable, isFalse);
      expect(env.incomparableTests, hasLength(1));
    });
  });

  group('defensive parsing', () {
    test('an empty object yields an empty envelope, not a crash', () {
      final env = ResultEnvelope.fromJson(const {});
      expect(env.isEmpty, isTrue);
      expect(env.panels, isEmpty);
      expect(env.flaggedPatterns, isEmpty);
    });

    test('tolerates wrong types and nulls', () {
      final env = ResultEnvelope.fromJson({
        'stage2': {
          'document_type': 'lab_report',
          'panels': 'not-a-list',
          'patient_context': 'not-a-map',
        },
        'stage3': {'panels': [null, 'nope']},
        'warnings': [null, 'real warning'],
        'summary_context': 'not-a-map',
      });
      expect(env.panels, isEmpty);
      expect(env.warnings, ['real warning']);
      expect(env.summaryContext, isNull);
    });

    test('a test with no name still parses', () {
      final env = ResultEnvelope.fromJson({
        'stage2': {
          'document_type': 'lab_report',
          'panels': [
            {
              'tests': [
                {'value': 5},
              ],
            },
          ],
        },
      });
      final test0 = env.panels.first.tests.first;
      expect(test0.testName, 'Unknown');
      expect(env.panels.first.panelName, 'Ungrouped');
    });
  });

  group('xray and prescription envelopes', () {
    test('parses xray probabilities sorted high to low', () {
      final env = ResultEnvelope.fromJson({
        'kind': 'xray',
        'normalized': {
          'document_type': 'xray',
          'top_pattern': 'Bacterial Pneumonia',
          'confidence': 0.71,
          'probabilities': {'Normal': 0.12, 'Bacterial Pneumonia': 0.71},
          'note': 'Structured context for doctor review.',
        },
      });

      expect(env.kind, 'xray');
      expect(env.xray, isNotNull);
      expect(env.xray!.isNormal, isFalse);
      expect(env.xray!.sortedProbabilities.first.key, 'Bacterial Pneumonia');
    });

    test('recognises a normal xray pattern', () {
      final env = ResultEnvelope.fromJson({
        'normalized': {
          'document_type': 'xray',
          'top_pattern': 'Normal',
          'probabilities': {'Normal': 0.93},
        },
      });
      expect(env.xray!.isNormal, isTrue);
    });

    test('parses prescription items out of panels', () {
      final env = ResultEnvelope.fromJson({
        'kind': 'prescription',
        'normalized': {
          'document_type': 'prescription',
          'panels': [
            {
              'panel_name': 'Prescribed items',
              'items': [
                {
                  'medication': 'amoxicillin',
                  'dosage': '500 mg',
                  'frequency': 'twice daily',
                },
              ],
            },
          ],
        },
      });

      expect(env.kind, 'prescription');
      expect(env.prescriptionItems, hasLength(1));
      expect(env.prescriptionItems.first.medication, 'amoxicillin');
    });
  });

  group('detection provenance', () {
    test('parses the on-device detection record', () {
      final env = ResultEnvelope.fromJson({
        'kind': 'prescription',
        'normalized': {'document_type': 'prescription', 'panels': []},
        'detection': {
          'type': 'prescription',
          'confidence': 0.95,
          'auto': true,
          'used_classifier': false,
          'reasons': ['Tab.', 'Dose strength'],
        },
        'page_count': 3,
      });

      expect(env.detection, isNotNull);
      expect(env.detection!.type, 'prescription');
      expect(env.detection!.confidence, closeTo(0.95, 0.001));
      expect(env.detection!.auto, isTrue);
      expect(env.detection!.usedClassifier, isFalse);
      expect(env.detection!.reasons, hasLength(2));
      expect(env.detection!.isWeak, isFalse);
      expect(env.pageCount, 3);
      expect(env.pagesTruncated, isFalse);
    });

    test('flags a weak auto-detection', () {
      final env = ResultEnvelope.fromJson({
        'normalized': {'document_type': 'lab_report', 'panels': []},
        'detection': {'type': 'lab_report', 'confidence': 0.2, 'auto': true},
      });
      expect(env.detection!.isWeak, isTrue);
    });

    test('a manual choice is not weak even at low confidence', () {
      final env = ResultEnvelope.fromJson({
        'normalized': {'document_type': 'xray', 'top_pattern': 'Normal'},
        'detection': {'type': 'xray', 'confidence': 0.3, 'auto': false},
      });
      expect(env.detection!.auto, isFalse);
      expect(env.detection!.isWeak, isFalse);
    });

    test('records a truncated multipage source', () {
      final env = ResultEnvelope.fromJson({
        'normalized': {'document_type': 'lab_report', 'panels': []},
        'page_count': 40,
        'pages_truncated': true,
      });
      expect(env.pageCount, 40);
      expect(env.pagesTruncated, isTrue);
    });

    test('envelopes without detection metadata still parse', () {
      final env = ResultEnvelope.fromJson(appEnvelope());
      expect(env.detection, isNull);
      expect(env.pageCount, isNull);
      expect(env.pagesTruncated, isFalse);
    });
  });

  group('lab report wrapper', () {
    test('parses list and detail shapes', () {
      final report = LabReport.fromJson({
        'id': 42,
        'patient_id': 7,
        'source': 'app',
        'filename': 'report.pdf',
        'file_url': 'https://example.test/signed',
        'upload_timestamp': '2026-01-02T10:15:30.123Z',
        'result': appEnvelope(),
      });

      expect(report.id, 42);
      expect(report.patientId, 7);
      expect(report.fromApp, isTrue);
      expect(report.filename, 'report.pdf');
      expect(report.uploadedAt, isNotNull);
      expect(report.result.testCount, 1);
    });

    test('tolerates a missing result object', () {
      final report = LabReport.fromJson({'id': 1});
      expect(report.result.isEmpty, isTrue);
      expect(report.id, 1);
    });
  });

  group('document analysis', () {
    test('parses the v1 detail analysis shape', () {
      final detail = DocumentDetail.fromJson({
        'id': 5,
        'fileName': 'scan.pdf',
        'status': 'Processed',
        'fileType': 'PDF',
        'fileUrl': 'https://example.test/f',
        'analysis': {
          'summary': {
            'status': 'success',
            'title': 'Normal Detected',
            'classification': 'Normal',
            'confidence': 93.8,
          },
          'findings': [
            {'label': 'Normal', 'confidence': 93.8},
          ],
          'nlp': {
            'summary': 'two medications',
            'entities': [
              {'text': 'Aspirin', 'label': 'MEDICATION'},
            ],
            'medications': ['Aspirin', {'name': 'Metformin'}],
            'prescriptions': [
              {'medication': 'aspirin', 'dosage': '75 mg'},
            ],
            'is_prescription': true,
          },
          'medical_summary': 'Summary text.',
          'key_findings': ['One finding'],
          'ocr_text': 'raw text',
        },
      });

      expect(detail.isPending, isFalse);
      expect(detail.analysis.classification, 'Normal');
      expect(detail.analysis.findings, hasLength(1));
      expect(detail.analysis.entities.first.text, 'Aspirin');
      // Medications arrive as both plain strings and objects.
      expect(detail.analysis.medications, ['Aspirin', 'Metformin']);
      expect(detail.analysis.prescriptions.first.medication, 'aspirin');
      expect(detail.analysis.isPrescription, isTrue);
      expect(detail.analysis.hasContent, isTrue);
    });

    test('a pending document has no analysis content', () {
      final detail = DocumentDetail.fromJson({
        'id': 9,
        'status': 'Pending',
        'analysis': {'summary': {'status': 'pending'}},
      });
      expect(detail.isPending, isTrue);
      expect(detail.analysis.hasContent, isFalse);
    });
  });

  group('profile and doctors', () {
    test('parses profile fields and defaults', () {
      final profile = Profile.fromJson({
        'id': 7,
        'email': 'patient@example.com',
        'name': 'Jane Doe',
        'dark_mode': true,
        'push_notifications': false,
      });
      expect(profile.displayName, 'Jane Doe');
      expect(profile.darkMode, isTrue);
      expect(profile.pushNotifications, isFalse);
      // Absent booleans keep their documented defaults.
      expect(profile.emailNotifications, isTrue);
    });

    test('falls back to the email prefix when name is missing', () {
      final profile = Profile.fromJson({
        'id': 1,
        'email': 'someone@example.com',
      });
      expect(profile.displayName, 'someone');
    });

    test('parses linked doctors', () {
      final doctor = LinkedDoctor.fromJson({
        'id': 3,
        'email': 'dr.smith@example.com',
        'name': 'Dr. Smith',
      });
      expect(doctor.displayName, 'Dr. Smith');
      expect(doctor.initial, 'D');
    });
  });

  group('formatting helpers', () {
    test('strips trailing zeros for display', () {
      expect(formatNumber(11.0), '11');
      expect(formatNumber(11.2), '11.2');
      expect(formatNumber(null), '—');
    });

    test('range label handles each combination', () {
      expect(
        LabTest.fromJson({'range_low': 4.0, 'range_high': 11.0}).rangeLabel,
        '4 – 11',
      );
      expect(
        LabTest.fromJson({'range_low': 4.0}).rangeLabel,
        '≥ 4',
      );
      expect(
        LabTest.fromJson({'range_high': 11.0}).rangeLabel,
        '≤ 11',
      );
      expect(
        LabTest.fromJson({'range_raw': '< 5'}).rangeLabel,
        '< 5',
      );
      expect(LabTest.fromJson(const {}).rangeLabel, isNull);
    });
  });
}
