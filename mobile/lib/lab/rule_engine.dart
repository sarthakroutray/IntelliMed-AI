// Stage 2 rule engine — a faithful Dart port of
// `backend/lab_pipeline/slm_stage.py`.
//
// Hard invariants carried over verbatim (see the Python module header):
// - Never compute abnormal flags from value-vs-range comparison. Only
//   source-printed flags are captured; range comparison stays Stage 3.
// - Never fabricate reference ranges or patient identity — null when absent.
// - Ambiguous rows are reconstructed at ocr_confidence "low", never dropped.
//
// The output mirrors the fixed lab-report schema exactly (10 keys per test),
// so it satisfies both `schemas.dart::validateLabReport` and the server's
// `_REQUIRED_LAB_TEST_KEYS`.
//
// Coordinate note: `bboxTolerance` mirrors the backend's 5.0 PDF-point
// tolerance for parity with the Python reference. On-device geometry is
// page-relative, and the pipeline passes a page-relative tolerance; the
// check is inert there because structure synthesis never puts a line both
// inside a table and into an element.

import 'dart:math' as math;

import 'stage1_model.dart';
import 'test_names.dart';

// --- Value / unit / range / flag parsing --------------------------------

final _numberRe = RegExp(
  r'(?<![\w.])(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)(?![\w])',
);

const _unitPattern =
    r'(?:g/dL|mg/dL|µg/dL|ug/dL|ng/mL|ng/dL|pg/mL|pg/pg|g/L|mg/L|µg/L|ug/L|'
    r'mmol/L|µmol/L|umol/L|mEq/L|meq/L|'
    r'U/L|IU/L|mIU/mL|µIU/mL|uIU/mL|IU/mL|U/mL|'
    r'10\^?3/(?:uL|µL|ul|μL)|10\^?6/(?:uL|µL|ul|μL)|10\^?9/L|10\^?12/L|'
    r'cells/uL|cells/HPF|/HPF|/uL|/µL|/ul|'
    r'copies/mL|fL|mm/hr|mm/h|%|ratio)';

/// Full-string match: is the text exactly a unit?
final _unitRe = RegExp('^$_unitPattern\$', caseSensitive: false);

/// Prefix match, mirroring Python's `_UNIT_SEARCH_RE.match`.
final _unitPrefixRe = RegExp('^$_unitPattern', caseSensitive: false);

/// Unanchored search, mirroring Python's `_UNIT_SEARCH_RE.search`.
final _unitSearchRe = RegExp(_unitPattern, caseSensitive: false);

final _rangePairRe = RegExp(
  r'(?<![\d.])(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*(?:-|–|—|to)\s*'
  r'(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)(?![\d.])',
  caseSensitive: false,
);

final _rangeLtRe = RegExp(
  r'(?:<|≤|<=|less than\s*|up to\s*|upto\s*)\s*(\d+(?:\.\d+)?)',
  caseSensitive: false,
);

final _rangeGtRe = RegExp(
  r'(?:>|≥|>=|greater than\s*|more than\s*)\s*(\d+(?:\.\d+)?)',
  caseSensitive: false,
);

/// Only source-printed flags qualify. Case-sensitive for single letters so
/// prose "h"/"l" cannot be mistaken for flags.
const _sourceFlagTokens = {'H', 'HH', 'L', 'LL', 'A', 'C'};

final _sourceFlagWordsRe = RegExp(
  r'\b(High|Low|Abn|Abnormal|Critical)\b\.?',
  caseSensitive: false,
);

final _sourceFlagStarsRe = RegExp(r'\*{1,2}$');

final _valueRowMarkerRe = RegExp(r'\b(value|result|finding)\b', caseSensitive: false);

/// Parse the first number in [text], or null. Mirrors `_parse_number`.
double? parseNumber(String text) {
  final m = _numberRe.firstMatch(text);
  if (m == null) return null;
  return double.parse(m.group(1)!.replaceAll(',', ''));
}

bool looksLikeUnit(String text) =>
    _unitRe.hasMatch(_rstrip(text.trim(), '.'));

