import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:intellimed_app/cnn_ocr.dart';
import 'package:intellimed_app/inference_queue.dart';
import 'package:intellimed_app/slm_runtime.dart';

void main() {
  test('SLM output parser rejects flag fields', () {
    final bad = jsonEncode({
      'document_type': 'lab_report',
      'patient_context': {},
      'lab_name': null,
      'panels': [
        {
          'panel_name': 'CBC',
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
              'abnormal': true,
            },
          ],
        },
      ],
    });
    expect(() => parseSlmOutput(bad), throwsFormatException);
  });

  test('SLM output parser accepts schema-correct JSON', () {
    final good = jsonEncode({
      'document_type': 'lab_report',
      'patient_context': {},
      'lab_name': null,
      'panels': [
        {
          'panel_name': 'CBC',
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
    });
    expect(parseSlmOutput(good)['document_type'], 'lab_report');
  });

  test('inference queue serializes overlapping calls', () async {
    final queue = InferenceQueue();
    final order = <int>[];
    Future<int> slowTask(int id) async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      order.add(id);
      return id;
    }

    final results = await Future.wait([
      queue.add(() => slowTask(1)),
      queue.add(() => slowTask(2)),
      queue.add(() => slowTask(3)),
    ]);
    expect(results, [1, 2, 3]);
    expect(order, [1, 2, 3]);
  });

  test('xray preprocess matches ImageNet mean/std NCHW layout', () {
    final src = img.Image(width: 4, height: 4);
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        src.setPixelRgb(x, y, 255, 255, 255);
      }
    }
    final flat = CnnClassifier.preprocessXray(src);
    expect(flat.length, 1 * 3 * xrayInputSize * xrayInputSize);
    // White pixel -> (1 - mean) / std per channel, first element is R of (0,0).
    expect(flat[0], closeTo((1 - xrayMean[0]) / xrayStd[0], 1e-6));
    final gStart = xrayInputSize * xrayInputSize;
    expect(flat[gStart], closeTo((1 - xrayMean[1]) / xrayStd[1], 1e-6));
  });

  test('sync payload is tagged source=app', () async {
    Map<String, dynamic>? sent;
    final client = MockClient((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'id': 7}), 200);
    });
    final uri = Uri.parse('http://x/api/v2/lab-reports/upload-structured');
    await client.post(
      uri,
      body: jsonEncode({'kind': 'lab_report', 'source': 'app'}),
    );
    expect(sent!['source'], 'app');
  });
}
