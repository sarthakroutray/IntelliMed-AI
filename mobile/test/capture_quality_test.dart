// Tests for the pre-inference capture quality gate. Images are synthesised so
// each failure mode is isolated: a sharp checkerboard (pass), its blurred
// counterpart, a glare patch and a dark frame.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intellimed_app/capture_quality.dart';

img.Image _checkerboard({int size = 160, int cell = 4}) {
  final image = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      // 20/235 rather than pure black/white, so the frame is not counted as
      // glare and its mean luminance stays mid-range.
      final v = ((x ~/ cell) + (y ~/ cell)) % 2 == 0 ? 20 : 235;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

void main() {
  group('pixel gate', () {
    test('a sharp, evenly lit frame passes', () {
      final assessment = assessCapture(_checkerboard());
      expect(
        assessment.ok,
        isTrue,
        reason: 'false positive: ${assessment.issues.map((i) => i.kind)}',
      );
      expect(assessment.metrics['blurVariance'], greaterThan(90));
    });

    test('a blurred frame is flagged, with the blur value attached', () {
      final blurred = img.gaussianBlur(_checkerboard(), radius: 6);
      final assessment = assessCapture(blurred);
      expect(assessment.ok, isFalse);
      final blur = assessment.issues.firstWhere(
        (i) => i.kind == CaptureIssueKind.blur,
      );
      expect(blur.value, lessThan(90));
      expect(blur.message, contains('focus'));
    });

    test('a bright patch is flagged as glare', () {
      final image = _checkerboard();
      // Cover ~40% of the frame with clipped white.
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (x < image.width * 2 / 5) image.setPixelRgb(x, y, 255, 255, 255);
        }
      }
      final assessment = assessCapture(image);
      expect(
        assessment.issues.map((i) => i.kind),
        contains(CaptureIssueKind.glare),
      );
    });

    test('a dark frame is flagged', () {
      final image = img.Image(width: 160, height: 160);
      for (var y = 0; y < 160; y++) {
        for (var x = 0; x < 160; x++) {
          image.setPixelRgb(x, y, 20, 20, 20);
        }
      }
      final assessment = assessCapture(image);
      expect(
        assessment.issues.map((i) => i.kind),
        contains(CaptureIssueKind.tooDark),
      );
    });

    test('unreadable bytes are reported, not thrown', () {
      final assessment = assessCaptureBytes(Uint8List.fromList([1, 2, 3, 4]));
      expect(assessment.ok, isFalse);
      expect(assessment.issues.single.kind, CaptureIssueKind.unreadable);
    });

    test('the byte entry point delegates to the pixel gate', () {
      final bytes = img.encodePng(_checkerboard());
      final assessment = assessCaptureBytes(bytes);
      expect(assessment.ok, isTrue);
    });
  });

  group('text size', () {
    test('flags text below the readable height', () {
      final issue = smallTextIssue(medianLineHeightPx: 10);
      expect(issue, isNotNull);
      expect(issue!.kind, CaptureIssueKind.smallText);
    });

    test('passes readable text and ignores unknown height', () {
      expect(smallTextIssue(medianLineHeightPx: 22), isNull);
      expect(smallTextIssue(medianLineHeightPx: 0), isNull);
      expect(
        smallTextIssue(medianLineHeightPx: captureMinTextHeightPx),
        isNull,
      );
    });
  });
}
