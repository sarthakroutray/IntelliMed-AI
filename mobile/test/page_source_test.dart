import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/page_source.dart';

/// These are the pure parts of file ingest: which formats we accept and how we
/// describe them. The rasterization path needs a platform PDF renderer, so it
/// is covered by the on-device integration test instead.
void main() {
  group('supported formats', () {
    test('PDFs are recognised', () {
      expect(isPdf('report.pdf'), isTrue);
      expect(isPdf('REPORT.PDF'), isTrue);
      expect(isPdf('/tmp/a/b/scan.pdf'), isTrue);
      expect(isPdf('scan.jpg'), isFalse);
    });

    test('common image formats are recognised', () {
      for (final name in [
        'a.jpg',
        'a.jpeg',
        'a.png',
        'a.webp',
        'a.bmp',
        'a.tif',
        'a.tiff',
      ]) {
        expect(isSupportedImage(name), isTrue, reason: name);
      }
    });

    test('HEIC is deliberately not claimed', () {
      // The Dart image package cannot decode HEIC, so the X-ray path would
      // fail after the photo was taken. Better to not offer it.
      expect(isSupportedImage('photo.heic'), isFalse);
      expect(isSupported('photo.heic'), isFalse);
    });

    test('kindOf classifies pdf, image, and rejects the rest', () {
      expect(kindOf('a.pdf'), SourceKind.pdf);
      expect(kindOf('a.PNG'), SourceKind.image);
      expect(() => kindOf('a.docx'), throwsA(isA<IngestException>()));
      expect(() => kindOf('a'), throwsA(isA<IngestException>()));
    });

    test('the rejection names the supported formats', () {
      try {
        kindOf('a.docx');
        fail('expected IngestException');
      } on IngestException catch (e) {
        expect(e.message, contains('docx'));
        expect(e.message, contains('pdf'));
      }
    });

    test('upload formats are a subset of what we can process locally', () {
      // The server documents a narrower set than ML Kit can read; anything we
      // upload must at least be a format we understand.
      for (final ext in uploadExtensions) {
        expect(supportedExtensions, contains(ext), reason: ext);
      }
      // WebP is on-device only.
      expect(uploadExtensions, isNot(contains('webp')));
    });
  });

  group('type labels', () {
    test('labels are human-readable', () {
      expect(fileTypeLabel('a.pdf'), 'PDF');
      expect(fileTypeLabel('a.jpg'), 'JPEG');
      expect(fileTypeLabel('a.jpeg'), 'JPEG');
      expect(fileTypeLabel('a.png'), 'PNG');
      expect(fileTypeLabel('a.tif'), 'TIFF');
      expect(fileTypeLabel('a.tiff'), 'TIFF');
      expect(fileTypeLabel('a.bmp'), 'BMP');
      expect(fileTypeLabel('a.webp'), 'WebP');
    });

    test('an unknown extension falls back to uppercase', () {
      expect(fileTypeLabel('a.docx'), 'DOCX');
    });
  });

  group('page set', () {
    test('a single-page source is not multipage and cannot be truncated', () {
      final set = PageSet(pages: [File('page_1.png')], totalPages: 1);
      expect(set.isMultipage, isFalse);
      expect(set.truncated, isFalse);
    });

    test('truncation is detected when the cap bites', () {
      // A capped document still has the pages we did process.
      final set = PageSet(
        pages: List.generate(maxPdfPages, (i) => File('page_$i.png')),
        totalPages: 30,
      );
      expect(set.isMultipage, isTrue);
      expect(set.processed, maxPdfPages);
      expect(set.truncated, isTrue);
    });

    test('a fully processed multipage document is not truncated', () {
      final set = PageSet(
        pages: [File('p1.png'), File('p2.png'), File('p3.png')],
        totalPages: 3,
      );
      expect(set.isMultipage, isTrue);
      expect(set.truncated, isFalse);
    });

    test('an empty page set is a failure, not a truncation', () {
      // Guarding this matters: reporting "first N pages used" for a document
      // that yielded nothing would mislead the reviewer.
      final set = PageSet(pages: const [], totalPages: 30);
      expect(set.truncated, isFalse);
    });

    test('the page cap is bounded', () {
      // A 500-page PDF must not look like a hang.
      expect(maxPdfPages, lessThanOrEqualTo(20));
      expect(maxPdfPages, greaterThan(1));
    });

    test('dispose is a no-op for an image source', () async {
      // An image's "pages" ARE the original file, so dispose must not delete
      // anything when there is no temp dir.
      final set = PageSet(pages: [File('photo.jpg')], totalPages: 1);
      await set.dispose();
      expect(set.tempDir, isNull);
    });
  });
}
