import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/api/models.dart';
import 'package:intellimed_app/document_type.dart';
import 'package:intellimed_app/theme.dart';
import 'package:intellimed_app/widgets/app_card.dart';
import 'package:intellimed_app/widgets/filter_chips.dart';
import 'package:intellimed_app/widgets/result_viewers.dart';
import 'package:intellimed_app/widgets/stat_card.dart';

/// Layout regression tests.
///
/// In debug builds a Flutter overflow reports a FlutterError during paint, and
/// `testWidgets` fails the test when that happens. So simply rendering these
/// widgets inside a narrow, large-text viewport is a real overflow assertion —
/// these are the exact combinations that overflowed before.
///
/// 320x640 is a small phone (and a common split-screen width); 1.4x text is
/// within the range Android allows from system font settings.

const _narrow = Size(320, 640);
const _textScale = 1.4;

Widget _host(Widget child, {Size size = _narrow, double scale = _textScale}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      textScaler: TextScaler.linear(scale),
    ),
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  for (final size in const [Size(320, 640), Size(360, 800), Size(412, 915)]) {
    group('at ${size.width.toInt()}dp wide', () {
      testWidgets('a pair of stat cards fits', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Mirrors Home: two cards in an IntrinsicHeight row.
        await tester.pumpWidget(
          _host(
            ListView(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      Expanded(
                        child: StatCard(
                          label: 'Reports',
                          value: '128',
                          icon: Icons.description_outlined,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: StatCard(
                          label: 'Pending sync',
                          value: '12',
                          icon: Icons.sync_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Pending sync'), findsOneWidget);
      });

      testWidgets('a lab test row with long content fits', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final test = LabTest.fromJson({
          'test_name': 'Mean Corpuscular Hemoglobin Concentration',
          'raw_test_name': 'MCHC',
          'value': 33.5,
          'unit': 'g/dL',
          'range_low': 32,
          'range_high': 36,
          'abnormal': true,
          'direction': 'high',
          'flag_in_source': 'HH',
        });

        await tester.pumpWidget(_host(ListView(children: [LabTestRow(test: test)])));

        expect(tester.takeException(), isNull);
        expect(find.text('Mean Corpuscular Hemoglobin Concentration'), findsOneWidget);
      });

      testWidgets('a lab test row with a long unit fits', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final test = LabTest.fromJson({
          'test_name': 'White Blood Cell Count',
          'value': 7500,
          'unit': 'cells/cumm',
          'range_raw': '4000-11000 cells/cumm',
        });

        await tester.pumpWidget(_host(ListView(children: [LabTestRow(test: test)])));

        expect(tester.takeException(), isNull);
      });

      testWidgets('the capture type chips fit four options', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _host(
            ListView(
              children: [
                AppCard(
                  child: FilterChips<CaptureMode>(
                    values: CaptureMode.values,
                    selected: CaptureMode.auto,
                    labelOf: (m) => m.label,
                    onSelected: (_) {},
                  ),
                ),
              ],
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        // All four stay visible rather than scrolling off-screen.
        for (final mode in CaptureMode.values) {
          expect(find.text(mode.label), findsOneWidget);
        }
      });

      testWidgets('a flagged pattern with long text fits', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final pattern = FlaggedPattern.fromJson({
          'pattern_name':
              'PLACEHOLDER_combined_microcytic_hypochromic_pattern_for_review',
          'surfaced_text':
              'Pattern consistent with a combined low pattern — recommend '
              'clinical review alongside the printed reference ranges.',
          'panel_name': 'Complete Blood Count With Differential',
          'triggering_tests': [
            {
              'test_name': 'Mean Corpuscular Hemoglobin',
              'value': 24.1,
              'unit': 'pg',
              'direction': 'low',
            },
          ],
        });

        await tester.pumpWidget(
          _host(ListView(children: [FlaggedPatternCard(pattern: pattern)])),
        );

        expect(tester.takeException(), isNull);
      });

      testWidgets('xray probability bars fit', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final xray = XrayResult.fromJson({
          'top_pattern': 'Bacterial Pneumonia',
          'confidence': 0.71,
          'probabilities': {
            'Normal': 0.12,
            'Bacterial Pneumonia': 0.71,
            'Viral Pneumonia': 0.17,
          },
        });

        await tester.pumpWidget(
          _host(ListView(children: [XrayProbabilityBars(xray: xray)])),
        );

        expect(tester.takeException(), isNull);
        // Appears twice by design: as the top pattern and as its bar label.
        expect(find.text('Bacterial Pneumonia'), findsWidgets);
        expect(find.text('Normal'), findsOneWidget);
      });

      testWidgets('a summary card with long findings fits', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final summary = SummaryContext.fromJson({
          'medical_summary':
              'Complete blood count showing a mild microcytic hypochromic '
              'pattern with a reduced haemoglobin concentration.',
          'key_findings': [
            'Haemoglobin below the printed reference range',
            'Mean corpuscular volume at the lower printed limit',
          ],
        });

        await tester.pumpWidget(
          _host(ListView(children: [SummaryContextCard(summary: summary)])),
        );

        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('long values are ellipsised rather than overflowing', (tester) async {
    tester.view.physicalSize = _narrow;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _host(
        ListView(
          children: const [
            StatCard(
              label: 'A very long stat label that cannot possibly fit',
              value: '999999',
              icon: Icons.folder_outlined,
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final label = tester.widget<Text>(
      find.text('A very long stat label that cannot possibly fit'),
    );
    expect(label.overflow, TextOverflow.ellipsis);
    expect(label.maxLines, 1);
  });
}