/// Parse a printed range into (low, high, raw). Mirrors `_parse_range`.
({double? low, double? high, String? raw}) parseRange(String text) {
  final t = text.trim();
  final pair = _rangePairRe.firstMatch(t);
  if (pair != null) {
    return (
      low: double.parse(pair.group(1)!.replaceAll(',', '')),
      high: double.parse(pair.group(2)!.replaceAll(',', '')),
      raw: pair.group(0),
    );
  }
  final lt = _rangeLtRe.firstMatch(t);
  if (lt != null) {
    return (low: null, high: double.parse(lt.group(1)!), raw: lt.group(0)!.trim());
  }
  final gt = _rangeGtRe.firstMatch(t);
  if (gt != null) {
    return (low: double.parse(gt.group(1)!), high: null, raw: gt.group(0)!.trim());
  }
  return (low: null, high: null, raw: null);
}

/// Return a source-printed flag token or null. Mirrors `_find_source_flag`.
String? findSourceFlag(List<LabCell> cells) {
  for (final cell in cells.reversed) {
    final text = cell.text.trim();
    if (text.isEmpty) continue;
    final m = _sourceFlagWordsRe.firstMatch(text);
    if (m != null) return m.group(1);
    final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isNotEmpty) {
      final last = _rstrip(tokens.last, '.,;:()');
      final stars = _sourceFlagStarsRe.firstMatch(last);
      if (stars != null && last.length == stars.group(0)!.length) return last;
      final lastBare = last.replaceFirst(RegExp(r'\*+$'), '');
      if (_sourceFlagTokens.contains(lastBare)) return lastBare;
    }
  }
  return null;
}

String stripFlag(String text, String? flag) {
  if (flag == null || flag.isEmpty) return text;
  final re = RegExp(
    r'(?:\b' + RegExp.escape(flag) + r'\b\.?|\*{1,2})\s*$',
  );
  return text.replaceFirst(re, '').trim();
}

// --- Row / panel construction -------------------------------------------

Map<String, dynamic>? _valueBbox(LabCell? valueCell) {
  if (valueCell == null) return null;
  if (valueCell.page == null || valueCell.bbox == null) return null;
  return {'page': valueCell.page, 'bbox': valueCell.bbox};
}

const _maxFreeLineChars = 160;
const _maxBlobSegmentChars = 160;

