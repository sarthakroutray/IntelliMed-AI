import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// Class labels + preprocessing mirror backend/services.py exactly:
/// ResNet50 head over [Normal, Bacterial Pneumonia, Viral Pneumonia],
/// 224x224 RGB, ImageNet mean/std normalization.
const xrayLabels = ['Normal', 'Bacterial Pneumonia', 'Viral Pneumonia'];
const xrayInputSize = 224;
const xrayMean = [0.485, 0.456, 0.406];
const xrayStd = [0.229, 0.224, 0.225];

/// Runtime backing the X-ray pattern pass.
///
/// `onnx` (default) runs the converted fine-tuned ResNet50
/// (`assets/models/pneumonia_resnet50.onnx`, built from
/// `backend/models/best_model_optimized.pkl` via
/// `backend/scripts/export_pneumonia_onnx.py`) through flutter_onnxruntime.
/// `tflite` is the future quantized path — selected with
/// `--dart-define=CNN_BACKEND=tflite` once `xray_cnn.tflite` lands.
enum CnnBackend { onnx, tflite }

enum CnnReadiness { ready, modelMissing }

class XrayPatternResult {
  XrayPatternResult({
    required this.topPattern,
    required this.confidence,
    required this.probabilities,
    required this.latencyMs,
    required this.modelAsset,
    this.note,
  });

  final String topPattern;
  final double confidence;
  final Map<String, double> probabilities;
  final int latencyMs;
  final String modelAsset;

  /// Extra context when the classifier could not run (e.g. load failure).
  final String? note;

  Map<String, dynamic> toStructuredContext() => {
    'document_type': 'xray',
    'top_pattern': topPattern,
    'confidence': confidence,
    'probabilities': probabilities,
    'model': modelAsset,
    'latency_ms': latencyMs,
    'note': note ?? 'Structured context for doctor review.',
  };
}

class CnnClassifier {
  CnnClassifier._onnx(this._session, this._modelAsset)
    : _mode = CnnReadiness.ready,
      _lazyOnnxAsset = null,
      _loadError = null;

  CnnClassifier._missing(this._modelAsset, [this._loadError])
    : _mode = CnnReadiness.modelMissing,
      _session = null,
      _lazyOnnxAsset = null;

  CnnClassifier._deferredOnnx(String asset)
    : _modelAsset = asset,
      _mode = CnnReadiness.modelMissing,
      _session = null,
      _lazyOnnxAsset = asset,
      _loadError = null;

  OrtSession? _session;
  final String _modelAsset;
  final CnnReadiness _mode;
  final String? _lazyOnnxAsset;
  String? _loadError;

  /// Why the model is not ready, when a load attempt failed. Distinguishes a
  /// genuinely absent model from a real ORT failure so on-device faults are
  /// diagnosable instead of silently reported as "unavailable".
  String? get loadError => _loadError;

  /// Startup mode: 'eager' loads now, 'lazy' defers to first classify() call.
  /// The benchmark screen times both; see docs/APP_SPIKE.md.
  static Future<CnnClassifier> load({
    required String modelAsset,
    bool lazy = false,
    CnnBackend backend = CnnBackend.onnx,
  }) async {
    if (backend == CnnBackend.tflite) {
      // Quantized .tflite not converted yet (needs TF toolchain); report the
      // gap instead of failing silently.
      return CnnClassifier._missing(modelAsset, 'tflite backend not built');
    }
    if (lazy) return CnnClassifier._deferredOnnx(modelAsset);
    return _loadOnnxEager(modelAsset);
  }

  static Future<CnnClassifier> _loadOnnxEager(String modelAsset) async {
    try {
      final session = await OnnxRuntime().createSessionFromAsset(modelAsset);
      return CnnClassifier._onnx(session, modelAsset);
    } catch (e) {
      debugPrint('CnnClassifier: failed to load $modelAsset — $e');
      return CnnClassifier._missing(modelAsset, '$e');
    }
  }

  bool get isReady => _mode == CnnReadiness.ready || _session != null;

  Future<void> _ensureLoaded() async {
    if (_session != null || _mode == CnnReadiness.ready) return;
    final asset = _lazyOnnxAsset ?? _modelAsset;
    try {
      _session = await OnnxRuntime().createSessionFromAsset(asset);
      _loadError = null;
    } catch (e) {
      // Stay in modelMissing mode; classify() reports the gap.
      _loadError = '$e';
      debugPrint('CnnClassifier: lazy load of $asset failed — $e');
    }
  }

