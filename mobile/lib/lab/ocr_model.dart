// OCR geometry model — the part of ML Kit's result tree that the flat-text
// path throws away. Mirroring the plugin types keeps the door open to word
// boxes and per-word confidence, which the structure synthesis (structure.dart)
// needs to reconstruct table rows and columns.
//
// Boxes are in the coordinate space of the *processed image* (bitmap pixels).
// [OcrPage.pixelWidth]/[OcrPage.pixelHeight] let later geometry normalise to
// page-relative units (`x / pixelWidth`), so the algorithm is scale-invariant
// across photos, 200-DPI PDF renders and different devices.

import 'dart:ui' show Rect;

/// Rotation (degrees) above which a page is treated as skewed.
const ocrRotatedAngleDeg = 1.0;

/// One recognised word. Mirrors ML Kit's `TextElement`.
class OcrWord {
  const OcrWord({required this.text, required this.bbox, this.confidence});

  final String text;
  final Rect bbox;

  /// Null on devices that do not report per-word confidence.
  final double? confidence;
}

/// One visual line. Mirrors ML Kit's `TextLine`.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.bbox,
    required this.words,
    this.confidence,
    this.angle = 0,
  });

  final String text;
  final Rect bbox;
  final List<OcrWord> words;

  /// Null when the platform does not report it.
  final double? confidence;

  /// Rotation in degrees; non-zero means the page is skewed and table
  /// detection should be skipped rather than guessing columns.
  final double angle;
}

/// All lines for one page, in the plugin's reading order.
class OcrPage {
  const OcrPage({
    required this.pageNumber,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.lines,
  });

  /// 1-based.
  final int pageNumber;
  final int pixelWidth;
  final int pixelHeight;
  final List<OcrLine> lines;

  bool get hasGeometry => pixelWidth > 0 && pixelHeight > 0;

  /// True when any line reports a non-trivial rotation.
  bool get isRotated => lines.any((l) => l.angle.abs() > ocrRotatedAngleDeg);
}
