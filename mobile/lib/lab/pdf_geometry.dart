// Turn a PDF text layer into the OCR-equivalent geometry `structure.dart`
// consumes. Pure Dart (no pdfium/plugin), so it is unit-testable.
//
// Input boxes are in PDF page coordinates: origin at the bottom-left, y
// pointing up. Output is Flutter-style y-down [Rect]s, grouped into words and
// visual lines, matching what ML Kit produces for a rasterised page.

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'ocr_model.dart';

/// One character's box in PDF page coordinates (y up).
typedef PdfCharBox = ({double left, double top, double right, double bottom});

/// Build one page from a PDF text layer.
OcrPage ocrPageFromTextLayer({
  required String fullText,
  required List<PdfCharBox> charBoxes,
  required double pageWidth,
  required double pageHeight,
  required int pageNumber,
}) => OcrPage(
  pageNumber: pageNumber,
  // PDF points; `structure.dart` normalises isotropically by width, so the unit
  // only has to be consistent within the page.
  pixelWidth: math.max(1, pageWidth.round()),
  pixelHeight: math.max(1, pageHeight.round()),
  lines: _groupIntoLines(_words(fullText, charBoxes, pageHeight)),
);

class _RawWord {
  const _RawWord(this.text, this.box);
  final String text;
  final Rect box;
}

/// Build word boxes from per-character boxes, splitting on whitespace.
List<_RawWord> _words(
  String text,
  List<PdfCharBox> boxes,
  double pageHeight,
) {
  final words = <_RawWord>[];
  var i = 0;
  while (i < text.length) {
    if (_isSpace(text.codeUnitAt(i))) {
      i++;
      continue;
    }
    final start = i;
    Rect? box;
    while (i < text.length && !_isSpace(text.codeUnitAt(i))) {
      if (i < boxes.length) {
        final b = boxes[i];
        if (!_isEmptyBox(b)) {
          final r = _toRect(b, pageHeight);
          box = box == null ? r : box.expandToInclude(r);
        }
      }
      i++;
    }
    if (box != null) words.add(_RawWord(text.substring(start, i), box));
  }
  return words;
}

bool _isEmptyBox(PdfCharBox b) => b.left >= b.right || b.top <= b.bottom;

/// PDF's bottom-left origin and upward y becomes Flutter's downward y.
Rect _toRect(PdfCharBox b, double pageHeight) => Rect.fromLTRB(
  b.left,
  pageHeight - b.top,
  b.right,
  pageHeight - b.bottom,
);

bool _isSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d || c == 0xa0;

/// Group words into visual lines by vertical proximity, then left-to-right.
List<OcrLine> _groupIntoLines(List<_RawWord> words) {
  if (words.isEmpty) return const [];
  final heights =
      words.map((w) => w.box.height).where((h) => h > 0).toList()..sort();
  final median = heights.isEmpty ? 0.0 : heights[heights.length ~/ 2];
  final tolerance = median > 0 ? median * 0.6 : 1.0;

  final sorted = [...words]
    ..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));
  final groups = <List<_RawWord>>[];
  for (final word in sorted) {
    // Compare against the group's top word so groups cannot chain downwards.
    if (groups.isEmpty ||
        (word.box.center.dy - groups.last.first.box.center.dy).abs() >
            tolerance) {
      groups.add([word]);
    } else {
      groups.last.add(word);
    }
  }

  final lines = <OcrLine>[];
  for (final group in groups) {
    final ordered = [...group]
      ..sort((a, b) => a.box.left.compareTo(b.box.left));
    var box = ordered.first.box;
    for (final word in ordered.skip(1)) {
      box = box.expandToInclude(word.box);
    }
    lines.add(
      OcrLine(
        text: ordered.map((w) => w.text).join(' '),
        bbox: box,
        words: [for (final w in ordered) OcrWord(text: w.text, bbox: w.box)],
      ),
    );
  }
  return lines;
}