/// Build one test entry from a Stage 1 table row (or null if the row carries
/// no test-like content at all). Mirrors `_parse_table_row`.
LabTest? parseTableRow(LabTableRow row, {required bool engineDegraded}) {
  final cells = [
    for (final c in row.cells)
      if (c.text.trim().isNotEmpty) c,
  ];
  if (cells.isEmpty) return null;

  var dataCells = [
    for (final c in cells)
      if (!c.isHeader) c,
  ];
  if (dataCells.isEmpty) {
    final rowText = cells.map((c) => c.text).join(' ');
    if (_numberRe.hasMatch(rowText)) {
      dataCells = cells;
    } else {
      return null;
    }
  }

  final singleCell = dataCells.length == 1;
  final nameCell = dataCells.first;
  var restCells = dataCells.sublist(1);
  var rawTestName = nameCell.text.trim();

  // Single-cell blobs have name+value fused: split off the leading name
  // segment before the first digit.
  if (singleCell) {
    final head = _nameDigitsRe.firstMatch(rawTestName);
    if (head != null) {
      final headEnd =
          head.group(0)!.indexOf(head.group(1)!) + head.group(1)!.length;
      restCells = [
        ...restCells,
        LabCell(
          text: rawTestName.substring(headEnd),
          bbox: nameCell.bbox,
          page: nameCell.page,
          isHeader: nameCell.isHeader,
          row: nameCell.row,
          col: nameCell.col,
        ),
      ];
      rawTestName = head.group(1)!.trim();
    }
  }
  if (rawTestName.isEmpty || _valueRowMarkerRe.hasMatch(rawTestName)) {
    // A column-header row slipped through without is_header.
    if (dataCells.length >= 2 &&
        !_numberRe.hasMatch(dataCells.map((c) => c.text).join(' '))) {
      return null;
    }
  }

  double? value;
  String? unit;
  double? rangeLow;
  double? rangeHigh;
  String? rangeRaw;
  LabCell? valueCell;
  var unitInferred = false;

  var remaining = List<LabCell>.from(restCells);

  if (!singleCell) {
    // Locate the first cell that parses as a number -> value cell.
    for (var idx = 0; idx < remaining.length; idx++) {
      final cell = remaining[idx];
      final numMatch = _numberRe.firstMatch(cell.text);
      if (numMatch != null) {
        value = double.parse(numMatch.group(1)!.replaceAll(',', ''));
        valueCell = cell;
        var afterValue = cell.text.substring(numMatch.end).trim();
        final unitM = _unitPrefixRe.firstMatch(afterValue.trim());
        if (unitM != null) {
          unit = unitM.group(0);
          afterValue = afterValue.substring(unitM.end).trim();
        }
        // Ranges often share the value cell ("230 mg/dL <200").
        final r = parseRange(afterValue);
        if (r.low != null || r.high != null) {
          rangeLow = r.low;
          rangeHigh = r.high;
          rangeRaw = r.raw;
        }
        remaining = remaining.sublist(idx + 1);
        break;
      }
    }
  }

  String? rangeRawText;
  if (singleCell) {
    // Single-row reconstruction: name/value/unit/range are fused in one blob.
    var blobParts = [
      for (final c in restCells)
        if (c.text.trim().isNotEmpty) c.text,
    ];
    if (blobParts.isEmpty) {
      blobParts = [restCells.map((c) => c.text).join(' ')];
    }
    final blob = blobParts.join(' ');
    final numMatch = _numberRe.firstMatch(blob);
    if (numMatch == null) return null;
    value = double.parse(numMatch.group(1)!.replaceAll(',', ''));
    valueCell = nameCell;
    var restAfterValue = blob.substring(numMatch.end);
    final unitM = _unitPrefixRe.firstMatch(restAfterValue.trim());
    if (unitM != null) {
      unit = unitM.group(0);
      restAfterValue = restAfterValue.substring(unitM.end);
    }
    rangeRawText = restAfterValue;
  } else {
    for (final cell in remaining) {
      final text = cell.text.trim();
      if (rangeLow == null && rangeHigh == null && rangeRaw == null) {
        final r = parseRange(text);
        if (r.low != null || r.high != null) {
          rangeLow = r.low;
          rangeHigh = r.high;
          rangeRaw = r.raw;
          continue;
        }
      }
      if (unit == null && looksLikeUnit(text)) {
        unit = _rstrip(text, '.');
        continue;
      }
    }
  }

  if (rangeRawText != null &&
      rangeRawText.isNotEmpty &&
      rangeLow == null &&
      rangeHigh == null) {
    final r = parseRange(rangeRawText);
    if (r.low != null || r.high != null) {
      rangeLow = r.low;
      rangeHigh = r.high;
      rangeRaw = r.raw;
    } else if (parseNumber(rangeRawText) != null && unit == null) {
      // A bare number in place of the range is conventionally an upper bound,
      // but that is an inference — cap confidence at medium.
      rangeHigh = parseNumber(rangeRawText);
      rangeRaw = rangeRawText.trim();
      unitInferred = true;
    }
  }

  final flagInSource = findSourceFlag(cells);
  if (flagInSource != null) {
    rawTestName = stripFlag(rawTestName, flagInSource);
  }

  final normalized = normalizeTestNameOrNull(rawTestName);
  if (normalized == null && rawTestName.isEmpty) return null;

  final String confidence;
  if (singleCell || engineDegraded) {
    confidence = 'low';
  } else if (value != null && unit == null && normalized == null) {
    confidence = 'medium';
  } else if (value != null && unit == null) {
    confidence = 'medium';
  } else if (rangeRaw != null && unitInferred) {
    confidence = 'medium';
  } else if (value == null) {
    confidence = 'low';
  } else {
    confidence = 'high';
  }

  return LabTest(
    testName: normalized ?? rawTestName,
    rawTestName: rawTestName,
    value: value,
    unit: unit,
    rangeLow: rangeLow,
    rangeHigh: rangeHigh,
    rangeRaw: rangeRaw,
    flagInSource: flagInSource,
    ocrConfidence: confidence,
    sourceBbox: _valueBbox(valueCell),
  );
}

