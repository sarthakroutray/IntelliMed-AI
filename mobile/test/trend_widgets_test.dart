// Layout regression for the trends widgets at a narrow width and large text.
// In debug builds an overflow is reported as a FlutterError during paint, which
// fails the test, so rendering these is a real overflow assertion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/screens/trend_detail_screen.dart';
import 'package:intellimed_app/theme.dart';
import 'package:intellimed_app/trends.dart';
import 'package:intellimed_app/widgets/trend_sparkline.dart';

const _narrow = Size(320, 640);
const _textScale = 1.4;

TrendSeries _series() => buildTrendSeries([
  TrendPoint(
    testName: 'Hemoglobin',
    value: 11.2,
    date: DateTime(2026, 1, 1),
    unit: 'g/dL',
    rangeLow: 13,
    rangeHigh: 17,
    flagInSource: 'L',
    sourceLabel: 'This device',
  ),
  TrendPoint(
    testName: 'Hemoglobin',
    value: 12.9,
    date: DateTime(2026, 2, 1),
    unit: 'g/dL',
    rangeLow: 13,
    rangeHigh: 17,
    sourceLabel: 'cbc_report_with_a_long_filename.pdf',
  ),
  TrendPoint(
    testName: 'Hemoglobin',
    value: 13.4,
    date: DateTime(2026, 3, 1),
    unit: 'g/dL',
    rangeLow: 13,
    rangeHigh: 17,
    sourceLabel: 'This device',
  ),
]).single;

void main() {
  testWidgets('a sparkline fits a narrow, large-text viewport', (tester) async {
    tester.view.physicalSize = _narrow;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: _narrow,
          textScaler: TextScaler.linear(_textScale),
        ),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: TrendSparkline(series: _series()),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('the analyte detail screen fits and lists its readings', (
    tester,
  ) async {
    tester.view.physicalSize = _narrow;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: _narrow,
          textScaler: TextScaler.linear(_textScale),
        ),
        child: MaterialApp(
          theme: AppTheme.light,
          home: TrendDetailScreen(series: _series()),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Hemoglobin'), findsOneWidget);
    // The header shows the latest reading; the older rows sit below the fold.
    expect(find.text('13.4 g/dL'), findsWidgets);
  });

  testWidgets('a single-reading series still renders', (tester) async {
    final single = buildTrendSeries([
      TrendPoint(
        testName: 'WBC',
        value: 7.5,
        date: DateTime(2026, 1, 1),
        unit: '10^3/uL',
      ),
    ]).single;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: TrendSparkline(series: single)),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
