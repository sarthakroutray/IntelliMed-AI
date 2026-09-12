// Tests for turning a PDF text layer into OCR-equivalent geometry.
//
// The risky parts are the coordinate flip (PDF is bottom-left/y-up; the OCR
// model is top-left/y-down) and the word/line grouping. Both are pure and
// exercised here without pdfium.

import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/lab/pdf_geometry.dart';

const _charWidth = 8.0;
const _lineHeight = 12.0;

/// Lay out [lines] (text, PDF baseline y) as per-character boxes.
List<PdfCharBox> _layout(List<(String, double)> lines) {
  final boxes = <PdfCharBox>[];
  for (final (text, baseY) in lines) {
    var x = 40.0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == ' ') {
        boxes.add((left: x, top: baseY, right: x, bottom: baseY));
        x += _charWidth / 2;
      } else {
        boxes.add((
          left: x,
          top: baseY + _lineHeight,
          right: x + _charWidth,
          bottom: baseY,
        ));
        x += _charWidth;
      }
    }
  }
  return boxes;
}

String _text(List<(String, double)> lines) =>
    lines.map((l) => l.$1).join('\n');

void main() {
  const lines = [('Hemoglobin 11.2 g/dL', 150.0), ('WBC 7.5', 120.0)];

  test('flips the y axis so the top line comes first', () {
    final page = ocrPageFromTextLayer(
      fullText: _text(lines),
      charBoxes: _layout(lines),
      pageWidth: 300,
      pageHeight: 200,
      pageNumber: 1,
    );

    expect(page.pageNumber, 1);
    expect(page.pixelWidth, 300);
    expect(page.pixelHeight, 200);
    expect(page.lines, hasLength(2));
    expect(page.lines.first.text, 'Hemoglobin 11.2 g/dL');
    expect(page.lines.last.text, 'WBC 7.5');

    // PDF baseline 150 with height 12 -> top 162 -> y-down 38.
    expect(page.lines.first.bbox.top, closeTo(200 - 162, 1e-9));
    // The first line is physically above the second.
    expect(page.lines.first.bbox.top, lessThan(page.lines.last.bbox.top));
  });

  test('splits each line into words with union boxes', () {
    final page = ocrPageFromTextLayer(
      fullText: _text(lines),
      charBoxes: _layout(lines),
      pageWidth: 300,
      pageHeight: 200,
      pageNumber: 1,
    );

    final first = page.lines.first;
    expect(first.words.map((w) => w.text), ['Hemoglobin', '11.2', 'g/dL']);
    expect(first.words.first.bbox.left, closeTo(40, 1e-9));
    // 10 characters at width 8.
    expect(first.words.first.bbox.right, closeTo(40 + 10 * _charWidth, 1e-9));
  });

  test('words on the same visual row are grouped into one line', () {
    // Two columns printed on one baseline stay a single line.
    const row = [('Glucose 98 mg/dL 70-100', 150.0)];
    final page = ocrPageFromTextLayer(
      fullText: _text(row),
      charBoxes: _layout(row),
      pageWidth: 300,
      pageHeight: 200,
      pageNumber: 1,
    );
    expect(page.lines, hasLength(1));
    expect(page.lines.single.words, hasLength(4));
  });

  test('empty text yields no lines', () {
    final page = ocrPageFromTextLayer(
      fullText: '',
      charBoxes: const [],
      pageWidth: 300,
      pageHeight: 200,
      pageNumber: 1,
    );
    expect(page.lines, isEmpty);
  });
}