final _nameDigitsRe = RegExp(
  r"^\s*([A-Za-z][A-Za-z .'()/,%^0-9\-]{2,}?)\s*\d",
);

/// Best-effort panel header from elements printed before the table. Mirrors
/// `_panel_name_for_table`.
String panelNameForTable(LabTable table, List<LabElement> precedingElements) {
  for (final el in precedingElements.reversed) {
    final text = el.text.trim();
    if (text.isEmpty || text.length > 120) continue;
    if (el.type == 'heading' || el.type == 'caption') return text;
    if (_numberRe.hasMatch(text)) continue;
    final letters = text.codeUnits.where(_isAsciiLetter).toList();
    if (letters.isNotEmpty &&
        letters.where(_isUpperAscii).length / letters.length > 0.7) {
      return text;
    }
  }
  return 'Ungrouped';
}

final _patientNameRe = RegExp(
  r"\bpatient(?:\s*name)?\s*[:\-]\s*([A-Za-z][A-Za-z .'\-]{1,58})",
  caseSensitive: false,
);
final _ageRe = RegExp(r'\bage\s*[:\-]?\s*(\d{1,3})\b', caseSensitive: false);
final _sexLabeledRe = RegExp(
  r'\bsex(?:/gender)?\s*[:\-]?\s*([A-Za-z]+)',
  caseSensitive: false,
);
final _sexSlashRe = RegExp(r'\b\d{1,3}\s*/\s*([MFT])\b', caseSensitive: false);
final _dateRe = RegExp(
  r'\b(?:report\s*)?date\s*[:\-]?\s*([0-9]{1,4}[/.\-][0-9]{1,2}[/.\-][0-9]{2,4})',
  caseSensitive: false,
);
final _labHintRe = RegExp(
  r'\b(lab|laboratory|diagnostic|patholog|hospital|clinic)\b',
  caseSensitive: false,
);
final _headerLabelRe = RegExp(
  r'\b(patient|age|sex|date|address|report no|ref no|sample no|lab |laboratory|panel|page \d)\b',
  caseSensitive: false,
);

/// Patient context strictly from text present in the document header. Never
/// inferred from test types. Mirrors `_extract_patient_context`.
PatientContext extractPatientContext(List<LabElement> elements) {
  String? name;
  int? age;
  String? sex;
  String? reportDate;

  for (final el in elements) {
    final text = el.text;
    if (name == null) {
      final m = _patientNameRe.firstMatch(text);
      if (m != null) {
        var value = m.group(1)!.trim();
        final cut = RegExp(r'\b(?:age|sex|date)\b', caseSensitive: false).firstMatch(value);
        if (cut != null) value = value.substring(0, cut.start).trim();
        if (value.isNotEmpty) name = value;
      }
    }
    if (age == null) {
      final m = _ageRe.firstMatch(text);
      if (m != null) age = int.parse(m.group(1)!);
    }
    if (sex == null) {
      final m = _sexLabeledRe.firstMatch(text);
      if (m != null) {
        final token = m.group(1)!.toLowerCase();
        if (token.startsWith('m')) {
          sex = 'M';
        } else if (token.startsWith('f')) {
          sex = 'F';
        }
      } else {
        final slash = _sexSlashRe.firstMatch(text);
        if (slash != null) {
          sex = slash.group(1)!.toUpperCase() == 'M' ? 'M' : 'F';
        }
      }
    }
    if (reportDate == null) {
      final m = _dateRe.firstMatch(text);
      if (m != null) reportDate = m.group(1);
    }
  }
  return PatientContext(name: name, age: age, sex: sex, reportDate: reportDate);
}

/// Lab name from header text — best effort, only when a lab-ish word appears
/// near the start of a text element. Mirrors `_extract_lab_name`.
String? extractLabName(List<LabElement> elements) {
  for (final el in elements) {
    final text = el.text.trim();
    if (text.isEmpty) continue;
    final head = text.length > 120 ? text.substring(0, 120) : text;
    final m = _labHintRe.firstMatch(head);
    if (m != null && m.start <= 40) {
      var candidate = text.length > 60 ? text.substring(0, 60) : text;
      final cut = RegExp(
        r'\b(patient|age|sex|date|address|report)\b',
        caseSensitive: false,
      ).firstMatch(candidate);
      if (cut != null) candidate = candidate.substring(0, cut.start);
      candidate = _stripEdges(candidate, ' ,:-');
      if (candidate.isNotEmpty) return candidate;
    }
  }
  return null;
}

