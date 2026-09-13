// End-to-end verification of the on-device document pipeline.
//
// Unlike the unit tests, these drive the REAL ML Kit OCR, the real ONNX
// Runtime sessions, and the real ModelManager orchestration. They need a
// connected Android device/emulator:
//
//     flutter test integration_test/ -d <device-id>
//
// Text is rendered to a PNG with the engine's own text rasterizer, so OCR is
// exercised against genuine rasterized glyphs rather than a hand-built bitmap.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intellimed_app/cnn_ocr.dart';
import 'package:intellimed_app/lab/rule_engine.dart';
import 'package:intellimed_app/lab/structure.dart';
import 'package:intellimed_app/model_manager.dart';
import 'package:intellimed_app/schemas.dart';
import 'package:path_provider/path_provider.dart';

Future<Directory> _tmpDir() async => getTemporaryDirectory();

/// Render [lines] as black text on white and write it to a PNG file.
Future<File> _renderTextImage(List<String> lines, {String name = 'doc'}) async {
  const width = 1000;
  final height = 120 + lines.length * 52;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  var y = 40.0;
  for (final line in lines) {
    final painter = TextPainter(
      text: TextSpan(
        text: line,
        style: const TextStyle(
          color: Color(0xFF000000),
          fontSize: 34,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 60);
    painter.paint(canvas, Offset(30, y));
    y += 52;
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  final dir = await _tmpDir();
  final file = File('${dir.path}/$name.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file;
}

/// A synthetic image of the right shape for the classifier.
Future<File> _renderXrayLike({String name = 'xray'}) async {
  const size = 512;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF303030), Color(0xFFB0B0B0)],
      ).createShader(rect),
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();

  final dir = await _tmpDir();
  final file = File('${dir.path}/$name.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'OCR reads rendered lab-report text',
    (tester) async {
      final file = await _renderTextImage([
        'CITY DIAGNOSTIC LABORATORY',
        'Hemoglobin 11.2 g/dL 13.0-17.0',
        'WBC 7.5 4.0-11.0',
        'Glucose 98 mg/dL',
      ], name: 'lab_ocr');

      final ocr = OcrService();
      final text = await ocr.recognizeFile(file);
      ocr.close();
      debugPrint('OCR RAW >>>\n$text\n<<<');

      expect(text.trim(), isNotEmpty, reason: 'ML Kit returned no text');
      final lower = text.toLowerCase();
      expect(lower, contains('hemoglobin'));
      expect(lower, contains('wbc'));
      expect(lower, contains('glucose'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'OCR geometry flows through structure synthesis and the rule engine',
    (tester) async {
      final file = await _renderTextImage([
        'Hemoglobin 11.2 g/dL 13.0-17.0',
        'WBC 7.5 4.0-11.0',
        'Platelet Count 250 150-400',
      ], name: 'lab_norm');

      final ocr = OcrService();
      final pages = await ocr.recognizePages([file]);
      ocr.close();
      debugPrint(
        'OCR PAGES >>> ${pages.length} page(s), '
        '${pages.first.lines.length} lines, '
        '${pages.first.pixelWidth}x${pages.first.pixelHeight}',
      );

      final stage1 = buildStage1(pages);
      final normalized = buildLabDocument(stage1).toJson();
      debugPrint('STAGE1 ENGINE >>> ${stage1.extractionEngine}');
      debugPrint('NORMALIZED >>> ${prettyJson(normalized)}');

      final problems = validateLabReport(normalized);
      expect(
        problems,
        isEmpty,
        reason: 'real OCR text produced schema-invalid output: $problems',
      );

      final panels = normalized['panels'] as List;
      final tests = panels.isEmpty
          ? const []
          : (panels.first as Map)['tests'] as List; // ignore: avoid_dynamic_calls
      expect(
        tests,
        isNotEmpty,
        reason: 'rule engine extracted no tests from real OCR text',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'CNN classifies an image end to end',
    (tester) async {
      final cnn = await CnnClassifier.load(
        modelAsset: 'assets/models/pneumonia_resnet50.onnx',
      );
      expect(cnn.isReady, isTrue, reason: 'loadError=${cnn.loadError}');

      final file = await _renderXrayLike();
      final result = await cnn.classifyFile(file);
      debugPrint(
        'CNN >>> top=${result.topPattern} '
        'conf=${result.confidence.toStringAsFixed(4)} '
        'probs=${result.probabilities} ${result.latencyMs}ms',
      );

      expect(xrayLabels, contains(result.topPattern));
      expect(result.confidence, greaterThan(0));
      expect(result.confidence, lessThanOrEqualTo(1.0));

      // Softmax must be a real distribution: non-negative and summing to 1.
      var sum = 0.0;
      for (final p in result.probabilities.values) {
        expect(p, greaterThanOrEqualTo(0.0));
        expect(p, lessThanOrEqualTo(1.0));
        sum += p;
      }
      expect(sum, closeTo(1.0, 1e-4));
      expect(result.probabilities.length, xrayLabels.length);

      await cnn.close();
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'full processDocument pipeline: OCR -> rule engine + SLM -> validate -> store',
    (tester) async {
      final models = ModelManager(
        cnnAsset: 'assets/models/pneumonia_resnet50.onnx',
        slmGgufAsset: 'assets/models/Qwen3-0.6B-Q3_K_S.gguf',
      );
      await models.init();
      try {
        final file = await _renderTextImage([
          'Hemoglobin 11.2 g/dL 13.0-17.0',
          'WBC 7.5 4.0-11.0',
          'Patient reports fever and productive cough for three days.',
        ], name: 'lab_full');

        final envelope = await models.processDocument(
          source: file,
          kind: 'lab_report',
        );
        debugPrint('ENVELOPE >>> ${prettyJson(envelope)}');

        expect(envelope['kind'], 'lab_report');
        expect(envelope['source'], 'app');
        expect(envelope['normalized'], isA<Map<String, dynamic>>());
        expect(envelope['latency_ms'], isA<int>());
        // The rule engine must have produced at least one test.
        final normalized = envelope['normalized'] as Map<String, dynamic>;
        final panels = normalized['panels'] as List;
        expect(panels, isNotEmpty, reason: 'no panels in the lab envelope');
        // The on-device SLM should have been exercised, not skipped.
        expect(
          envelope['engine'],
          contains('qwen-summary'),
          reason: 'SLM summariser did not run in the default pipeline',
        );
        expect(envelope['summary_context'], isA<Map<String, dynamic>>());

        // Provenance tells a reviewer how the structure was reconstructed.
        final structure = envelope['structure'] as Map<String, dynamic>;
        expect(structure['engine'], isA<String>());
        expect(structure['tables'], isA<int>());
        expect(structure['tests'], greaterThan(0));
        expect(structure['confidence'], isIn(['high', 'medium', 'low']));
        expect(structure['pages_without_tables'], isA<List>());
      } finally {
        await models.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  testWidgets(
    'full processXray pipeline: classify -> envelope',
    (tester) async {
      final models = ModelManager(
        cnnAsset: 'assets/models/pneumonia_resnet50.onnx',
        slmGgufAsset: 'assets/models/Qwen3-0.6B-Q3_K_S.gguf',
      );
      await models.init();
      try {
        final file = await _renderXrayLike(name: 'xray_full');
        final envelope = await models.processXray(source: file);
        debugPrint('XRAY ENVELOPE >>> ${prettyJson(envelope)}');

        expect(envelope['kind'], 'xray');
        expect(envelope['source'], 'app');
        final normalized = envelope['normalized'] as Map<String, dynamic>;
        expect(normalized['document_type'], 'xray');
        expect(normalized['top_pattern'], isNotNull);
        expect(xrayLabels, contains(normalized['top_pattern']));
      } finally {
        await models.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
