// Minimal sparkline for one unit-consistent test series.
//
// No charting dependency: a deterministic CustomPainter keeps the bundle small
// and draws exactly what the trends rule requires — a value line plus the
// report's own printed reference band shaded behind it. It never colours a
// point to imply "good" or "bad"; that would be an interpretation.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../trends.dart';

class TrendSparkline extends StatelessWidget {
  const TrendSparkline({
    super.key,
    required this.series,
    this.height = 56,
    this.showBand = true,
  });

  final TrendSeries series;
  final double height;
  final bool showBand;

  @override
  Widget build(BuildContext context) {
    final band = showBand ? series.referenceBand : null;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          points: series.points,
          bandLow: band?.low,
          bandHigh: band?.high,
          lineColor: AppColors.primary,
          bandColor: AppColors.primary.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.points,
    required this.lineColor,
    required this.bandColor,
    this.bandLow,
    this.bandHigh,
  });

  final List<TrendPoint> points;
  final double? bandLow;
  final double? bandHigh;
  final Color lineColor;
  final Color bandColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    final values = [for (final p in points) p.value];
    final bounds = <double>[
      ...values,
      ?bandLow,
      ?bandHigh,
    ];
    var lo = bounds.reduce(math.min);
    var hi = bounds.reduce(math.max);
    if (hi - lo < 1e-9) {
      // A flat series still needs a vertical extent to draw against.
      final pad = hi.abs() < 1 ? 1.0 : hi.abs() * 0.1;
      lo -= pad;
      hi += pad;
    }
    final range = hi - lo;
    lo -= range * 0.08;
    hi += range * 0.08;

    double yFor(double value) =>
        size.height - ((value - lo) / (hi - lo)) * size.height;

    if (bandLow != null || bandHigh != null) {
      final high = yFor(bandHigh ?? bandLow!);
      final low = yFor(bandLow ?? bandHigh!);
      canvas.drawRect(
        Rect.fromLTRB(0, high, size.width, low),
        Paint()..color = bandColor,
      );
    }

    final n = points.length;
    double xFor(int i) =>
        n == 1 ? size.width / 2 : (i / (n - 1)) * size.width;

    if (n > 1) {
      final path = Path()..moveTo(xFor(0), yFor(values[0]));
      for (var i = 1; i < n; i++) {
        path.lineTo(xFor(i), yFor(values[i]));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    final dot = Paint()..color = lineColor;
    for (var i = 0; i < n; i++) {
      final radius = i == n - 1 ? 3.2 : 2.2;
      canvas.drawCircle(Offset(xFor(i), yFor(values[i])), radius, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.points != points ||
      old.bandLow != bandLow ||
      old.bandHigh != bandHigh ||
      old.lineColor != lineColor;
}
