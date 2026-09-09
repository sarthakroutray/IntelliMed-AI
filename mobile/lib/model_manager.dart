import 'dart:async';
import 'dart:io';

import 'cnn_ocr.dart';
import 'inference_queue.dart';
import 'normalize.dart';
import 'schemas.dart';
import 'slm_runtime.dart';
import 'store.dart';
import 'sync.dart';

/// Owns both model slots and the serial inference queue.
///
/// Default policy: both models stay loaded and resident. Swap-in/swap-out
/// logic is deliberately NOT built — see docs/MEMORY_REPORT.md: it only gets
/// added if real-device measurement shows memory pressure.
class ModelManager {
  ModelManager({
    required this.cnnAsset,
    required this.slmGgufAsset,
    this.eagerLoad = false,
  });

  final String cnnAsset;
  final String slmGgufAsset;
  final bool eagerLoad;

  final InferenceQueue queue = InferenceQueue();
  CnnClassifier? cnn;
  SlmRuntime? slm;
  OcrService? ocr;
  DateTime? cnnLoadedAt;
  DateTime? slmLoadedAt;

  int cnnLoadMs = -1;
  int slmLoadMs = -1;

  Future<void> init() async {
    ocr = OcrService();
    if (eagerLoad) {
      await loadCnn();
      await loadSlm(SlmBackend.onnx);
    }
  }

  Future<CnnClassifier> loadCnn({
    bool lazy = false,
    CnnBackend? backend,
  }) async {
    final started = DateTime.now();
    cnn ??= await CnnClassifier.load(
      modelAsset: cnnAsset,
      lazy: lazy || !eagerLoad,
      backend: backend ?? CnnBackend.onnx,
    );
    cnnLoadedAt ??= DateTime.now();
    cnnLoadMs = DateTime.now().difference(started).inMilliseconds;
    return cnn!;
  }

  Future<SlmRuntime> loadSlm(SlmBackend backend) async {
    final started = DateTime.now();
    slm ??= backend == SlmBackend.llamaCpp
        ? LlamaCppRuntime(modelPath: slmGgufAsset)
        : OnnxSlmRuntime();
    await slm!.load();
    slmLoadedAt ??= DateTime.now();
    slmLoadMs = DateTime.now().difference(started).inMilliseconds;
    return slm!;
  }

  /// Full on-device pass for a captured document image:
  /// OCR -> deterministic schema normalization (+ T5 summary context for
  /// non-prescription docs when the standardizer is loaded) -> store pending.
  Future<Map<String, dynamic>> processDocument({
    required File image,
    required String kind,
    String? token,
    V2Sync? sync,
  }) {
    return queue.add(() async {
      final started = DateTime.now();
      final ocrText = await (ocr ??= OcrService()).recognizeFile(image);
      final normalized = await normalizeInBackground((
        kind == 'xray' ? 'lab_report' : kind,
        ocrText,
      ));
      var engine = 'deterministic-v1';
      Map<String, dynamic>? summaryContext;
      final slmSnapshot = slm;
      if (slmSnapshot is OnnxSlmRuntime &&
          (slmSnapshot.isReady || kind != 'prescription')) {
        // T5 standardizer (same checkpoint as backend
        // `medical_summarize_service`): summary context for review on
        // non-prescription documents. Prescriptions keep the deterministic
        // structured path, mirroring the backend short-circuit.
        try {
          if (!slmSnapshot.isReady) await slmSnapshot.load();
          summaryContext = await slmSnapshot.standardizeText(ocrText);
          engine = 'deterministic-v1+t5-q8';
        } catch (_) {
          summaryContext = null;
        }
      }
      final problems = kind == 'prescription'
          ? validatePrescription(normalized)
          : validateLabReport(normalized);
      if (problems.isNotEmpty) {
        throw StateError('schema validation failed: ${problems.join('; ')}');
      }
      final envelope = buildResultEnvelope(
        kind: kind,
        normalized: normalized,
        ocrText: ocrText,
        engine: engine,
        latencyMs: DateTime.now().difference(started).inMilliseconds,
        summaryContext: summaryContext,
      );
      final store = await ResultStore.instance();
      final rowId = await store.insertPending(
        kind: kind,
        localPath: image.path,
        resultJson: encodeEnvelope(envelope),
      );
      if (sync != null) {
        try {
          final serverId = await sync.postResult(
            kind: kind,
            envelope: envelope,
            token: token,
          );
          await store.markSynced(rowId, serverId: serverId);
        } catch (e) {
          await store.markFailed(rowId, '$e');
        }
      }
      return envelope;
    });
  }

  /// X-ray pattern pass: CNN classify -> structured context -> store pending.
  Future<Map<String, dynamic>> processXray({
    required File image,
    String? token,
    V2Sync? sync,
  }) {
    return queue.add(() async {
      final classifier = cnn ?? await loadCnn(lazy: true);
      final result = await classifier.classifyFile(image);
      final envelope = {
        'kind': 'xray',
        'engine': 'onnx-resnet50',
        'latency_ms': result.latencyMs,
        'normalized': result.toStructuredContext(),
        'source': 'app',
      };
      final store = await ResultStore.instance();
      final rowId = await store.insertPending(
        kind: 'xray',
        localPath: image.path,
        resultJson: encodeEnvelope(envelope),
      );
      if (sync != null) {
        try {
          final serverId = await sync.postResult(
            kind: 'xray',
            envelope: envelope,
            token: token,
          );
          await store.markSynced(rowId, serverId: serverId);
        } catch (e) {
          await store.markFailed(rowId, '$e');
        }
      }
      return envelope;
    });
  }

  Future<void> dispose() async {
    await cnn?.close();
    slm?.close();
    ocr?.close();
  }
}
