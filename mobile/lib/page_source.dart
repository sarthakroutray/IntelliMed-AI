// File ingest for on-device inference.
//
// The on-device pipeline (ML Kit OCR -> normalizer -> T5, or the ResNet50
// X-ray head) works on *images*. The user can hand us many more formats than
// that, so this layer is the single place that knows how to turn any supported
// file into page images:
//
//   * images (jpg/jpeg/png/webp/bmp/heic/heif/tif/tiff) -> the file itself
//   * PDFs                                               -> rasterized pages
//
// PDF rasterization goes through `pdfx`, which uses the platform renderer
// (Android PdfRenderer). On Android pages cannot be rendered in parallel, so
// rasterization is strictly sequential and each page is closed before the next.
//
// Anything else is rejected with a clear message rather than being fed to OCR
// and producing nonsense.

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

/// Extensions accepted for on-device capture.
///
/// Deliberately excludes HEIC/HEIF: ML Kit's HEIC support is inconsistent
/// across devices and, more importantly, the Dart `image` package cannot
/// decode HEIC, so the X-ray path would fail after the user had already taken
/// the photo. Claiming support we cannot honour is worse than not listing it.
const supportedExtensions = <String>[
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'webp',
  'bmp',
  'tif',
  'tiff',
];

/// Extensions accepted for the server upload path (Docs).
///
/// Narrower than [supportedExtensions]: the backend runs its own
/// OpenDataLoader/EasyOCR pipeline, and this set is what it documents as
/// readable.
const uploadExtensions = <String>[
  'pdf',
  'jpg',
  'jpeg',
  'png',
  'bmp',
  'tif',
  'tiff',
];

/// Extensions ML Kit can OCR directly (no rasterization needed).
const _imageExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'webp',
  'bmp',
  'tif',
  'tiff',
};

/// Hard cap on pages processed from one PDF.
///
/// Inference is serial and a page costs an OCR pass, so an unbounded document
/// would look like a hang. The first [maxPdfPages] are processed and the
/// truncation is recorded in the envelope.
const maxPdfPages = 12;

/// Render scale for PDF rasterization.
///
/// PDF space is 72 DPI, so 200/72 ≈ 2.78 gives ~200 DPI — enough for ML Kit to
/// read small print reliably without producing huge bitmaps.
const _pdfRenderScale = 200 / 72;

/// Cap on the rendered page's long edge, so a huge poster-size PDF cannot
/// allocate hundreds of megabytes.
const _pdfMaxEdge = 2600.0;

/// A file we refused to ingest.
class IngestException implements Exception {
  IngestException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The source is an image or a multipage PDF.
enum SourceKind { image, pdf }

String extensionOf(String path) =>
    p.extension(path).replaceFirst('.', '').toLowerCase();

bool isPdf(String path) => extensionOf(path) == 'pdf';

bool isSupportedImage(String path) => _imageExtensions.contains(extensionOf(path));

bool isSupported(String path) {
  final ext = extensionOf(path);
  return supportedExtensions.contains(ext);
}

SourceKind kindOf(String path) {
  if (isPdf(path)) return SourceKind.pdf;
  if (isSupportedImage(path)) return SourceKind.image;
  throw IngestException(
    'Unsupported file type ".${extensionOf(path)}". Supported: '
    '${supportedExtensions.join(', ')}.',
  );
}

/// Human label for a file type, for chips and list rows.
String fileTypeLabel(String path) {
  final ext = extensionOf(path);
  switch (ext) {
    case 'pdf':
      return 'PDF';
    case 'jpg':
    case 'jpeg':
      return 'JPEG';
    case 'png':
      return 'PNG';
    case 'tif':
    case 'tiff':
      return 'TIFF';
    case 'bmp':
      return 'BMP';
    case 'heic':
    case 'heif':
      return 'HEIC';
    case 'webp':
      return 'WebP';
    default:
      return ext.isEmpty ? 'File' : ext.toUpperCase();
  }
}

/// Page images extracted from a source, plus what was skipped.
class PageSet {
  const PageSet({
    required this.pages,
    required this.totalPages,
    this.tempDir,
  });

  /// Page images in document order.
  final List<File> pages;

  /// Pages in the source document, before the [maxPdfPages] cap.
  final int totalPages;

  /// Directory holding rasterized pages, when the source was a PDF. Null for
  /// an image, where [pages] is the original file — deleting that would
  /// destroy the user's data.
  final Directory? tempDir;

  int get processed => pages.length;
  bool get isMultipage => totalPages > 1;

  /// True when the document had more pages than we processed.
  ///
  /// Guarded on a non-empty [pages]: extracting zero pages is a failure, not a
  /// truncation, and must not be reported to the reviewer as a deliberate cap.
  bool get truncated => pages.isNotEmpty && totalPages > pages.length;