  /// Preprocess X-ray bytes to the model's expected [1,3,224,224] float input,
  /// flattened to a Float32List for the ORT NCHW tensor.
  ///
  /// Mirrors the backend `_preprocess_xray` transform exactly: PIL
  /// `.convert('RGB')` followed by `transforms.Resize((224, 224))` — a direct
  /// 224x224 squash (aspect ratio intentionally not preserved) with
  /// antialiased bilinear resampling.
  ///
  /// `Interpolation.average` is an area filter, which is the correct choice
  /// when downscaling a large radiograph to 224 and the closest match to
  /// torchvision's antialiased resize. The previous default
  /// (`Interpolation.nearest`) aliased badly and was a train/inference
  /// mismatch.
  static Float32List preprocessXray(img.Image src) {
    final rgb = src.numChannels == 3 ? src : src.convert(numChannels: 3);
    final resized = img.copyResize(
      rgb,
      width: xrayInputSize,
      height: xrayInputSize,
      interpolation: img.Interpolation.average,
    );
    const plane = xrayInputSize * xrayInputSize;
    final out = Float32List(3 * plane);
    for (var y = 0; y < xrayInputSize; y++) {
      for (var x = 0; x < xrayInputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final idx = y * xrayInputSize + x;
        out[idx] = (pixel.r / 255.0 - xrayMean[0]) / xrayStd[0];
        out[plane + idx] = (pixel.g / 255.0 - xrayMean[1]) / xrayStd[1];
        out[2 * plane + idx] = (pixel.b / 255.0 - xrayMean[2]) / xrayStd[2];
      }
    }
    return out;
  }

  Future<XrayPatternResult> classifyFile(File file) async {
    final started = DateTime.now();
    await _ensureLoaded();
    final session = _session;
    if (session == null) {
      return XrayPatternResult(
        topPattern: 'unavailable',
        confidence: 0,
        probabilities: {for (final l in xrayLabels) l: 0},
        latencyMs: DateTime.now().difference(started).inMilliseconds,
        modelAsset: _modelAsset,
        note: 'On-device classifier unavailable'
            '${_loadError == null ? '' : ' ($_loadError)'}',
      );
    }
    final bytes = await file.readAsBytes();
    final decoded = await compute(_decodeImage, bytes);
    if (decoded == null) {
      throw StateError('Could not decode image ${file.path}');
    }
    final inputData = preprocessXray(decoded);
    final input = await OrtValue.fromList(inputData, [
      1,
      3,
      xrayInputSize,
      xrayInputSize,
    ]);
    try {
      final outputs = await session.run({'input': input});
      final logitsValue = outputs['logits'] ?? outputs.values.first;
      final flat = await logitsValue.asFlattenedList();
      final logits = flat.map((e) => (e as num).toDouble()).toList();
      final scores = softmax(logits);
      var best = 0;
      for (var i = 1; i < scores.length; i++) {
        if (scores[i] > scores[best]) best = i;
      }
      final probs = {
        for (var i = 0; i < xrayLabels.length; i++) xrayLabels[i]: scores[i],
      };
      return XrayPatternResult(
        topPattern: xrayLabels[best],
        confidence: scores[best],
        probabilities: probs,
        latencyMs: DateTime.now().difference(started).inMilliseconds,
        modelAsset: _modelAsset,
      );
    } finally {
      await input.dispose();
    }
  }

  /// Numerically stable softmax over raw logits.
  ///
  /// Exposed for regression testing: an earlier hand-rolled Taylor-series
  /// `exp` returned negative values for the negative arguments this shift
  /// always produces, which flipped the argmax and mislabelled confident
  /// predictions.
  @visibleForTesting
  static List<double> softmax(List<double> logits) {
    if (logits.isEmpty) return const [];
    var maxLogit = logits.first;
    for (final l in logits) {
      if (l > maxLogit) maxLogit = l;
    }
    final exps = logits.map((l) => math.exp(l - maxLogit)).toList();
    var sum = 0.0;
    for (final e in exps) {
      sum += e;
    }
    if (sum <= 0) return List<double>.filled(logits.length, 0);
    return exps.map((e) => e / sum).toList();
  }

  Future<void> close() async {
    await _session?.close();
  }
}

img.Image? _decodeImage(List<int> bytes) {
  try {
    return img.decodeImage(Uint8List.fromList(bytes));
  } catch (_) {
    return null;
  }
}

/// On-device OCR via ML Kit (default for this app — see docs/APP_SPIKE.md).
/// Handwriting OCR is out of scope and never attempted here; printed
/// prescriptions and lab reports only.
class OcrService {
  OcrService()
    : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;

  Future<String> recognizeFile(File file) async {
    final input = InputImage.fromFile(file);
    final result = await _recognizer.processImage(input);
    return result.text;
  }

  Future<String> recognizePicked(XFile picked) =>
      recognizeFile(File(picked.path));

  void close() => _recognizer.close();
}
