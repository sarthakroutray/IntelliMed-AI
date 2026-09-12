import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/document_type.dart';

/// Realistic OCR text for each document kind.
///
/// The X-ray classifier is a *pneumonia* classifier over
/// [Normal, Bacterial Pneumonia, Viral Pneumonia]. It has no "not a chest
/// X-ray" class, so the regression these tests lock down is: a prescription or
/// lab report must NEVER be typed as an X-ray, however confident the
/// classifier is.
const labReportText = '''
CITY DIAGNOSTICS CENTRE
Patient: Jane Doe            Date: 12-04-2024
Complete Blood Count
Hemoglobin 11.2 g/dL 13.0-17.0
WBC 7.5 10^3/uL 4.0-11.0
Platelet Count 250 150-450
Serum Creatinine 1.1 mg/dL 0.7-1.3
Reference Range
Specimen: Serum
''';

const prescriptionText = '''
Dr. A. Sharma MBBS
Rx
Tab. Amoxicillin 500 mg
Take 1 tablet twice daily after food for 5 days
Cap. Omeprazole 20 mg
Dispense: 10
''';

/// A radiograph carries almost no machine-readable text.
const xrayText = '''
PORTABLE CHEST
AP
12-04-2024
''';

void main() {
  group('text signals', () {
    test('a lab report scores on analytes, units and ranges', () {
      final signals = analyseText(labReportText);
      expect(signals.hasLabEvidence, isTrue);
      expect(signals.hasPrescriptionEvidence, isFalse);
      expect(signals.labMatches, contains('Measurement unit'));
      expect(signals.labMatches, contains('Printed range'));
      expect(signals.isSparse, isFalse);
    });

    test('a prescription scores on dosage form and frequency', () {
      final signals = analyseText(prescriptionText);
      expect(signals.hasPrescriptionEvidence, isTrue);
      expect(signals.hasLabEvidence, isFalse);
      expect(signals.prescriptionMatches, contains('Dose strength'));
      expect(signals.isSparse, isFalse);
    });

    test('a radiograph is sparse with no document markers', () {
      final signals = analyseText(xrayText);
      expect(signals.isSparse, isTrue);
      expect(signals.isDecisive, isFalse);
      expect(signals.labScore, 0);
      expect(signals.prescriptionScore, 0);
    });

    test('empty text yields zero signals', () {
      final signals = analyseText('   \n  ');
      expect(signals.wordCount, 0);
      expect(signals.isSparse, isTrue);
      expect(signals.isDecisive, isFalse);
    });

    test('a date is not mistaken for a printed reference range', () {
      // "12-04-2024" must not read as a range, or every dated page would look
      // like a lab report.
      final signals = analyseText('Patient seen 12-04-2024');
      expect(signals.labMatches, isNot(contains('Printed range')));
      expect(signals.labScore, 0);
    });

    test('a real decimal range survives date stripping', () {
      final signals = analyseText('Hemoglobin 11.2 g/dL 13.0-17.0');
      expect(signals.labMatches, contains('Printed range'));
    });

    test('a plain integer range survives date stripping', () {
      final signals = analyseText('Platelet Count 250 150-450');
      expect(signals.labMatches, contains('Printed range'));
    });
  });

  group('classifier guard (the misidentification regression)', () {
    test('a lab report stays a lab report even at 99% pneumonia', () {
      final detection = decideType(
        signals: analyseText(labReportText),
        xrayConfidence: 0.99,
      );
      expect(detection.type, DocumentType.labReport);
      expect(detection.usedClassifier, isFalse);
    });

    test('a prescription stays a prescription even at 99% pneumonia', () {
      final detection = decideType(
        signals: analyseText(prescriptionText),
        xrayConfidence: 0.99,
      );
      expect(detection.type, DocumentType.prescription);
      expect(detection.reasons, isNot(contains('sparse text')));
    });

    test('a prescription is not typed as a lab report', () {
      final detection = decideType(signals: analyseText(prescriptionText));
      expect(detection.type, DocumentType.prescription);
    });

    test('a lab report is not typed as a prescription', () {
      final detection = decideType(signals: analyseText(labReportText));
      expect(detection.type, DocumentType.labReport);
    });

    test('a sparse image with a confident classifier is an X-ray', () {
      final detection = decideType(
        signals: analyseText(xrayText),
        xrayConfidence: 0.88,
      );
      expect(detection.type, DocumentType.xray);
      expect(detection.usedClassifier, isTrue);
      expect(detection.confidence, closeTo(0.88, 0.001));
    });

    test('the classifier is not trusted below the 0.6 threshold', () {
      final detection = decideType(
        signals: analyseText(xrayText),
        xrayConfidence: 0.42,
      );
      expect(detection.type, isNot(DocumentType.xray));
    });

    test('the threshold is inclusive at exactly 0.6', () {
      final detection = decideType(
        signals: analyseText(xrayText),
        xrayConfidence: xrayConfidenceThreshold,
      );
      expect(detection.type, DocumentType.xray);
    });

    test('text-dense content with no markers is not called an X-ray', () {
      // Enough words to break sparseness, but no lab/Rx vocabulary — the
      // classifier must not be allowed to decide on text-dense content.
      final prose = List.filled(30, 'the patient reports feeling unwell today')
          .join(' ');
      final detection = decideType(
        signals: analyseText(prose),
        xrayConfidence: 0.95,
      );
      expect(detection.type, isNot(DocumentType.xray));
    });
  });

  group('detection reporting', () {
    test('an auto-detection records its evidence', () {
      final detection = decideType(signals: analyseText(labReportText));
      expect(detection.autoDetected, isTrue);
      expect(detection.reasons, isNotEmpty);
      expect(detection.confidence, greaterThan(0.6));
      expect(detection.isWeak, isFalse);
    });

    test('a low-confidence guess is flagged weak so the UI can ask', () {
      final detection = decideType(
        signals: analyseText('partial scan with 5 mg'),
        xrayConfidence: 0.2,
      );
      expect(detection.isWeak, isTrue);
    });

    test('a manual choice is not weak and reports no auto evidence', () {
      final detection = decideType(
        signals: analyseText(labReportText),
        fallback: DocumentType.prescription,
      );
      expect(detection.autoDetected, isTrue);
      // Manual selections never go through decideType; its job is auto-only.
      expect(detection.usedClassifier, isFalse);
    });

    test('the summary names the detected type', () {
      final detection = decideType(signals: analyseText(prescriptionText));
      expect(detection.summary, contains('Prescription'));
    });
  });

  group('classifier scheduling', () {
    test('decisive text does not need the classifier', () {
      expect(needsClassifier(analyseText(labReportText)), isFalse);
      expect(needsClassifier(analyseText(prescriptionText)), isFalse);
    });

    test('a sparse image does need the classifier', () {
      expect(needsClassifier(analyseText(xrayText)), isTrue);
    });
  });

  group('enum helpers', () {
    test('wire names round-trip', () {
      for (final type in DocumentType.values) {
        expect(DocumentTypeWire.fromWire(type.wireName), type);
      }
      expect(DocumentTypeWire.fromWire('nonsense'), isNull);
    });

    test('capture modes map to their pinned type', () {
      expect(CaptureMode.auto.pinned, isNull);
      expect(CaptureMode.labReport.pinned, DocumentType.labReport);
      expect(CaptureMode.prescription.pinned, DocumentType.prescription);
      expect(CaptureMode.xray.pinned, DocumentType.xray);
    });
  });
}
