// Digital-PDF text layer extraction.
//
// A digital PDF already carries the exact characters; rasterizing it and
// running OCR throws that away and re-guesses it — OCR confuses 1/l and 0/O,
// drops decimal points, and interleaves columns. pdfrx exposes pdfium's text
// layer with a bounding box per character, so we can rebuild the same OcrPage
// geometry the OCR path produces, but from exact text.
//
// Strictly additive: any failure (no text layer, encrypted/odd PDF, plugin
// unavailable) returns null and the caller falls back to rasterize + OCR.

import 'dart:math' as math;

import 'package:pdfrx/pdfrx.dart';

import 'ocr_model.dart';
import 'pdf_geometry.dart';

/// A document needs at least this much text for the layer to be treated as a
/// real text layer rather than the near-empty output of a scanned PDF.
const pdfTextLayerMinCharsPerDoc = 80;

class PdfTextLayer {
  const PdfTextLayer({required this.pages, required this.totalPages});

  final List<OcrPage> pages;

  /// Pages in the source document, before the [maxPages] cap.
  final int totalPages;
}

/// Read a PDF's text layer as OCR-equivalent pages, or null when there is no
/// usable text layer (scanned/image-only, encrypted, or extraction failed).
Future<PdfTextLayer?> readPdfTextLayer(String path, {int maxPages = 12}) async {
  PdfDocument? document;
  try {
    // Required before using the engine APIs without a pdfrx widget. Idempotent.
    await pdfrxFlutterInitialize();
    document = await PdfDocument.openFile(path);
    final all = document.pages;
    final limit = math.min(all.length, maxPages);
    final pages = <OcrPage>[];
    var chars = 0;
    for (var i = 0; i < limit; i++) {
      final page = all[i];
      final raw = await page.loadText();
      if (raw == null || raw.fullText.trim().isEmpty) continue;
      chars += raw.fullText.trim().length;
      pages.add(_toPage(raw, page.width, page.height, i + 1));
    }
    if (pages.isEmpty || chars < pdfTextLayerMinCharsPerDoc) return null;
    return PdfTextLayer(pages: pages, totalPages: all.length);
  } catch (_) {
    // Any pdfium/plugin failure: let the caller OCR instead.
    return null;
  } finally {
    await document?.dispose();
  }
}

OcrPage _toPage(
  PdfPageRawText raw,
  double width,
  double height,
  int pageNumber,
) => ocrPageFromTextLayer(
  fullText: raw.fullText,
  charBoxes: [
    for (final r in raw.charRects)
      (left: r.left, top: r.top, right: r.right, bottom: r.bottom),
  ],
  pageWidth: width,
  pageHeight: height,
  pageNumber: pageNumber,
);
