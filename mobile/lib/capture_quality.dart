// Pre-inference capture quality gate.
//
// Input quality is the dominant cause of poor extraction, and no model fixes a
// blurred, glare-hit or dark photo. This runs on the corrected scanner image
// (or a picked gallery image) before OCR and asks for a retake with a specific
// reason, which is cheaper and kinder than producing a bad result.
//
// Fully deterministic and on-device: no model, just pixel statistics over the
// `image` package. Analysis is done on a downscaled grayscale copy so a
// 12-megapixel photo costs a bounded amount of work.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Luma at or above this counts as clipped white (glare).
const _clippedLuma = 250;

/// A word/line shorter than this (in pixels) is hard for ML Kit to read.
const captureMinTextHeightPx = 14.0;

/// Tunable thresholds. Defaults were chosen against representative phone
/// photos; they are grouped here so they can be adjusted in one place.
class CaptureQualityThresholds {
  const CaptureQualityThresholds({
    this.blurVariance = 90,
    this.glareFraction = 0.06,
    this.darkMeanLuminance = 45,
    this.analysisMaxEdge = 800,
  });

  /// Variance of the Laplacian below this reads as blurry.
  final double blurVariance;

  /// Fraction of clipped-white pixels above this reads as glare.
  final double glareFraction;

  /// Mean luma below this reads as too dark.
  final double darkMeanLuminance;

  /// Long edge used for analysis; the image is downscaled to this first.
  final int analysisMaxEdge;
}

enum CaptureIssueKind { unreadable, blur, glare, tooDark, smallText }

class CaptureIssue {
  const CaptureIssue({
    required this.kind,
    required this.message,
    required this.value,
  });

  final CaptureIssueKind kind;

  /// User-facing, specific, and non-judgemental.
  final String message;
  final double value;
}

class CaptureAssessment {
  const CaptureAssessment({required this.issues, this.metrics = const {}});

  final List<CaptureIssue> issues;

  /// Raw measurements, for the developer bench and for tuning thresholds.
  final Map<String, double> metrics;

  bool get ok => issues.isEmpty;
}

/// Assess raw image bytes. Top-level and isolate-friendly for `compute`.
CaptureAssessment assessCaptureBytes(
  Uint8List bytes, [
  CaptureQualityThresholds thresholds = const CaptureQualityThresholds(),
]) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) {
    return const CaptureAssessment(
      issues: [
        CaptureIssue(
          kind: CaptureIssueKind.unreadable,
          message: 'This image could not be read — try taking the photo again.',
          value: -1,
        ),
      ],
    );
  }
  return assessCapture(decoded, thresholds: thresholds);
}

/// Pixel-level gate: blur (variance of Laplacian), glare (clipped-white area)
/// and overall darkness. Text size is checked separately via [smallTextIssue],
/// because it needs OCR geometry.
CaptureAssessment assessCapture(
  img.Image source, {
  CaptureQualityThresholds thresholds = const CaptureQualityThresholds(),
}) {
  final gray = _downscaleGrayscale(source, thresholds.analysisMaxEdge);
  if (gray.width < 3 || gray.height < 3) {
    return const CaptureAssessment(
      issues: [
        CaptureIssue(
          kind: CaptureIssueKind.unreadable,
          message: 'This image is too small to read — take a new photo.',
          value: 0,
        ),
      ],
    );
  }

  final values = gray.values;
  var sum = 0.0;
  var clipped = 0;
  for (final v in values) {
    sum += v;
    if (v >= _clippedLuma) clipped++;
  }
  final mean = sum / values.length;
  final glare = clipped / values.length;
  final blur = _laplacianVariance(gray);

  final issues = <CaptureIssue>[];
  if (blur < thresholds.blurVariance) {
    issues.add(
      CaptureIssue(
        kind: CaptureIssueKind.blur,
        message:
            'The photo looks out of focus — hold still and keep the page flat.',
        value: blur,
      ),
    );
  }
  if (glare > thresholds.glareFraction) {
    issues.add(
      CaptureIssue(
        kind: CaptureIssueKind.glare,
        message: 'There is glare on the page — move away from the light source.',
        value: glare,
      ),
    );
  }
  if (mean < thresholds.darkMeanLuminance) {
    issues.add(
      CaptureIssue(
        kind: CaptureIssueKind.tooDark,
        message: 'The photo is too dark — add light and try again.',
        value: mean,
      ),
    );
  }

  return CaptureAssessment(
    issues: issues,
    metrics: {'blurVariance': blur, 'glareFraction': glare, 'meanLuminance': mean},
  );
}

/// Post-OCR check: ML Kit line boxes expose the printed text height, which
/// pixel statistics cannot. Returns null when the text is a readable size.
CaptureIssue? smallTextIssue({required double medianLineHeightPx}) {
  if (medianLineHeightPx <= 0 || medianLineHeightPx >= captureMinTextHeightPx) {
    return null;
  }
  return CaptureIssue(
    kind: CaptureIssueKind.smallText,
    message:
        'The text is small in this photo — move closer or scan the page flat.',
    value: medianLineHeightPx,
  );
}

class _Gray {
  _Gray(this.width, this.height, this.values);
  final int width;
  final int height;
  final List<double> values;
}

/// Downscale the long edge to [maxEdge] and convert to luma, so the Laplacian
/// pass is bounded regardless of the camera's resolution.
_Gray _downscaleGrayscale(img.Image source, int maxEdge) {
  img.Image working = source;
  final longEdge = math.max(source.width, source.height);
  if (longEdge > maxEdge) {
    final scale = maxEdge / longEdge;
    working = img.copyResize(
      source,
      width: (source.width * scale).round(),
      height: (source.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  final w = working.width;
  final h = working.height;
  final values = List<double>.filled(w * h, 0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = working.getPixel(x, y);
      values[y * w + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    }
  }
  return _Gray(w, h, values);
}

/// Variance of the 4-neighbour Laplacian over the interior. Sharp edges give a
/// high variance; a blurred image collapses toward zero.
double _laplacianVariance(_Gray gray) {
  final w = gray.width;
  final h = gray.height;
  final v = gray.values;

  var sum = 0.0;
  var sumSq = 0.0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    final row = y * w;
    for (var x = 1; x < w - 1; x++) {
      final i = row + x;
      final lap = v[i - w] + v[i + w] + v[i - 1] + v[i + 1] - 4 * v[i];
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return sumSq / n - mean * mean;
}
