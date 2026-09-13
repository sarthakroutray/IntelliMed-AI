import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'cnn_ocr.dart';
import 'document_type.dart';
import 'inference_queue.dart';
import 'lab/clinical_engine.dart';
import 'lab/extract.dart';
import 'lab/ocr_model.dart';
import 'lab/pdf_text.dart';
import 'lab/render.dart';
import 'lab/rule_engine.dart';
import 'lab/stage1_model.dart';
import 'normalize.dart';
import 'page_source.dart';
import 'schemas.dart';
import 'slm_runtime.dart';
import 'store.dart';
import 'sync.dart';

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

  /// Latched after a failed SLM *load* so each passive capture doesn't
  /// re-attempt a doomed ~372 MB model load. A user-initiated insight clears
  /// it by loading successfully; a generation failure never sets it.
  bool _slmUnavailable = false;

  int cnnLoadMs = -1;
  int slmLoadMs = -1;

  /// Whether the on-device SLM is currently written off after a failed load.
  bool get slmUnavailable => _slmUnavailable;

  /// Allow a later retry of the SLM (e.g. after the user frees memory or the
  /// model becomes available again).
  void resetSlmFailure() => _slmUnavailable = false;

  Future<void> init() async {
    // The ML Kit recognizer is built on first use (see `_recognizePages`):
    // constructing it here put a native platform-channel init on the path
    // before the first frame, for a handle nothing touches until the user
    // captures something.
    if (eagerLoad) {
      ocr = OcrService();
      await loadCnn();
      await loadSlm(SlmBackend.llamaCpp);
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

  /// Load the on-device SLM.
  ///
  /// [SlmBackend.llamaCpp] is the active path (Qwen3-0.6B GGUF);
  /// [SlmBackend.onnx] remains only for the dev A/B harness.
  Future<MedicalSummarizer> loadSlm(SlmBackend backend) async {
    final started = DateTime.now();
    var runtime = slm;
    if (runtime == null) {
      runtime = backend == SlmBackend.llamaCpp
          ? QwenSlmRuntime(modelPath: slmGgufAsset)
          // ignore: deprecated_member_use_from_same_package
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

  /// Run an SLM-powered insight task through the serial queue.
  ///
  /// The SLM is loaded lazily on first use. Only a *load* failure latches
  /// [_slmUnavailable] (so passive captures stop retrying a doomed ~372 MB
  /// load); a user-initiated tap is always allowed to retry, and a successful
  /// load clears the latch. A generation failure (e.g. a timeout) never
  /// disables later insights.
  Future<String> runInsightTask(Future<String> Function(QwenSlmRuntime) task) {
    return queue.add(() async {
      MedicalSummarizer? runtime;
      try {
        runtime = slm ?? await loadSlm(SlmBackend.llamaCpp);
      } catch (e) {
        _slmUnavailable = true;
        rethrow;
      }
      if (runtime is! QwenSlmRuntime) {
        throw StateError('Expected QwenSlmRuntime, got ${runtime.runtimeType}');
      }
      _slmUnavailable = false;
      return task(runtime);
    });
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
      final read = await _readPages(source);
      final ocrPages = read.ocrPages;
      final pages = read.pages;
      try {
        final ocrText = _flatText(ocrPages);
        final signals = analyseText(ocrText);

        // A digital PDF read from its text layer has no page images to classify.
        final canClassify = pages.pages.isNotEmpty;
        XrayPatternResult? classification;
        TypeDetection detection;

        if (canClassify && needsClassifier(signals)) {
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

        if (detection.type == DocumentType.xray && canClassify) {
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
            usedTextLayer: read.usedTextLayer,
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
  /// OCR -> lab rule engine / prescription normalizer (+ SLM summary context)
  /// -> store pending.
  Future<Map<String, dynamic>> processDocument({
    required File source,
    required String kind,
    String? token,
    V2Sync? sync,
  }) {
    return queue.add(() async {
      final started = DateTime.now();
      final read = await _readPages(source);
      final ocrPages = read.ocrPages;
      final pages = read.pages;
      try {
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
            usedTextLayer: read.usedTextLayer,
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
      final read = await _readPages(source);
      final ocrPages = read.ocrPages;
      try {
        final extraction = extractLabDocument(ocrPages);
        return {
          'normalized': extraction.document.toJson(),
          'structure': _structureJson(
            extraction.stage1,
            extraction.document,
            ocrPages,
            recoveredTests: extraction.recoveredTests,
            textLayer: read.usedTextLayer,
          ),
        };
      } finally {
        await read.pages.dispose();
      }
    });
  }

  // -------------------------------------------------------------------
  // Internals (never enqueue)
  // -------------------------------------------------------------------

  /// Read a document into OCR pages.
  ///
  /// A digital PDF is read from its exact text layer (pdfrx/pdfium) first;
  /// rasterize + OCR is only used when there is no usable text layer (scanned
  /// or image-only PDF, or extraction failed).
  Future<({List<OcrPage> ocrPages, PageSet pages, bool usedTextLayer})>
  _readPages(File source) async {
    if (isPdf(source.path)) {
      final layer = await readPdfTextLayer(source.path, maxPages: maxPdfPages);
      if (layer != null) {
        return (
          ocrPages: layer.pages,
          pages: PageSet(
            pages: const [],
            totalPages: layer.totalPages,
            processedCount: layer.pages.length,
          ),
          usedTextLayer: true,
        );
      }
    }
    final pages = await PageSource.pagesFor(source.path);
    try {
      final ocrPages = await _recognizePages(pages.pages);
      return (ocrPages: ocrPages, pages: pages, usedTextLayer: false);
    } catch (_) {
      // Never leak rasterized scratch files when OCR fails mid-way.
      await pages.dispose();
      rethrow;
    }
  }

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

  /// Structured normalization plus on-device SLM summary context.
  ///
  /// Lab reports run the deterministic rule engine over Stage 1 geometry
  /// synthesised from ML Kit boxes (structure.dart -> rule_engine.dart);
  /// prescriptions run the deterministic normalizer. The SLM is fed the
  /// *rendered structure* (renderLabText / renderPrescriptionText), not the raw
  /// OCR stream: it summarises, it does not structure.
  Future<Map<String, dynamic>> _documentEnvelope({
    required String kind,
    required List<OcrPage> ocrPages,
    required DateTime started,
    required TypeDetection detection,
    required PageSet pages,
    bool usedTextLayer = false,
  }) async {
    final ocrText = _flatText(ocrPages);
    final isPrescription = kind == 'prescription';

    final Map<String, dynamic> normalized;
    Map<String, dynamic>? stage3;
    final Map<String, dynamic>? structure;
    List<String>? warnings;
    final String baseEngine;
    var summaryInput = ocrText;

    if (isPrescription) {
      normalized = await normalizePrescriptionInBackground(ocrText);
      stage3 = null;
      structure = null;
      baseEngine = 'deterministic-v1';
      // The SLM summarises the extracted items, plus the rest of the document
      // text so it can cover timing, duration and follow-up too.
      summaryInput = renderPrescriptionText(
        normalized,
        fallback: ocrText,
        context: ocrText,
      );
    } else {
      // Structural extraction plus a flat-text recovery pass, so a mis-guessed
      // table can never extract fewer values than the plain-text parser.
      final extraction = extractLabDocument(ocrPages);
      final document = extraction.document;
      normalized = document.toJson();

      // Run Stage 3 arithmetic & clinical rule engine on-device
      final stage3Result = annotateLabDocument(document);
      final stage3Doc = stage3Result.document;
      stage3 = {
        ...stage3Doc.toJson(),
        'flagged_patterns': stage3Result.patterns.map((p) => {
          'pattern_name': p.patternName,
          'surfaced_text': p.surfacedText,
          'match_type': p.matchType,
          'panel_name': p.panelName,
          'severity': p.severity,
          'category': p.category,
          'clinical_implication': p.clinicalImplication,
          'differential_diagnosis': p.differentialDiagnosis,
          'triggering_tests': p.triggeringTests.map((t) => {
            'test_name': t.testName,
            'raw_test_name': t.rawTestName,
            'value': t.value,
            'unit': t.unit,
            'direction': t.direction,
            'severity': t.severity,
          }).toList(),
        }).toList(),
      };

      structure = _structureJson(
        extraction.stage1,
        document,
        ocrPages,
        recoveredTests: extraction.recoveredTests,
        textLayer: usedTextLayer,
      );
      // Surface extraction degradation and arithmetic warnings on device
      warnings = [
        ...extraction.stage1.warnings,
        ...stage3Result.warnings,
      ];
      baseEngine = 'rule-engine-v2';
      summaryInput = renderLabText(stage3Doc, fallback: ocrText);
    }

    // The model's context is 2048 tokens; an unbounded prompt (the raw-OCR
    // fallback on a dense page) would overflow it and fail the generation.
    summaryInput = _capSummaryInput(summaryInput);

    var engine = baseEngine;
    Map<String, dynamic>? summaryContext;
    // Non-fatal SLM problems, surfaced with the extraction warnings so a
    // missing summary is never silent.
    final summaryWarnings = <String>[];

    // Every document kind — lab report and prescription alike — gets summary
    // context from the on-device SLM (Qwen3-0.6B GGUF), fed the *extracted*
    // structure rather than the raw OCR stream. It is loaded on first use when
    // the app started lazily (the default).
    //
    // It stays a summariser: lab structure comes from the rule engine,
    // prescription items from the deterministic normalizer, and every
    // flag/panic verdict from clinical_engine — never from here.
    if (!_slmUnavailable) {
      MedicalSummarizer? runtime;
      try {
        runtime = slm ?? await loadSlm(SlmBackend.llamaCpp);
      } catch (e) {
        // A load failure is not recoverable within this capture. Latch it so
        // later captures skip the doomed ~372 MB load; a user-initiated insight
        // tap clears the latch by loading successfully.
        _slmUnavailable = true;
        debugPrint('ModelManager: SLM load failed — $e');
      }
      if (runtime != null) {
        try {
          final summary = isPrescription
              ? await runtime.summarizePrescription(summaryInput)
              : await runtime.summarize(summaryInput);
          if (_hasSummaryText(summary)) {
            summaryContext = summary;
            engine = '$baseEngine+qwen-summary';
          } else {
            // The runtime ran but produced nothing usable. Do not claim a
            // summary engine, and surface it rather than hiding a blank card.
            debugPrint('ModelManager: SLM returned an empty summary');
            summaryWarnings.add(
              'The on-device summary came back empty on this device.',
            );
          }
        } catch (e) {
          // A generation failure (load, slot allocation, timeout) degrades this
          // capture only; the runtime stays resident for the next one.
          debugPrint('ModelManager: SLM generation failed — $e');
          summaryWarnings.add('On-device summary unavailable: $e');
        }
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
      stage3: stage3,
      ocrText: ocrText,
      engine: engine,
      latencyMs: DateTime.now().difference(started).inMilliseconds,
      summaryContext: summaryContext,
      detection: _detectionJson(detection),
      structure: structure,
      warnings: [...?warnings, ...summaryWarnings],
      pageCount: pages.totalPages,
      pagesTruncated: pages.truncated,
    );
  }

  /// Upper bound on the text handed to the SLM, in characters. The model's
  /// context is 2048 tokens and the reply is capped at [maxNewTokens]; a dense
  /// raw-OCR fallback can otherwise overrun the context and fail.
  static const int _maxSummaryChars = 4000;

  static String _capSummaryInput(String text) =>
      text.length <= _maxSummaryChars
          ? text
          : text.substring(0, _maxSummaryChars);

  /// Whether a summariser result carries any usable text.
  static bool _hasSummaryText(Map<String, dynamic> summary) {
    final text = summary['medical_summary'];
    if (text is String && text.trim().isNotEmpty) return true;
    final findings = summary['key_findings'];
    return findings is List && findings.isNotEmpty;
  }

  /// Provenance for the lab extraction: how the structure was reconstructed,
  /// how much of it there was, and how far to trust it.
  Map<String, dynamic> _structureJson(
    LabStage1 stage1,
    LabDocument document,
    List<OcrPage> ocrPages, {
    int recoveredTests = 0,
    bool textLayer = false,
  }) {
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
      // Whether values came from a digital PDF's exact text layer or from OCR.
      'source': textLayer ? 'pdf-text' : 'ocr',
      'tables': stage1.tables.length,
      'tests': confidences.length,
      // How many rows only the flat-text recovery pass found. A reviewer can
      // see how much the geometry heuristic missed.
      'recovered': recoveredTests,
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