/// Mirrors `_bbox_inside`. [tolerance] is in the same space as the boxes:
/// 5.0 for the backend's PDF points (parity fixtures), page-relative on
/// device.
bool _bboxInside(
  List<double>? elementBbox,
  List<double>? containerBbox, [
  double tolerance = 5.0,
]) {
  if (elementBbox == null || containerBbox == null) return false;
  if (elementBbox.length < 4 || containerBbox.length < 4) return false;
  final ex1 = elementBbox[0];
  final ey1 = elementBbox[1];
  final ex2 = elementBbox[2];
  final ey2 = elementBbox[3];
  final cx1 = containerBbox[0];
  final cy1 = containerBbox[1];
  final cx2 = containerBbox[2];
  final cy2 = containerBbox[3];
  return ex1 >= cx1 - tolerance &&
      ex2 <= cx2 + tolerance &&
      ey1 >= cy1 - tolerance &&
      ey2 <= cy2 + tolerance;
}

/// Parse one free-text line (outside tables) as a possible test row. Anything
/// parsed here is a reconstruction, so ocr_confidence is always 'low'.
LabTest? parseFreeLine(String rawLine, List<double>? bbox, int? page) {
  final line = rawLine.trim();
  if (line.isEmpty || line.length < 3 || line.length > _maxFreeLineChars) {
    return null;
  }
  if (_headerLabelRe.hasMatch(line)) return null;
  if (!_numberRe.hasMatch(line)) return null;

  final row = LabTableRow(cells: [LabCell(text: line, bbox: bbox, page: page)]);
  final test = parseTableRow(row, engineDegraded: true);
  if (test == null) return null;
  return test.withSourceBbox(
    (page != null && bbox != null) ? {'page': page, 'bbox': bbox} : null,
  );
}

final RegExp _blobNameRe = _buildBlobNamePattern();

RegExp _buildBlobNamePattern() {
  final names = testNameMap.keys.toList()
    ..sort((a, b) {
      final byLength = b.length.compareTo(a.length);
      return byLength != 0 ? byLength : a.compareTo(b);
    });
  return RegExp(
    r'\b(' + names.map(RegExp.escape).join('|') + r')\b',
    caseSensitive: false,
  );
}

final _testLexiconRe = RegExp(
  r'\b(hb|hgb|hemoglobin|wbc|tlc|rbc|plt|platelet|hct|pcv|hematocrit|'
  r'mcv|mch|mchc|rdw|esr|crp|neut|lymph|eos|baso|mono|'
  r'glucose|fbs|fbg|ppbs|ppbg|rbs|hba1c|sugar|'
  r'cholesterol|hdl|ldl|vldl|triglyceride|lipid|'
  r'sgot|sgpt|ast|alt|alp|bilirubin|protein|albumin|globulin|'
  r'urea|bun|creatinine|creat|uric acid|sodium|potassium|potas|chloride|calcium|'
  r'tsh|t3|t4|thyroid|testosterone|cortisol|vitamin|iron|ferritin|calcium|'
  r'urine|blood|count|cbc|serum|s\.|total|direct|indirect|u/l|mg/dl|g/dl)\b',
  caseSensitive: false,
);

