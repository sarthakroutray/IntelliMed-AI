import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'cnn_ocr.dart';
import 'document_type.dart';
import 'inference_queue.dart';
import 'lab/ocr_model.dart';
import 'lab/render.dart';
import 'lab/rule_engine.dart';
import 'lab/stage1_model.dart';
import 'lab/structure.dart';
import 'normalize.dart';
import 'page_source.dart';
import 'schemas.dart';
import 'slm_runtime.dart';
import 'store.dart';
import 'sync.dart';

/// On-device bounding boxes are page-relative (0..1), so the ported rule
/// engine's text-inside-table tolerance must be expressed the same way. The
/// backend's 5.0 is in PDF points; applied to normalised units it would treat
/// an entire page as "inside" a table and skip row recovery.
const _pageRelativeBboxTolerance = 0.01;

/// Owns both model slots and the serial inference queue.
///
/// Default policy: both models stay loaded and resident. Swap-in/swap-out
/// logic is deliberately NOT built — see docs/MEMORY_REPORT.md: it only gets
/// added if real-device measurement shows memory pressure.
///
/// NOTE: [InferenceQueue] is strictly serial, so the public entry points are
/// the only things that enqueue. Internal helpers (`_processDocument`,
/// `_processXray`) must never call `queue.add` — a nested enqueue would wait on
/// itself and deadlock.
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
  MedicalSummarizer? slm;
  OcrService? ocr;
  DateTime? cnnLoadedAt;
  DateTime? slmLoadedAt;

  /// Latched after a failed T5 load so each capture doesn't re-attempt a
  /// ~94 MB model load that already failed. Cleared by [resetSlmFailure].
  bool _slmUnavailable = false;

  int cnnLoadMs = -1;
  int slmLoadMs = -1;

  /// Whether the T5 summariser is currently written off after a failure.
  bool get slmUnavailable => _slmUnavailable;

  /// Allow a later retry of the T5 summariser (e.g. after the user frees
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

  Future<MedicalSummarizer> loadSlm(SlmBackend backend) async {
    final started = DateTime.now();
    var runtime = slm;
    if (runtime == null) {
      runtime = backend == SlmBackend.llamaCpp
          ? LlamaCppRuntime(modelPath: slmGgufAsset)
          : OnnxSummarizer();
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

  // -------------------------------------------------------------------
  // Public entry points (each enqueues exactly once)
  // -------------------------------------------------------------------

  /// Auto-detect the document type, then run the matching pass.
  ///
  /// This is the default capture path. Detection uses OCR text first — a lab
  /// report or prescription is text-dense and unmistakable — and only falls
  /// back to the X-ray classifier for sparse, evidence-free images. That
  /// ordering is what stops a prescription being labelled pneumonia by the
  /// pneumonia classifier.
  ///
  /// [source] may be a PDF or an image (see page_source.dart); pages are
  /// rasterized and their text combined, so a multipage report is normalized
  /// as one document rather than one capture per page.
  Future<Map<String, dynamic>> processAuto({
    required File source,
    String? token,
    V2Sync? sync,
  }) {
    return queue.add(() async {
      final started = DateTime.now();
      final pages = await PageSource.pagesFor(source.path);
      try {
        final ocrPages = await _recognizePages(pages.pages);
        final ocrText = _flatText(ocrPages);
        final signals = analyseText(ocrText);

        XrayPatternResult? classification;
        TypeDetection detection;

        if (needsClassifier(signals)) {
          // Sparse text with no document markers: only now is the X-ray head
          // meaningful. A load/run failure must not fail the capture.
          try {
            classification = await _classify(pages.pages.first);
          } catch (e) {
            debugPrint('ModelManager: classifier unavailable — $e');
          }
          detection = decideType(
            signals: signals,
            xrayConfidence: classification?.confidence,
          );
        } else {
          detection = decideType(signals: signals);
        }

        if (detection.type == DocumentType.xray) {
          final result = classification ?? await _classify(pages.pages.first);
          return _storeAndSync(
            kind: 'xray',
            sourcePath: source.path,
            envelope: _xrayEnvelope(result, detection, pages),
            sync: sync,
            token: token,
          );
        }

        return _storeAndSync(
          kind: detection.type.wireName,
          sourcePath: source.path,
          envelope: await _documentEnvelope(
            kind: detection.type.wireName,
            ocrPages: ocrPages,
            started: started,
            detection: detection,
            pages: pages,
          ),
          sync: sync,
          token: token,
        );
      } finally {
        await pages.dispose();
      }
    });
  }

  /// Full on-device pass for a captured document, with the type chosen
  /// explicitly by the user:
  /// OCR -> lab rule engine / prescription normalizer (+ T5 summary context
  /// for non-prescription docs when the summariser is loaded) -> store pending.
  Future<Map<String, dynamic>> processDocument({
    required File source,
    required String kind,
    String? token,
    V2Sync? sync,
  }) {
    return queue.add(() async {
      final started = DateTime.now();
      final pages = await PageSource.pagesFor(source.path);
      try {
        final ocrPages = await _recognizePages(pages.pages);
        final detection = TypeDetection(
          type: DocumentTypeWire.fromWire(kind) ?? DocumentType.labReport,
          confidence: 1,
          reasons: const ['selected manually'],
          autoDetected: false,
        );
        return _storeAndSync(
          kind: kind,
          sourcePath: source.path,
          envelope: await _documentEnvelope(
            kind: kind,
            ocrPages: ocrPages,
            started: started,
            detection: detection,
            pages: pages,
          ),
          sync: sync,
          token: token,
        );
      } finally {
        await pages.dispose();
      }
    });
  }

  /// X-ray pattern pass chosen explicitly by the user. A radiograph is one
  /// image, so only the first page of a multipage source is classified.
  Future<Map<String, dynamic>> processXray({
    required File source,
    String? token,
    V2Sync? sync,
  }) {
    return queue.add(() async {
      final pages = await PageSource.pagesFor(source.path);
      try {
        final result = await _classify(pages.pages.first);
        final detection = TypeDetection(
          type: DocumentType.xray,
          confidence: result.confidence,
          reasons: const ['selected manually'],
          autoDetected: false,
        );
        return _storeAndSync(
          kind: 'xray',
          sourcePath: source.path,
          envelope: _xrayEnvelope(result, detection, pages),
          sync: sync,
          token: token,
        );
      } finally {
        await pages.dispose();
      }
    });
  }

  /// Run only the on-device lab engine (OCR geometry -> Stage 1 -> rule
  /// engine) and return the structured document plus provenance.
  ///
  /// Does not store, sync, or run the summariser. Used by the developer diff
  /// screen to compare the on-device engine against the server pipeline.
  Future<Map<String, dynamic>> localLabPreview({required File source}) {
    return queue.add(() async {
      final pages = await PageSource.pagesFor(source.path);
      try {
        final ocrPages = await _recognizePages(pages.pages);
        final stage1 = buildStage1(ocrPages);
        final document = buildLabDocument(
          stage1,
          bboxTolerance: _pageRelativeBboxTolerance,
        );
        return {
          'normalized': document.toJson(),
          'structure': _structureJson(stage1, document, ocrPages),
        };
      } finally {
        await pages.dispose();
      }
    });
  }

  // -------------------------------------------------------------------
  // Internals (never enqueue)
  // -------------------------------------------------------------------

  /// OCR every page in order, preserving word geometry.
  ///
  /// Sequential on purpose: ML Kit's recognizer is not safe to drive
  /// concurrently, and the surrounding queue is serial anyway.
  Future<List<OcrPage>> _recognizePages(List<File> pages) async {
    final service = ocr ??= OcrService();
    return service.recognizePages(pages);
  }

  /// Flat reading-order text, for type detection and the non-lab paths.
  String _flatText(List<OcrPage> pages) =>
      pages.expand((p) => p.lines.map((l) => l.text)).join('\n');

  Future<XrayPatternResult> _classify(File image) async {
    final classifier = cnn ?? await loadCnn(lazy: true);
    return classifier.classifyFile(image);
  }

  /// Structured normalization plus, for non-prescription kinds, the T5
  /// summary context.
  ///
  /// Lab reports run the deterministic rule engine over Stage 1 geometry
  /// synthesised from ML Kit boxes (structure.dart -> rule_engine.dart). The
  /// T5 model is fed the *rendered structure* (renderLabText), not the raw OCR
  /// stream: it summarises, it does not structure.
  Future<Map<String, dynamic>> _documentEnvelope({
    required String kind,
    required List<OcrPage> ocrPages,
    required DateTime started,
    required TypeDetection detection,
    required PageSet pages,
  }) async {
    final ocrText = _flatText(ocrPages);
    final isPrescription = kind == 'prescription';

    final Map<String, dynamic> normalized;
    final Map<String, dynamic>? structure;
    final String baseEngine;
    var summaryInput = ocrText;

    if (isPrescription) {
      normalized = await normalizePrescriptionInBackground(ocrText);
      structure = null;
      baseEngine = 'deterministic-v1';
    } else {
      final stage1 = buildStage1(ocrPages);
      final document = buildLabDocument(
        stage1,
        bboxTolerance: _pageRelativeBboxTolerance,
      );
      normalized = document.toJson();
      structure = _structureJson(stage1, document, ocrPages);
      baseEngine = 'rule-engine-v2';
      summaryInput = renderLabText(document, fallback: ocrText);
    }

    var engine = baseEngine;
    Map<String, dynamic>? summaryContext;

    // Prescriptions deliberately stay on the deterministic path, mirroring the
    // backend short-circuit (structured NLP data, never generative output).
    // Every other document kind uses the T5 summariser, which is loaded on
    // first use when the app started lazily (the default): previously nothing
    // ever called loadSlm() outside the opt-in eager path, so `slm` stayed null
    // and the 94 MB of T5 weights shipped but were never exercised.
    //
    // Long text is safe here: the tokenizer truncates to `maxInputTokens`
    // (128) internally, and renderLabText already bounds the input.
    if (!isPrescription && !_slmUnavailable) {
      try {
        final runtime = slm ?? await loadSlm(SlmBackend.onnx);
        summaryContext = await runtime.summarize(summaryInput);
        engine = '$baseEngine+t5-summary';
      } catch (e) {
        // Degrade to the deterministic engine rather than failing the capture.
        // Latch the failure so we don't retry a doomed ~94 MB load every time.
        _slmUnavailable = true;
        summaryContext = null;
        debugPrint('ModelManager: T5 summariser unavailable — $e');
      }
    }

    final problems = isPrescription
        ? validatePrescription(normalized)
        : validateLabReport(normalized);
    if (problems.isNotEmpty) {
      throw StateError('schema validation failed: ${problems.join('; ')}');
    }

    return buildResultEnvelope(
      kind: kind,
      normalized: normalized,
      ocrText: ocrText,
      engine: engine,
      latencyMs: DateTime.now().difference(started).inMilliseconds,
      summaryContext: summaryContext,
      detection: _detectionJson(detection),
      structure: structure,
      pageCount: pages.totalPages,
      pagesTruncated: pages.truncated,
    );
  }

  /// Provenance for the lab extraction: how the structure was reconstructed,
  /// how much of it there was, and how far to trust it.
  Map<String, dynamic> _structureJson(
    LabStage1 stage1,
    LabDocument document,
    List<OcrPage> ocrPages,
  ) {
    final confidences = [
      for (final panel in document.panels)
        for (final test in panel.tests) test.ocrConfidence,
    ];
    final String confidence;
    if (confidences.isEmpty || confidences.contains('low')) {
      confidence = 'low';
    } else if (confidences.contains('medium')) {
      confidence = 'medium';
    } else {
      confidence = 'high';
    }
    return {
      'engine': stage1.extractionEngine,
      'tables': stage1.tables.length,
      'tests': confidences.length,
      'confidence': confidence,
      'pages_without_tables': [
        for (final page in ocrPages)
          if (!stage1.tables.any((t) => t.page == page.pageNumber))
            page.pageNumber,
      ],
    };
  }

  Map<String, dynamic> _xrayEnvelope(
    XrayPatternResult result,
    TypeDetection detection,
    PageSet pages,
  ) => {
    'kind': 'xray',
    'engine': 'onnx-resnet50',
    'latency_ms': result.latencyMs,
    'normalized': result.toStructuredContext(),
    'source': 'app',
    'detection': _detectionJson(detection),
    'page_count': pages.totalPages,
    if (pages.truncated) 'pages_truncated': true,
  };

  Map<String, dynamic> _detectionJson(TypeDetection detection) => {
    'type': detection.type.wireName,
    'confidence': double.parse(detection.confidence.toStringAsFixed(3)),
    'auto': detection.autoDetected,
    'used_classifier': detection.usedClassifier,
    'reasons': detection.reasons,
  };

  /// Insert the row, then attempt a sync holding the offline contract: a
  /// transport failure or a lapsed session keeps the row `pending` so nothing
  /// is lost, while a genuine rejection is `failed`.
  Future<Map<String, dynamic>> _storeAndSync({
    required String kind,
    required String sourcePath,
    required Map<String, dynamic> envelope,
    V2Sync? sync,
    String? token,
  }) async {
    final store = await ResultStore.instance();
    final rowId = await store.insertPending(
      kind: kind,
      localPath: sourcePath,
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
        // Route isn't deployed at this base URL — keep the row pending so it
        // syncs once the backend is reachable.
        debugPrint('ModelManager: $e — row $rowId stays pending');
      } on OfflineException catch (e) {
        // Offline capture: keep the structured result queued locally and sync
        // when connectivity returns (V2Sync.watchConnectivity).
        await store.markPending(rowId);
        debugPrint('ModelManager: $e — row $rowId stays pending');
      } on UnauthorizedException catch (e) {
        // Session lapsed: the on-device result is valid, so keep it queued for
        // after the next sign-in rather than marking it failed.
        await store.markPending(rowId);
        debugPrint('ModelManager: $e — row $rowId stays pending');
      } catch (e) {
        await store.markFailed(rowId, '$e');
      }
    }
    return envelope;
  }

  Future<void> dispose() async {
    await cnn?.close();
    await slm?.close();
    ocr?.close();
  }
}
