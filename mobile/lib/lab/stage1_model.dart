// Stage 1 data model — field-for-field compatible with the backend's
// `stage1` dict produced by `backend/lab_pipeline/ocr_stage.py`
// (`_build_stage1_output`). Keeping the shape identical is what lets the
// ported Stage 2 rule engine consume geometry synthesised on-device and lets
// the parity harness feed the same JSON to the Python reference.
//
// All geometry is normalised to page-relative units (0..1) on-device; the
// model itself does not care which space it is in.

/// Coerce arbitrary JSON into a bbox, or null when absent/short.
List<double>? parseBbox(Object? value) {
  if (value is! List || value.length < 4) return null;
  return [for (final v in value) (v as num).toDouble()];
}

int? _asInt(Object? v) => v is num ? v.toInt() : null;

String _asText(Object? v) => v == null ? '' : '$v';

/// One flattened content element. Mirrors the backend's `elements[]` entries.
class LabElement {
  const LabElement({
    this.type,
    required this.text,
    this.bbox,
    this.page,
  });

  /// 'heading' | 'caption' | 'text' | 'table' (best effort).
  final String? type;
  final String text;
  final List<double>? bbox;
  final int? page;

  factory LabElement.fromJson(Map<String, dynamic> json) => LabElement(
    type: json['type'] as String?,
    text: _asText(json['text']),
    bbox: parseBbox(json['bbox']),
    page: _asInt(json['page']),
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'text': text,
    'bbox': bbox,
    'page': page,
  };
}

/// One table cell. Mirrors the backend's `tables[].rows[].cells[]` entries.
class LabCell {
  const LabCell({
    required this.text,
    this.bbox,
    this.page,
    this.isHeader = false,
    this.row,
    this.col,
  });

  final String text;
  final List<double>? bbox;
  final int? page;
  final bool isHeader;
  final int? row;
  final int? col;

  factory LabCell.fromJson(Map<String, dynamic> json) => LabCell(
    text: _asText(json['text']),
    bbox: parseBbox(json['bbox']),
    page: _asInt(json['page']),
    isHeader: json['is_header'] == true,
    row: _asInt(json['row']),
    col: _asInt(json['col']),
  );

  Map<String, dynamic> toJson() => {
    'text': text,
    'bbox': bbox,
    'page': page,
    'is_header': isHeader,
    'row': row,
    'col': col,
  };
}

class LabTableRow {
  const LabTableRow({this.row, required this.cells});

  final int? row;
  final List<LabCell> cells;

  factory LabTableRow.fromJson(Map<String, dynamic> json) => LabTableRow(
    row: _asInt(json['row']),
    cells: [
      for (final c in (json['cells'] as List? ?? const []))
        if (c is Map) LabCell.fromJson(Map<String, dynamic>.from(c)),
    ],
  );

  Map<String, dynamic> toJson() => {
    'row': row,
    'cells': [for (final c in cells) c.toJson()],
  };
}

/// One detected table. Mirrors the backend's `tables[]` entries.
class LabTable {
  const LabTable({
    this.bbox,
    this.page,
    this.nRows,
    this.nCols,
    required this.rows,
  });

  final List<double>? bbox;
  final int? page;
  final int? nRows;
  final int? nCols;
  final List<LabTableRow> rows;

  factory LabTable.fromJson(Map<String, dynamic> json) => LabTable(
    bbox: parseBbox(json['bbox']),
    page: _asInt(json['page']),
    nRows: _asInt(json['n_rows']),
    nCols: _asInt(json['n_cols']),
    rows: [
      for (final r in (json['rows'] as List? ?? const []))
        if (r is Map) LabTableRow.fromJson(Map<String, dynamic>.from(r)),
    ],
  );

  Map<String, dynamic> toJson() => {
    'bbox': bbox,
    'page': page,
    'n_rows': nRows,
    'n_cols': nCols,
    'rows': [for (final r in rows) r.toJson()],
  };
}

/// The whole Stage 1 output for one document.
class LabStage1 {
  const LabStage1({
    required this.extractionEngine,
    required this.text,
    required this.elements,
    required this.tables,
    required this.warnings,
  });

  /// 'mlkit-geometry' | 'mlkit-lines-only' on-device, or a backend engine id
  /// in fixtures ('opendataloader-json' | 'easyocr_fallback').
  final String extractionEngine;
  final String text;
  final List<LabElement> elements;
  final List<LabTable> tables;
  final List<String> warnings;

  factory LabStage1.fromJson(Map<String, dynamic> json) => LabStage1(
    extractionEngine: _asText(json['extraction_engine']),
    text: _asText(json['text']),
    elements: [
      for (final e in (json['elements'] as List? ?? const []))
        if (e is Map) LabElement.fromJson(Map<String, dynamic>.from(e)),
    ],
    tables: [
      for (final t in (json['tables'] as List? ?? const []))
        if (t is Map) LabTable.fromJson(Map<String, dynamic>.from(t)),
    ],
    warnings: [
      for (final w in (json['warnings'] as List? ?? const [])) '$w',
    ],
  );

  Map<String, dynamic> toJson() => {
    'extraction_engine': extractionEngine,
    'text': text,
    'elements': [for (final e in elements) e.toJson()],
    'tables': [for (final t in tables) t.toJson()],
    'warnings': warnings,
  };
}
