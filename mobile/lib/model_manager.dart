import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

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

  /// Latched after a failed T5 load so each capture doesn't re-attempt a
  /// ~94 MB model load that already failed. Cleared by [resetSlmFailure].
  bool _slmUnavailable = false;

  int cnnLoadMs = -1;
  int slmLoadMs = -1;

  /// Whether the T5 standardizer is currently written off after a failure.
  bool get slmUnavailable => _slmUnavailable;

  /// Allow a later retry of the T5 standardizer (e.g. after the user frees
  /// memory or connectivity/model changes).
  void resetSlmFailure() => _slmUnavailable = false;

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
    var runtime = slm;
    if (runtime == null) {
      runtime = backend == SlmBackend.llamaCpp
          ? LlamaCppRuntime(modelPath: slmGgufAsset)
          : OnnxSlmRuntime();
      slm = runtime;
    }
    try {
      await runtime.load();
    } catch (e) {
      // Never keep a half-initialised runtime resident: a failed load would
      // otherwise be reused forever behind a non-null `slm`.
      if (identical(slm, runtime)) slm = null;
      rethrow;
    }
    slmLoadedAt ??= DateTime.now();
    slmLoadMs = DateTime.now().difference(started).inMilliseconds;
    return runtime;
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
      // Prescriptions deliberately stay on the deterministic path, mirroring
      // the backend short-circuit (structured NLP data, never generative
      // output). Every other document kind uses the T5 standardizer.
      //
      // The standardizer is loaded on first use when the app started lazily
      // (the default): previously nothing ever called loadSlm() outside the
      // opt-in eager path, so `slm` stayed null and this block never ran —
      // the 94 MB of T5 weights shipped but were never exercised.
      if (kind != 'prescription' && !_slmUnavailable) {
        try {
          final runtime = slm ?? await loadSlm(SlmBackend.onnx);
          if (runtime is OnnxSlmRuntime) {
            summaryContext = await runtime.standardizeText(ocrText);
            engine = 'deterministic-v1+t5-q8';
          }
        } catch (e) {
          // Degrade to the deterministic engine rather than failing the
          // capture. Latch the failure so we don't retry a doomed ~94 MB
          // load on every subsequent document.
          _slmUnavailable = true;
          summaryContext = null;
          debugPrint('ModelManager: T5 standardizer unavailable — $e');
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
        } on RouteMissingException catch (e) {
          // Route isn't deployed at this base URL — keep the row pending so
          // it syncs once the backend is reachable.
          debugPrint('ModelManager: $e — row $rowId stays pending');
        } on OfflineException catch (e) {
          // Offline capture: keep the structured result queued locally and
          // sync when connectivity returns (V2Sync.watchConnectivity).
          await store.markPending(rowId);
          debugPrint('ModelManager: $e — row $rowId stays pending');
        } on UnauthorizedException catch (e) {
          // Session lapsed: the on-device result is valid, so keep it queued
          // for after the next sign-in rather than marking it failed.
          await store.markPending(rowId);
          debugPrint('ModelManager: $e — row $rowId stays pending');
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
        } on RouteMissingException catch (e) {
          // Route isn't deployed at this base URL — keep the row pending so
          // it syncs once the backend is reachable.
          debugPrint('ModelManager: $e — row $rowId stays pending');
        } on OfflineException catch (e) {
          // Offline capture: keep the structured result queued locally and
          // sync when connectivity returns (V2Sync.watchConnectivity).
          await store.markPending(rowId);
          debugPrint('ModelManager: $e — row $rowId stays pending');
        } on UnauthorizedException catch (e) {
          // Session lapsed: the on-device result is valid, so keep it queued
          // for after the next sign-in rather than marking it failed.
          await store.markPending(rowId);
          debugPrint('ModelManager: $e — row $rowId stays pending');
        } catch (e) {
          await store.markFailed(rowId, '$e');
        }
      }
      return envelope;
    });
  }

  Future<void> dispose() async {
    await cnn?.close();
    await slm?.close();
    ocr?.close();
  }
}