/// Recover test rows fused into long text elements. Each known test name
/// anchors a segment parsed for value/unit/range — always 'low' confidence.
List<LabTest> scanBlobForTestRows(
  String text,
  List<double>? bbox,
  int? page,
  Set<String> seenNames,
) {
  final tests = <LabTest>[];
  final matches = _blobNameRe.allMatches(text).toList();
  for (var idx = 0; idx < matches.length; idx++) {
    final m = matches[idx];
    final segEnd = idx + 1 < matches.length ? matches[idx + 1].start : text.length;
    final segment = text.substring(
      m.start,
      math.min(segEnd, m.start + _maxBlobSegmentChars),
    );
    final rawName = m.group(1)!.trim();
    final key = normalizeLookupKey(rawName);
    if (seenNames.contains(key)) continue;

    final rest = segment.substring(m.end - m.start);
    final numMatch = _numberRe.firstMatch(rest);
    if (numMatch == null) continue;

    final after = rest.substring(numMatch.end).trim();
    final unitM = _unitSearchRe.firstMatch(
      after.length > 32 ? after.substring(0, 32) : after,
    );
    final unit = unitM?.group(0);
    final r = parseRange(after);
    if (r.low == null && r.high == null && rawName.length <= 2 && unit == null) {
      continue;
    }

    final flag = findSourceFlag([LabCell(text: segment)]);
    var name = rawName;
    if (flag != null) name = stripFlag(name, flag);

    tests.add(
      LabTest(
        testName: normalizeTestNameOrNull(rawName) ?? rawName,
        rawTestName: name,
        value: double.parse(numMatch.group(1)!.replaceAll(',', '')),
        unit: unit,
        rangeLow: r.low,
        rangeHigh: r.high,
        rangeRaw: r.raw,
        flagInSource: flag,
        ocrConfidence: 'low',
        sourceBbox: (page != null && bbox != null)
            ? {'page': page, 'bbox': bbox}
            : null,
      ),
    );
    seenNames.add(key);
  }
  return tests;
}

/// Find test rows that landed in plain text elements instead of detected
/// tables. Mirrors `_missed_rows_from_text`.
List<LabTest> missedRowsFromText(
  LabStage1 stage1,
  Set<String> tableRawNames, {
  double bboxTolerance = 5.0,
}) {
  final elements = stage1.elements;
  final tables = stage1.tables;
  final tableBoxes = [for (final t in tables) (t.page, t.bbox)];

  final tests = <LabTest>[];
  final seenNames = Set<String>.from(tableRawNames);
  for (final el in elements) {
    if (el.type == 'table') continue;
    final page = el.page;
    final bbox = el.bbox;
    if (tableBoxes.any(
      (b) => page == b.$1 && _bboxInside(bbox, b.$2, bboxTolerance),
    )) {
      continue;
    }
    final elText = el.text;
    tests.addAll(scanBlobForTestRows(elText, bbox, page, seenNames));
    for (final rawLine in elText.split('\n')) {
      final line = rawLine.trim();
      if (line == elText.trim() && line.length > _maxFreeLineChars) {
        continue; // blob lines are handled by the scanner above
      }
      final test = parseFreeLine(rawLine, bbox, page);
      if (test == null) continue;
      var resolved = test;
      final normalized = normalizeTestNameOrNull(test.rawTestName);
      if (normalized != null) {
        resolved = test.withTestName(normalized);
      } else if (!_testLexiconRe.hasMatch(test.rawTestName)) {
        // Unrecognizable free text with a stray number — not a test row,
        // never silently kept.
        continue;
      }
      final key = normalizeLookupKey(resolved.rawTestName);
      if (seenNames.contains(key)) continue;
      seenNames.add(key);
      tests.add(resolved);
    }
  }
  return tests;
}

/// Fallback line parser when extraction produced no tables. Every test is
/// reconstructed at 'low' confidence. Mirrors `_parse_from_plain_text`.
List<LabTest> parseFromPlainText(LabStage1 stage1) {
  final tests = <LabTest>[];
  for (final rawLine in stage1.text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.length < 3) continue;
    final row = LabTableRow(cells: [LabCell(text: line)]);
    final test = parseTableRow(row, engineDegraded: true);
    if (test != null) tests.add(test);
  }
  return tests;
}

