import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intellimed_app/cnn_ocr.dart';
import 'package:intellimed_app/slm_runtime.dart';

void main() {
  group('no-repeat n-gram', () {
    test('bans the token completing a repeated trigram', () {
      // Trailing prefix (1,2) already occurred at index 0 followed by 3.
      expect(
        OnnxSlmRuntime.bannedByRepeatNgram([1, 2, 3, 1, 2], 3),
        {3},
      );
    });

    test('returns nothing when the prefix is new', () {
      expect(OnnxSlmRuntime.bannedByRepeatNgram([1, 2, 3], 3), isEmpty);
    });

    test('bans a degenerate repeated token run', () {
      expect(OnnxSlmRuntime.bannedByRepeatNgram([5, 5, 5, 5], 3), {5});
    });

    test('is inert for short sequences and invalid n', () {
      expect(OnnxSlmRuntime.bannedByRepeatNgram([1, 2], 3), isEmpty);
      expect(OnnxSlmRuntime.bannedByRepeatNgram([1, 2, 3], 1), isEmpty);
      expect(OnnxSlmRuntime.bannedByRepeatNgram(const [], 3), isEmpty);
    });
  });

  group('softmax', () {
    test('does not invert predictions with wide logit spread', () {
      // Regression: the hand-rolled Taylor-series exp went negative for the
      // negative arguments softmax always produces, flipping the argmax. A
      // confident "Normal" (class 0) was reported as class 1.
      final scores = CnnClassifier.softmax([12.0, -8.0, 2.0]);
      // exp(-10) is not negligible, so the top class sits just under 1.
      expect(scores[0], closeTo(1.0, 1e-4));
      expect(scores[1], lessThan(1e-8));
      expect(scores[2], closeTo(0.0000454, 1e-6));

      var best = 0;
      for (var i = 1; i < scores.length; i++) {
        if (scores[i] > scores[best]) best = i;
      }
      expect(best, 0, reason: 'argmax must follow the largest logit');
    });

    test('stays exact for extreme negative logits', () {
      // x = -30 previously produced ~-2e11 instead of ~9e-14.
      final scores = CnnClassifier.softmax([0.0, -30.0, -60.0]);
      expect(scores[0], closeTo(1.0, 1e-9));
      expect(scores[1], greaterThanOrEqualTo(0.0));
      expect(scores[2], greaterThanOrEqualTo(0.0));
    });

    test('produces a normalized, non-negative distribution', () {
      final scores = CnnClassifier.softmax([2.5, 1.0, -1.5]);
      for (final s in scores) {
        expect(s, greaterThan(0.0));
      }
      expect(scores.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
    });

    test('is symmetric to a uniform shift', () {
      final a = CnnClassifier.softmax([1.0, 2.0, 3.0]);
      final b = CnnClassifier.softmax([101.0, 102.0, 103.0]);
      for (var i = 0; i < a.length; i++) {
        expect(a[i], closeTo(b[i], 1e-9));
      }
    });

    test('handles empty and equal logits', () {
      expect(CnnClassifier.softmax(const []), isEmpty);
      final equal = CnnClassifier.softmax([1.0, 1.0, 1.0]);
      for (final s in equal) {
        expect(s, closeTo(1 / 3, 1e-9));
      }
    });
  });

  group('preprocessXray', () {
    test('emits NCHW float layout of the expected size', () {
      final src = img.Image(width: 448, height: 448);
      final flat = CnnClassifier.preprocessXray(src);
      expect(flat.length, 3 * xrayInputSize * xrayInputSize);
    });

    test('normalizes with ImageNet mean/std per channel', () {
      final src = img.Image(width: 4, height: 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          src.setPixelRgb(x, y, 255, 255, 255);
        }
      }
      final flat = CnnClassifier.preprocessXray(src);
      const plane = xrayInputSize * xrayInputSize;
      expect(flat[0], closeTo((1.0 - xrayMean[0]) / xrayStd[0], 1e-6));
      expect(flat[plane], closeTo((1.0 - xrayMean[1]) / xrayStd[1], 1e-6));
      expect(flat[2 * plane], closeTo((1.0 - xrayMean[2]) / xrayStd[2], 1e-6));
    });

    test('resamples with an area filter, not nearest neighbour', () {
      // Regression: copyResize defaults to Interpolation.nearest, which both
      // aliased and diverged from the backend's torchvision resize. A fine
      // black/white checkerboard downscaled 2:1 must average to mid-grey;
      // nearest sampling would return pure black or pure white instead.
      final src = img.Image(width: 448, height: 448);
      for (var y = 0; y < 448; y++) {
        for (var x = 0; x < 448; x++) {
          final v = (x + y) % 2 == 0 ? 0 : 255;
          src.setPixelRgb(x, y, v, v, v);
        }
      }

      final flat = CnnClassifier.preprocessXray(src);
      final midGrey = (0.502 - xrayMean[0]) / xrayStd[0];
      final interior = 100 * xrayInputSize + 100;
      expect(
        flat[interior],
        closeTo(midGrey, 0.15),
        reason: 'area-filtered checkerboard should land near mid-grey',
      );

      // Nearest neighbour would land on one of these poles instead.
      final black = (0.0 - xrayMean[0]) / xrayStd[0];
      final white = (1.0 - xrayMean[0]) / xrayStd[0];
      expect(flat[interior], isNot(closeTo(black, 0.5)));
      expect(flat[interior], isNot(closeTo(white, 0.5)));
    });

    test('accepts single-channel input by promoting it to RGB', () {
      final gray = img.Image(width: 4, height: 4, numChannels: 1);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          gray.setPixelRgb(x, y, 128, 128, 128);
        }
      }
      final flat = CnnClassifier.preprocessXray(gray);
      const plane = xrayInputSize * xrayInputSize;
      expect(flat.length, 3 * plane);

      // Every channel sees the same grey pixel, but each is normalized with
      // its own ImageNet mean/std, so the expected values differ per channel.
      const grey = 128 / 255.0;
      for (var c = 0; c < 3; c++) {
        expect(
          flat[c * plane],
          closeTo((grey - xrayMean[c]) / xrayStd[c], 1e-6),
          reason: 'channel $c should carry the promoted grey value',
        );
      }
    });
  });
}
