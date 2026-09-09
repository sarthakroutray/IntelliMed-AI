import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/t5_tokenizer.dart';

void main() {
  test('T5 Dart tokenizer matches HF reference vectors', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tok = await T5Tokenizer.load('assets/models/t5_tokenizer.json');
    final lines = await File(
      'assets/sample/t5_parity_vectors.txt',
    ).readAsLines();
    final inputs = [
      'summarize: The patient was prescribed Amoxicillin 500 mg twice daily for 7 days.',
      'summarize: Hemoglobin 11.2 g/dL WBC 7.5 Glucose 98 mg/dL',
      'summarize: Take after meals.',
    ];
    expect(lines.length, inputs.length);
    for (var i = 0; i < inputs.length; i++) {
      final expected = lines[i]
          .replaceAll('[', '')
          .replaceAll(']', '')
          .split(',')
          .map((s) => int.parse(s.trim()))
          .toList();
      final actual = tok.encode(inputs[i]);
      expect(actual, expected, reason: 'mismatch on input $i: ${inputs[i]}');
    }
  });
}