  /// Remove rasterized scratch files. Never touches the original source.
  Future<void> dispose() async {
    final dir = tempDir;
    if (dir == null) return;
    await PageSource._safeDelete(dir);
  }
}

/// The file ingest service.
class PageSource {
  const PageSource._();

  /// Directory holding a durable copy of each capture's source file.
  ///
  /// A copy is kept (rather than the picker's cache path) for two reasons:
  /// the picker path can be purged by the OS at any time, and a capture can be
  /// re-run later with a corrected document type — which needs the original.
  static Future<Directory> _captureDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'captures'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copy [source] into app storage and return the canonical path.
  static Future<File> persist(File source, {required String filename}) async {
    final ext = extensionOf(filename);
    if (ext.isNotEmpty && !supportedExtensions.contains(ext)) {
      throw IngestException(
        'Unsupported file type ".$ext". Supported: '
        '${supportedExtensions.join(', ')}.',
      );
    }
    final dir = await _captureDir();
    final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final target = File(p.join(dir.path, '${stamp}_$safe'));
    await target.writeAsBytes(await source.readAsBytes(), flush: true);
    return target;
  }

  /// Delete a persisted source, but only if it lives inside our capture
  /// directory. Guards against a stale row ever removing an arbitrary file.
  static Future<void> removePersisted(String path) async {
    try {
      final dir = await _captureDir();
      final normalized = p.normalize(path);
      if (!p.isWithin(dir.path, normalized)) return;
      final file = File(normalized);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort: leaving an orphaned file is safer than deleting wrongly.
    }
  }

  /// Extract page images for inference.
  ///
  /// Images are returned as-is (no copy, no scratch dir). PDFs are rasterized
  /// into a temp directory that the caller must release via [PageSet.dispose].
  static Future<PageSet> pagesFor(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw IngestException('The file is no longer available on this device.');
    }

    final kind = kindOf(path);
    if (kind == SourceKind.image) {
      return PageSet(pages: [file], totalPages: 1);
    }

    final tempRoot = await getTemporaryDirectory();
    final tempDir = await Directory(
      p.join(tempRoot.path, 'pdf_${DateTime.now().microsecondsSinceEpoch}'),
    ).create(recursive: true);

    final pages = <File>[];
    PdfDocument? document;
    var succeeded = false;
    try {
      document = await _open(path);
      final total = document.pagesCount;
      if (total <= 0) {
        throw IngestException('That PDF has no readable pages.');
      }

      // Opened once: reading pagesCount off the same handle avoids a second
      // native open, which is slow for a large document.
      final limit = total < maxPdfPages ? total : maxPdfPages;
      for (var number = 1; number <= limit; number++) {
        // Android cannot render pages in parallel, so this loop is strictly
        // sequential and each page is closed before the next is opened.
        final page = await document.getPage(number);
        try {
          final scale = _scaleFor(page.width, page.height);
          final rendered = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: PdfPageImageFormat.png,
          );
          if (rendered == null) continue;
          final target = File(p.join(tempDir.path, 'page_$number.png'));
          await target.writeAsBytes(rendered.bytes, flush: true);
          pages.add(target);
        } finally {
          await page.close();
        }
      }

      if (pages.isEmpty) {
        throw IngestException('No pages could be read from that PDF.');
      }

      succeeded = true;
      return PageSet(pages: pages, totalPages: total, tempDir: tempDir);
    } catch (e) {
      if (e is IngestException) rethrow;
      throw IngestException('Page rendering failed: $e');
    } finally {
      await document?.close();
      // Only clean up on failure; on success the caller owns the scratch dir
      // and releases it via PageSet.dispose().
      if (!succeeded) await _safeDelete(tempDir);
    }
  }

  /// Open a PDF, mapping any platform failure to a clear message.
  static Future<PdfDocument> _open(String path) async {
    try {
      return await PdfDocument.openFile(path);
    } catch (_) {
      throw IngestException(
        'That PDF could not be opened. It may be corrupted or '
        'password-protected.',
      );
    }
  }

  /// Number of pages in a PDF without rendering them.
  static Future<int> pageCount(String path) async {
    final document = await _open(path);
    try {
      return document.pagesCount;
    } finally {
      await document.close();
    }
  }

  static Future<void> _safeDelete(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Scratch cleanup is best-effort; the OS reclaims the temp dir.
    }
  }

  static double _scaleFor(double width, double height) {
    var scale = _pdfRenderScale;
    final longEdge = width > height ? width : height;
    final projected = longEdge * scale;
    if (projected > _pdfMaxEdge) scale = _pdfMaxEdge / longEdge;
    return scale;
  }

  /// Write bytes to a temp file, for sources that arrive in memory.
  static Future<File> writeTemp(Uint8List bytes, String filename) async {
    final dir = await getTemporaryDirectory();
    final safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(
      p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}_$safe'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
