import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/normalize.dart';
import 'package:intellimed_app/schemas.dart';

void main() {
  test('lab normalization produces schema-correct JSON', () {
    final doc = normalizeLabText(
      'Hemoglobin 11.2 g/dL 13.0-17.0\nWBC 7.5 4.0-11.0',
    );
    expect(validateLabReport(doc), isEmpty);
    expect(doc['document_type'], 'lab_report');
  });

  test('prescription normalization produces schema-correct JSON', () {
    final doc = normalizePrescriptionText(
      'Amoxicillin 500 mg twice daily\nAspirin 75 mg once daily',
    );
    expect(validatePrescription(doc), isEmpty);
    expect(doc['document_type'], 'prescription');
  });

  test('normalization output never carries flag fields', () {
    final doc = normalizeLabText('Hemoglobin 11.2 g/dL 13.0-17.0');
    final tests = (doc['panels'] as List).first['tests'] as List;
    for (final t in tests) {
      expect((t as Map).containsKey('abnormal'), isFalse);
      expect(t.containsKey('direction'), isFalse);
    }
  });
}
