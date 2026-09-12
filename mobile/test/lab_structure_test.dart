// Geometry synthesis tests (WS2). Each fixture is a recorded ML Kit tree
// (blocks -> lines -> elements with boxes) reduced to the fields structure.dart
// consumes. They cover the cases the plan calls out: a clean digital table, a
// merged two-row line plus a wrapped value, a rotated page, and a page with no
// usable geometry.
//
// The stage1 these produce is then fed through the rule engine to prove the
// two stages compose (and that traceable source_bbox reaches the wire schema).

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intellimed_app/lab/ocr_model.dart';
import 'package:intellimed_app/lab/rule_engine.dart';
import 'package:intellimed_app/lab/structure.dart';

const _dir = 'test/fixtures/lab';

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('$_dir/$name').readAsStringSync()) as Map<String, dynamic>;

Rect _rect(Object? value) {
  final l = (value as List).map((e) => (e as num).toDouble()).toList();
  return Rect.fromLTRB(l[0], l[1], l[2], l[3]);
}

OcrPage _page(Map<String, dynamic> json) => OcrPage(
  pageNumber: json['page'] as int,
  pixelWidth: json['pixel_width'] as int,
  pixelHeight: json['pixel_height'] as int,
  lines: [
    for (final line in (json['lines'] as List).cast<Map<String, dynamic>>())
      OcrLine(
        text: line['text'] as String,
        bbox: _rect(line['bbox']),
        angle: (line['angle'] as num?)?.toDouble() ?? 0,
        confidence: (line['confidence'] as num?)?.toDouble(),
        words: [
          for (final word in (line['words'] as List).cast<Map<String, dynamic>>())
            OcrWord(
              text: word['text'] as String,
              bbox: _rect(word['bbox']),
              confidence: (word['confidence'] as num?)?.toDouble(),
            ),
        ],
      ),
  ],
);

void main() {
  group('clean table', () {
    final stage1 = buildStage1([_page(_read('clean_table.geometry.json'))]);

    test('reconstructs columns, rows and a table region', () {
      expect(stage1.extractionEngine, 'mlkit-geometry');
      expect(stage1.tables, hasLength(1));
      final table = stage1.tables.first;
      expect(table.page, 1);
      expect(table.nCols, 4);
      expect(table.nRows, 6); // header + 5 data rows
      expect(table.rows.first.cells.first.text, 'Test');
      expect(table.rows[1].cells.first.text, 'Hemoglobin (Hb)');
      expect(table.rows[1].cells[1].text, '11.2');
      expect(table.rows[1].cells[3].text, '13.0-17.0');
    });

    test('keeps only the non-table lines as elements', () {
      final texts = stage1.elements.map((e) => e.text).toList();
      expect(texts, contains('COMPLETE BLOOD COUNT'));
      expect(texts.any((t) => t.contains('Hemoglobin')), isFalse);
      // The heading is typed so the panel-name lookup can prefer it.
      final heading = stage1.elements.firstWhere(
        (e) => e.text == 'COMPLETE BLOOD COUNT',
      );
      expect(heading.type, 'heading');
    });

    test('the rule engine turns it into traceable tests', () {
      final doc = buildLabDocument(stage1);
      expect(doc.panels, hasLength(1));
      expect(doc.panels.first.panelName, 'COMPLETE BLOOD COUNT');
      final tests = doc.panels.first.tests;
      expect(tests, hasLength(5));

      final hb = tests.first;
      expect(hb.testName, 'Hemoglobin');
      expect(hb.value, 11.2);
      expect(hb.unit, 'g/dL');
      expect(hb.rangeLow, 13.0);
      expect(hb.rangeHigh, 17.0);
      expect(hb.ocrConfidence, 'high');
      // Geometry is preserved: this is the traceability that was always null.
      expect(hb.sourceBbox, isNotNull);

      final ldl = tests.last;
      expect(ldl.flagInSource, 'H');
      expect(ldl.rangeHigh, 200.0);
    });
  });

  group('merged line and wrapped value', () {
    final stage1 = buildStage1([_page(_read('merged_wrapped.geometry.json'))]);

    test('splits a two-row line and attaches the orphan range', () {
      expect(stage1.tables, hasLength(1));
      final table = stage1.tables.first;
      expect(table.nRows, 4); // Hemoglobin, WBC(+wrapped), Platelet, Creatinine
      final names = [for (final r in table.rows) r.cells.first.text];
      expect(names, contains('Hemoglobin'));
      expect(names, contains('WBC'));

      final reversed = table.rows
          .expand((r) => r.cells)
          .map((c) => c.text)
          .where((t) => t.contains('4.0-11.0 13.0-17.0'));
      expect(reversed, isNotEmpty, reason: 'wrapped value was dropped');
    });

    test('the rule engine yields both merged rows as tests', () {
      final doc = buildLabDocument(stage1);
      final tests = doc.panels.first.tests;
      expect(tests.map((t) => t.testName), containsAll(['Hemoglobin', 'White Blood Cell Count']));
    });
  });

  group('degraded pages are explicit, never silent', () {
    test('a rotated page skips table detection with a warning', () {
      final stage1 = buildStage1([_page(_read('rotated_page.geometry.json'))]);
      expect(stage1.extractionEngine, 'mlkit-lines-only');
      expect(stage1.tables, isEmpty);
      expect(stage1.warnings.any((w) => w.contains('rotated')), isTrue);
      // The line still flows through the plain-text fallback at low confidence.
      final doc = buildLabDocument(stage1);
      final tests = doc.panels.first.tests;
      expect(tests, hasLength(1));
      expect(tests.first.ocrConfidence, 'low');
    });

    test('a page without geometry degrades to text-only elements', () {
      final stage1 = buildStage1([_page(_read('no_geometry.geometry.json'))]);
      expect(stage1.extractionEngine, 'mlkit-lines-only');
      expect(stage1.elements, hasLength(1));
      expect(stage1.elements.first.bbox, isNull);
      expect(
        stage1.warnings.any((w) => w.contains('image dimensions unavailable')),
        isTrue,
      );
    });
  });
}