/// Normalise Stage 1 output into the fixed lab report schema. Mirror of
/// `_build_document`.
LabDocument buildLabDocument(LabStage1 stage1, {double bboxTolerance = 5.0}) {
  final elements = stage1.elements;
  final tables = stage1.tables;
  final engineDegraded = stage1.extractionEngine == 'easyocr_fallback';

  final panels = <LabPanel>[];
  final tableRawNames = <String>{};
  if (tables.isNotEmpty) {
    // Elements are in document order; approximate "elements before this table"
    // by page + document position of the first table row.
    final seenPages = <int?>{};
    for (final table in tables) {
      final tablePage = table.page;
      var preceding = <LabElement>[];
      for (final el in elements) {
        final elPage = el.page;
        if (elPage == null || tablePage == null || elPage <= tablePage) {
          preceding.add(el);
        }
      }
      if (seenPages.contains(tablePage)) {
        preceding = preceding.sublist(math.max(0, preceding.length - 6));
      }
      seenPages.add(tablePage);

      final tests = <LabTest>[];
      for (final row in table.rows) {
        final test = parseTableRow(row, engineDegraded: engineDegraded);
        if (test != null) {
          tests.add(test);
          tableRawNames.add(normalizeLookupKey(test.rawTestName));
        }
      }
      panels.add(
        LabPanel(panelName: panelNameForTable(table, preceding), tests: tests),
      );
    }

    final missed = missedRowsFromText(
      stage1,
      tableRawNames,
      bboxTolerance: bboxTolerance,
    );
    if (missed.isNotEmpty) {
      panels.add(LabPanel(panelName: 'Ungrouped', tests: missed));
    }
  } else {
    final tests = parseFromPlainText(stage1);
    if (tests.isNotEmpty) {
      panels.add(LabPanel(panelName: 'Ungrouped', tests: tests));
    }
  }

  return LabDocument(
    documentType: 'lab_report',
    patientContext: extractPatientContext(elements),
    labName: extractLabName(elements),
    panels: panels,
  );
}

// --- Output model (mirrors the wire schema) ------------------------------

class LabTest {
  const LabTest({
    required this.testName,
    required this.rawTestName,
    this.value,
    this.unit,
    this.rangeLow,
    this.rangeHigh,
    this.rangeRaw,
    this.flagInSource,
    this.ocrConfidence = 'low',
    this.sourceBbox,
    this.abnormal,
    this.direction,
    this.severity,
    this.isPanicValue = false,
    this.calculationMethod,
    this.formula,
    this.rangeSource,
  });

  final String testName;
  final String rawTestName;
  final double? value;
  final String? unit;
  final double? rangeLow;
  final double? rangeHigh;
  final String? rangeRaw;
  final String? flagInSource;

  /// high | medium | low
  final String ocrConfidence;

  /// {page, bbox} — the value cell's geometry, for reviewer traceability.
  final Map<String, dynamic>? sourceBbox;

  final bool? abnormal;
  final String? direction;
  final String? severity;
  final bool isPanicValue;
  final String? calculationMethod;
  final String? formula;
  final String? rangeSource;

  LabTest withTestName(String name) => LabTest(
    testName: name,
    rawTestName: rawTestName,
    value: value,
    unit: unit,
    rangeLow: rangeLow,
    rangeHigh: rangeHigh,
    rangeRaw: rangeRaw,
    flagInSource: flagInSource,
    ocrConfidence: ocrConfidence,
    sourceBbox: sourceBbox,
    abnormal: abnormal,
    direction: direction,
    severity: severity,
    isPanicValue: isPanicValue,
    calculationMethod: calculationMethod,
    formula: formula,
    rangeSource: rangeSource,
  );

  LabTest withSourceBbox(Map<String, dynamic>? box) => LabTest(
    testName: testName,
    rawTestName: rawTestName,
    value: value,
    unit: unit,
    rangeLow: rangeLow,
    rangeHigh: rangeHigh,
    rangeRaw: rangeRaw,
    flagInSource: flagInSource,
    ocrConfidence: ocrConfidence,
    sourceBbox: box,
    abnormal: abnormal,
    direction: direction,
    severity: severity,
    isPanicValue: isPanicValue,
    calculationMethod: calculationMethod,
    formula: formula,
    rangeSource: rangeSource,
  );

