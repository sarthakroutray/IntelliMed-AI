// Stage 1 structure synthesis — reconstruct the backend's Stage 1 shape
// (`elements[]` + `tables[].rows[].cells[]`, see stage1_model.dart) from ML
// Kit geometry.
//
// This is the one genuinely new algorithm in the lab-report rework. It exists
// so the ported Stage 2 rule engine (rule_engine.dart) can run on-device with
// the same inputs the backend's OpenDataLoader path provides, instead of the
// flat, column-interleaved text the old regex extractor guessed at.
//
// All geometry is normalised to page-relative units (0..1) so thresholds are
// scale-invariant across photos, 200-DPI PDF renders and different devices.
// No absolute-pixel constant is used anywhere.
//
// Failure is explicit, never silent (mirrors the backend's fallback chain):
// a page with no usable geometry or a rotated page is skipped for table
// detection with a recorded warning, and a document that yields no tables at
// all is emitted as `mlkit-lines-only` so the ported plain-text fallback runs.
// Rows are never fabricated and never silently dropped.

import 'dart:math' as math;

import 'ocr_model.dart';
import 'stage1_model.dart';

// --- Tunables (page-relative) --------------------------------------------

/// A line is "grid-like" when it has at least this many word groups.
const _minGridGroups = 3;

/// Horizontal gap (as a multiple of the page's median word height) that
/// separates columns.
const _gridGapFactor = 1.6;

/// Minimum number of grid-like lines for a table region.
const _minRunLength = 3;

/// One non-grid line is tolerated inside a run (a wrapped value row).
const _maxRunGap = 1;

/// Word left edges within this fraction of page width share a column.
const _columnToleranceFrac = 0.015;

/// A column must be supported by at least this fraction of the region's lines.
const _columnSupportFrac = 0.5;

/// Y-spread (as a multiple of median word height) above which a single ML Kit
/// line is re-split into two visual rows.
const _mergeSplitFactor = 0.6;

final _headerLexiconRe = RegExp(
  r'\b(test|result|unit|reference|ref|range|method|specimen)\b',
  caseSensitive: false,
);
final _digitRe = RegExp(r'\d');
final _alphaRe = RegExp(r'[A-Za-z]');

/// Build a backend-compatible Stage 1 document from recognised pages.
LabStage1 buildStage1(List<OcrPage> pages) {
  final elements = <LabElement>[];
  final tables = <LabTable>[];
  final warnings = <String>[];
  final textLines = <String>[];

  for (final page in pages) {
    textLines.addAll(page.lines.map((l) => l.text));

    if (!page.hasGeometry) {
      warnings.add(
        'page ${page.pageNumber}: image dimensions unavailable — table '
        'structure not reconstructed (lines emitted as text only)',
      );
      elements.addAll(_elementsFromRawLines(page));
      continue;
    }
    if (page.isRotated) {
      warnings.add(
        'page ${page.pageNumber}: rotated/skewed page — table detection '
        'skipped to avoid guessing columns',
      );
      elements.addAll(_elementsFromRawLines(page));
      continue;
    }

    final lines = _normalise(page);
    final split = _resplitMergedLines(lines);
    final wordHeights = [
      for (final l in split)
        for (final w in l.words) w.height,
    ];
    final medianHeight = _median(wordHeights);
    if (medianHeight <= 0) {
      elements.addAll(_elementsFromRawLines(page));
      continue;
    }

    final isGrid = [
      for (final l in split) _wordGroups(l, medianHeight * _gridGapFactor).length >= _minGridGroups,
    ];
    final regions = _tableRegions(isGrid);
    final consumed = <int>{};

    for (final region in regions) {
      final regionLines = split.sublist(region.first, region.last + 1);
      final columns = _detectColumns(regionLines);
      if (columns.length < 2) continue;
      final rows = _buildRows(regionLines, columns, page.pageNumber);
      if (rows.isEmpty) continue;
      consumed.addAll([for (var i = region.first; i <= region.last; i++) i]);
      tables.add(
        LabTable(
          bbox: _unionOfLines(regionLines),
          page: page.pageNumber,
          nRows: rows.length,
          nCols: columns.length,
          rows: rows,
        ),
      );
    }

    for (var i = 0; i < split.length; i++) {
      if (consumed.contains(i)) continue;
      elements.add(_elementFromLine(split[i], page.pageNumber));
    }
  }

  final degraded = tables.isEmpty;
  if (degraded) {
    warnings.add(
      'no table structure reconstructed — falling back to line-by-line '
      'parsing (all rows low confidence)',
    );
  }

  return LabStage1(
    extractionEngine: degraded ? 'mlkit-lines-only' : 'mlkit-geometry',
    text: textLines.join('\n'),
    elements: _dropElementsInsideTables(elements, tables),
    tables: tables,
    warnings: warnings,
  );
}

