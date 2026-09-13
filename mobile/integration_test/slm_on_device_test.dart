// On-device verification for the Qwen3 SLM (plus the retained T5 tokenizer)
// and the X-ray classifier.
//
// These exercise the REAL llama_cpp_dart / flutter_onnxruntime paths against
// the models bundled in the APK, so they only run on a connected Android
// device or emulator:
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
      'Qwen3-0.6B loads and produces a biomarker explanation on device',
      (tester) async {
        final slm = QwenSlmRuntime(
          modelPath: 'assets/models/Qwen3-0.6B-Q3_K_S.gguf',
          // Emits raw-output stats (length, whether the <think> block closed)
          // so a failure here is diagnosable from the test log.
          verbose: true,
        );

        final loadWatch = Stopwatch()..start();
        await slm.load();
        loadWatch.stop();

        expect(
          slm.isReady,
          isTrue,
          reason: 'Qwen3 GGUF failed to load on this device',
        );
        debugPrint('Qwen3 load: ${loadWatch.elapsedMilliseconds} ms');

        final runWatch = Stopwatch()..start();
        final explanation = await slm.explainBiomarker(
          testName: 'Hemoglobin',
          value: '11.2',
          unit: 'g/dL',
          direction: 'low',
        );
        runWatch.stop();
        debugPrint('Explain: ${runWatch.elapsedMilliseconds} ms | $explanation');

        expect(
          explanation.trim(),
          isNotEmpty,
          reason: 'model produced no answer (thinking block never closed?)',
        );
        // The <think> block and echoed ChatML control tokens must be gone.
        expect(explanation, isNot(contains('<think>')));
        expect(explanation, isNot(contains('<|im_end|>')));

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
