// On-device verification for the T5 summariser and the X-ray classifier.
//
// These exercise the REAL flutter_onnxruntime path against the models bundled
// in the APK, so they only run on a connected Android device or emulator:
//
//     flutter test integration_test/slm_on_device_test.dart -d <device-id>
//
// A plain `flutter test` (Dart VM, no plugin host) cannot run these.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intellimed_app/cnn_ocr.dart';
import 'package:intellimed_app/slm_runtime.dart';
import 'package:intellimed_app/t5_tokenizer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('on-device inference', () {
    testWidgets('T5 tokenizer loads from the bundled asset', (tester) async {
      final tokenizer = await T5Tokenizer.load();
      expect(tokenizer.vocabSize, 32100);
      expect(tokenizer.eosId, 1);

      final ids = tokenizer.encode('summarize: hemoglobin 11.2 g/dL');
      expect(ids, isNotEmpty);
      expect(ids.last, tokenizer.eosId);
      // Round-trips through the decoder without throwing.
      expect(tokenizer.decode(ids), isA<String>());
    });

    testWidgets(
      'T5 summariser loads and produces a summary on device',
      (tester) async {
        final slm = OnnxSummarizer();

        final loadWatch = Stopwatch()..start();
        await slm.load();
        loadWatch.stop();

        expect(
          slm.isReady,
          isTrue,
          reason: 'T5 encoder/decoder failed to load on this device',
        );
        debugPrint('SLM load: ${loadWatch.elapsedMilliseconds} ms');

        final runWatch = Stopwatch()..start();
        final out = await slm.summarize(
          'Hemoglobin 11.2 g/dL 13.0-17.0. WBC 7.5 4.0-11.0. '
          'Patient reports fever and productive cough for three days.',
        );
        runWatch.stop();
        debugPrint(
          'SLM summarize: ${runWatch.elapsedMilliseconds} ms | '
          'input_tokens=${out['input_tokens']} '
          'decode_steps=${out['decode_steps']}',
        );
        debugPrint('SLM summary: ${out['medical_summary']}');

        final summary = out['medical_summary'];
        expect(summary, isA<String>());
        expect(
          (summary as String).trim(),
          isNotEmpty,
          reason: 'greedy decode produced an empty summary',
        );
        expect(out['summary_length'], greaterThan(0));
        expect(out['decode_steps'], greaterThan(0));
        expect(out['latency_ms'], isA<int>());

        await slm.close();
        expect(slm.isReady, isFalse);
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    testWidgets(
      'X-ray CNN classifier loads on device',
      (tester) async {
        final cnn = await CnnClassifier.load(
          modelAsset: 'assets/models/pneumonia_resnet50.onnx',
        );
        // loadError distinguishes a real ORT failure from an absent model.
        expect(cnn.isReady, isTrue, reason: 'loadError=${cnn.loadError}');
        await cnn.close();
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