// --- normalisation --------------------------------------------------------

class _Word {
  _Word({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  double get height => bottom - top;
  double get width => right - left;
}

class _Line {
  _Line(this.text, this.left, this.top, this.right, this.bottom, this.words);

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final List<_Word> words;
}

/// Normalise page geometry isotropically by the page width, so a horizontal
/// gap and a word height are directly comparable and every threshold is a
/// fraction of page size (the plan's `x / pixelWidth`). Dividing x and y by
/// different axes would make the gap-vs-height comparisons aspect-dependent.
List<_Line> _normalise(OcrPage page) {
  final w = page.pixelWidth.toDouble();
  return [
    for (final line in page.lines)
      _Line(
        line.text,
        line.bbox.left / w,
        line.bbox.top / w,
        line.bbox.right / w,
        line.bbox.bottom / w,
        [
          for (final word in line.words)
            _Word(
              text: word.text,
              left: word.bbox.left / w,
              top: word.bbox.top / w,
              right: word.bbox.right / w,
              bottom: word.bbox.bottom / w,
            ),
        ],
      ),
  ];
}

/// Emit lines as plain text elements when geometry is unusable.
List<LabElement> _elementsFromRawLines(OcrPage page) => [
  for (final line in page.lines)
    LabElement(
      type: _inferElementType(line.text),
      text: line.text,
      bbox: null,
      page: page.pageNumber,
    ),
];

LabElement _elementFromLine(_Line line, int page) => LabElement(
  type: _inferElementType(line.text),
  text: line.text,
  bbox: [line.left, line.top, line.right, line.bottom],
  page: page,
);

/// heading if all-caps and short, caption if it looks like a label, else text.
String _inferElementType(String text) {
  final trimmed = text.trim();
  final letters = [
    for (final c in trimmed.codeUnits)
      if (_isAsciiLetter(c)) c,
  ];
  if (letters.isNotEmpty &&
      trimmed.length <= 60 &&
      letters.every(_isUpperAscii)) {
    return 'heading';
  }
  if (trimmed.length <= 40 && trimmed.contains(':')) return 'caption';
  return 'text';
}

// --- line re-splitting ----------------------------------------------------

/// Re-split a line whose word y-centres are spread across two visual rows.
List<_Line> _resplitMergedLines(List<_Line> lines) {
  final out = <_Line>[];
  for (final line in lines) {
    if (line.words.length < 2) {
      out.add(line);
      continue;
    }
    final heights = [for (final w in line.words) w.height];
    final medianHeight = _median(heights);
    if (medianHeight <= 0) {
      out.add(line);
      continue;
    }
    final sorted = [...line.words]..sort((a, b) => a.centerY.compareTo(b.centerY));
    final groups = <List<_Word>>[];
    for (final word in sorted) {
      if (groups.isEmpty) {
        groups.add([word]);
        continue;
      }
      final gap = word.centerY - groups.last.last.centerY;
      if (gap > medianHeight * _mergeSplitFactor) {
        groups.add([word]);
      } else {
        groups.last.add(word);
      }
    }
    if (groups.length <= 1) {
      out.add(line);
      continue;
    }
    for (final group in groups) {
      final ordered = [...group]..sort((a, b) => a.left.compareTo(b.left));
      out.add(
        _Line(
          ordered.map((w) => w.text).join(' '),
          ordered.map((w) => w.left).reduce(math.min),
          ordered.map((w) => w.top).reduce(math.min),
          ordered.map((w) => w.right).reduce(math.max),
          ordered.map((w) => w.bottom).reduce(math.max),
          ordered,
        ),
      );
    }
  }
  return out;
}

// --- table region detection -----------------------------------------------

/// Split a line into word groups separated by horizontal gaps larger than
/// [gapThreshold].
List<List<_Word>> _wordGroups(_Line line, double gapThreshold) {
  final words = [...line.words]..sort((a, b) => a.left.compareTo(b.left));
  final groups = <List<_Word>>[];
  for (final word in words) {
    if (groups.isEmpty) {
      groups.add([word]);
      continue;
    }
    if (word.left - groups.last.last.right > gapThreshold) {
      groups.add([word]);
    } else {
      groups.last.add(word);
    }
  }
  return groups;
}

/// Runs of grid-like line indices forming a table region (allowing
/// [_maxRunGap] non-grid lines inside a run).
List<List<int>> _tableRegions(List<bool> isGrid) {
  final regions = <List<int>>[];
  var run = <int>[];
  for (var i = 0; i < isGrid.length; i++) {
    if (!isGrid[i]) continue;
    if (run.isEmpty) {
      run = [i];
      continue;
    }
    final gap = i - run.last - 1;
    if (gap <= _maxRunGap) {
      run.add(i);
    } else {
      if (run.length >= _minRunLength) regions.add(run);
      run = [i];
    }
  }
  if (run.length >= _minRunLength) regions.add(run);
  return regions;
}

// --- columns and rows -----------------------------------------------------

class _Column {
  _Column(this.meanCenterX, this.meanLeft)
    : sumCenter = meanCenterX,
      sumLeft = meanLeft,
      count = 1;

  double meanCenterX;
  double meanLeft;
  double sumCenter;
  double sumLeft;
  int count;
  final Set<int> lines = <int>{};

  void add(_Word word, int lineIndex) {
    sumCenter += word.centerX;
    sumLeft += word.left;
    count++;
    meanCenterX = sumCenter / count;
    meanLeft = sumLeft / count;
    lines.add(lineIndex);
  }
}

List<_Column> _detectColumns(List<_Line> regionLines) {
  final words = <(int, _Word)>[];
  for (var i = 0; i < regionLines.length; i++) {
    for (final w in regionLines[i].words) {
      words.add((i, w));
    }
  }
  words.sort((a, b) => a.$2.left.compareTo(b.$2.left));

  final clusters = <_Column>[];
  for (final (lineIndex, word) in words) {
    _Column? target;
    for (final c in clusters) {
      if ((word.left - c.meanLeft).abs() <= _columnToleranceFrac) {
        target = c;
        break;
      }
    }
    if (target == null) {
      clusters.add(_Column(word.centerX, word.left)..lines.add(lineIndex));
    } else {
      target.add(word, lineIndex);
    }
  }

  final minSupport = regionLines.length * _columnSupportFrac;
  final supported = [
    for (final c in clusters)
      if (c.lines.length >= minSupport) c,
  ]..sort((a, b) => a.meanCenterX.compareTo(b.meanCenterX));
  return supported;
}

List<LabTableRow> _buildRows(
  List<_Line> regionLines,
  List<_Column> columns,
  int page,
) {
  final rows = <LabTableRow>[];
  for (var i = 0; i < regionLines.length; i++) {
    final line = regionLines[i];
    final cells = <LabCell>[];
    for (var c = 0; c < columns.length; c++) {
      final words = [
        for (final w in line.words)
          if (_nearestColumn(w, columns) == c) w,
      ]..sort((a, b) => a.left.compareTo(b.left));
      if (words.isEmpty) continue;
      cells.add(
        LabCell(
          text: words.map((w) => w.text).join(' '),
          bbox: [
            words.map((w) => w.left).reduce(math.min),
            words.map((w) => w.top).reduce(math.min),
            words.map((w) => w.right).reduce(math.max),
            words.map((w) => w.bottom).reduce(math.max),
          ],
          page: page,
          row: i + 1,
          col: c + 1,
        ),
      );
    }
    if (cells.isNotEmpty) {
      rows.add(LabTableRow(row: i + 1, cells: cells));
    }
  }
  final merged = _attachOrphanRows(rows);
  return [...merged].map(_markHeader).toList();
}

int _nearestColumn(_Word word, List<_Column> columns) {
  var best = 0;
  var bestDistance = (word.centerX - columns.first.meanCenterX).abs();
  for (var i = 1; i < columns.length; i++) {
    final d = (word.centerX - columns[i].meanCenterX).abs();
    if (d < bestDistance) {
      bestDistance = d;
      best = i;
    }
  }
  return best;
}

/// A wrapped value can land on its own line with no alphabetic content. Attach
/// it to the nearest cell of the previous row rather than dropping it.
List<LabTableRow> _attachOrphanRows(List<LabTableRow> rows) {
  final out = <LabTableRow>[];
  for (final row in rows) {
    final hasAlpha = row.cells.any((c) => _alphaRe.hasMatch(c.text));
    if (!hasAlpha && out.isNotEmpty) {
      final prev = out.last;
      for (final cell in row.cells) {
        final index = _nearestCellIndex(cell, prev.cells);
        if (index < 0) continue;
        final target = prev.cells[index];
        prev.cells[index] = LabCell(
          text: '${target.text} ${cell.text}'.trim(),
          bbox: _unionBbox(target.bbox, cell.bbox),
          page: target.page,
          isHeader: target.isHeader,
          row: target.row,
          col: target.col,
        );
      }
      continue;
    }
    out.add(LabTableRow(row: row.row, cells: [...row.cells]));
  }
  return out;
}

int _nearestCellIndex(LabCell cell, List<LabCell> cells) {
  if (cells.isEmpty) return -1;
  final x = cell.bbox == null ? null : (cell.bbox![0] + cell.bbox![2]) / 2;
  if (x == null) return cells.length - 1;
  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < cells.length; i++) {
    final box = cells[i].bbox;
    if (box == null) continue;
    final d = (x - (box[0] + box[2]) / 2).abs();
    if (d < bestDistance) {
      bestDistance = d;
      best = i;
    }
  }
  return best;
}

LabTableRow _markHeader(LabTableRow row) {
  final rowText = row.cells.map((c) => c.text).join(' ');
  final isHeader = !_digitRe.hasMatch(rowText) || _headerLexiconRe.hasMatch(rowText);
  if (!isHeader) return row;
  return LabTableRow(
    row: row.row,
    cells: [for (final c in row.cells) _asHeader(c)],
  );
}

LabCell _asHeader(LabCell cell) => LabCell(
  text: cell.text,
  bbox: cell.bbox,
  page: cell.page,
  isHeader: true,
  row: cell.row,
  col: cell.col,
);

// --- small helpers --------------------------------------------------------

List<double>? _unionOfLines(List<_Line> lines) {
  if (lines.isEmpty) return null;
  return [
    lines.map((l) => l.left).reduce(math.min),
    lines.map((l) => l.top).reduce(math.min),
    lines.map((l) => l.right).reduce(math.max),
    lines.map((l) => l.bottom).reduce(math.max),
  ];
}

List<double>? _unionBbox(List<double>? a, List<double>? b) {
  if (a == null) return b;
  if (b == null) return a;
  return [
    math.min(a[0], b[0]),
    math.min(a[1], b[1]),
    math.max(a[2], b[2]),
    math.max(a[3], b[3]),
  ];
}

/// The rule engine reconstructs rows from text elements outside tables; drop
/// any element whose box falls inside a table box so nothing is duplicated.
List<LabElement> _dropElementsInsideTables(
  List<LabElement> elements,
  List<LabTable> tables,
) {
  if (tables.isEmpty) return elements;
  return [
    for (final el in elements)
      if (!tables.any((t) => el.page == t.page && _inside(el.bbox, t.bbox))) el,
  ];
}

bool _inside(List<double>? inner, List<double>? outer) {
  if (inner == null || outer == null) return false;
  return inner[0] >= outer[0] &&
      inner[2] <= outer[2] &&
      inner[1] >= outer[1] &&
      inner[3] <= outer[3];
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

bool _isAsciiLetter(int c) => (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);

bool _isUpperAscii(int c) => c >= 0x41 && c <= 0x5a;