  factory LabTest.fromJson(Map<String, dynamic> json) => LabTest(
    testName: json['test_name'] as String? ?? json['raw_test_name'] as String? ?? 'Unknown',
    rawTestName: json['raw_test_name'] as String? ?? json['test_name'] as String? ?? 'Unknown',
    value: (json['value'] as num?)?.toDouble(),
    unit: json['unit'] as String?,
    rangeLow: (json['range_low'] as num?)?.toDouble(),
    rangeHigh: (json['range_high'] as num?)?.toDouble(),
    rangeRaw: json['range_raw'] as String?,
    flagInSource: json['flag_in_source'] as String?,
    ocrConfidence: json['ocr_confidence'] as String? ?? 'low',
    sourceBbox: json['source_bbox'] is Map ? (json['source_bbox'] as Map).cast<String, dynamic>() : null,
    abnormal: json['abnormal'] as bool?,
    direction: json['direction'] as String?,
    severity: json['severity'] as String?,
    isPanicValue: json['is_panic_value'] as bool? ?? false,
    calculationMethod: json['calculation_method'] as String?,
    formula: json['formula'] as String?,
    rangeSource: json['range_source'] as String?,
  );

  /// Exactly the 10 schema keys for Stage 2, plus Stage 3 annotations when present.
  Map<String, dynamic> toJson() => {
    'test_name': testName,
    'raw_test_name': rawTestName,
    'value': value,
    'unit': unit,
    'range_low': rangeLow,
    'range_high': rangeHigh,
    'range_raw': rangeRaw,
    'flag_in_source': flagInSource,
    'ocr_confidence': ocrConfidence,
    'source_bbox': sourceBbox,
    if (abnormal != null) 'abnormal': abnormal,
    if (direction != null) 'direction': direction,
    if (severity != null) 'severity': severity,
    if (isPanicValue) 'is_panic_value': isPanicValue,
    if (calculationMethod != null) 'calculation_method': calculationMethod,
    if (formula != null) 'formula': formula,
    if (rangeSource != null) 'range_source': rangeSource,
  };
}

class PatientContext {
  const PatientContext({this.name, this.age, this.sex, this.reportDate});

  final String? name;
  final int? age;
  final String? sex;
  final String? reportDate;

  factory PatientContext.fromJson(Map<String, dynamic> json) => PatientContext(
    name: json['name'] as String?,
    age: (json['age'] as num?)?.toInt(),
    sex: json['sex'] as String?,
    reportDate: json['report_date'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
    'sex': sex,
    'report_date': reportDate,
  };
}

class LabPanel {
  const LabPanel({required this.panelName, required this.tests});

  final String panelName;
  final List<LabTest> tests;

  factory LabPanel.fromJson(Map<String, dynamic> json) => LabPanel(
    panelName: json['panel_name'] as String? ?? 'Ungrouped',
    tests: [
      for (final t in (json['tests'] as List? ?? const []))
        LabTest.fromJson((t as Map).cast<String, dynamic>()),
    ],
  );

  Map<String, dynamic> toJson() => {
    'panel_name': panelName,
    'tests': [for (final t in tests) t.toJson()],
  };
}

class LabDocument {
  const LabDocument({
    required this.documentType,
    required this.patientContext,
    this.labName,
    required this.panels,
  });

  final String documentType;
  final PatientContext patientContext;
  final String? labName;
  final List<LabPanel> panels;

  factory LabDocument.fromJson(Map<String, dynamic> json) => LabDocument(
    documentType: json['document_type'] as String? ?? 'lab_report',
    patientContext: json['patient_context'] != null
        ? PatientContext.fromJson(
            (json['patient_context'] as Map).cast<String, dynamic>(),
          )
        : const PatientContext(),
    labName: json['lab_name'] as String?,
    panels: [
      for (final p in (json['panels'] as List? ?? const []))
        LabPanel.fromJson((p as Map).cast<String, dynamic>()),
    ],
  );

  Map<String, dynamic> toJson() => {
    'document_type': documentType,
    'patient_context': patientContext.toJson(),
    'lab_name': labName,
    'panels': [for (final p in panels) p.toJson()],
  };
}

// --- small helpers --------------------------------------------------------

bool _isAsciiLetter(int c) =>
    (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);

bool _isUpperAscii(int c) => c >= 0x41 && c <= 0x5a;

String _rstrip(String s, String chars) {
  var end = s.length;
  while (end > 0 && chars.contains(s[end - 1])) {
    end--;
  }
  return s.substring(0, end);
}

String _stripEdges(String s, String chars) {
  var start = 0;
  var end = s.length;
  while (start < end && chars.contains(s[start])) {
    start++;
  }
  while (end > start && chars.contains(s[end - 1])) {
    end--;
  }
  return s.substring(start, end);
}
