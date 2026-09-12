// Longitudinal trends over stored lab results.
//
// A single haemoglobin of 11.2 says little; the same value falling over three
// reports is the thing that matters. This is arithmetic over rows the app
// already stores — deterministic, no model, and essentially hallucination-proof.
//
// The one real correctness trap is units: a series is keyed by canonical test
// name AND unit, so a change from mg/dL to mmol/L splits the series rather than
// silently plotting incomparable numbers on one line.
//
// Wording rule (see copy.dart): "your values over time", never "improving" or
// "worsening" — direction is an interpretation and belongs to a clinician.

import 'dart:convert';

import 'api/models.dart';
import 'schemas.dart';

/// One reading of one analyte at one point in time.
class TrendPoint {
  const TrendPoint({
    required this.testName,
    required this.value,
    required this.date,
    this.unit,
    this.rangeLow,
    this.rangeHigh,
    this.rangeRaw,
    this.flagInSource,
    this.sourceLabel,
    this.sourceId,
  });

  /// Canonical name (e.g. "Hemoglobin"), not the as-printed abbreviation.
  final String testName;
  final double value;
  final DateTime date;
  final String? unit;

  /// The reference range printed on THAT report, when present.
  final double? rangeLow;
  final double? rangeHigh;
  final String? rangeRaw;

  /// A flag printed on the source document. Never computed here.
  final String? flagInSource;

  /// Where the reading came from ("This device", a filename, …).
  final String? sourceLabel;
  final int? sourceId;

  TrendPoint withTestName(String name) => TrendPoint(
    testName: name,
    value: value,
    date: date,
    unit: unit,
    rangeLow: rangeLow,
    rangeHigh: rangeHigh,
    rangeRaw: rangeRaw,
    flagInSource: flagInSource,
    sourceLabel: sourceLabel,
    sourceId: sourceId,
  );

  bool get hasRange => rangeLow != null || rangeHigh != null;
}

/// A unit-consistent time series for one analyte. Points are ascending by date.
class TrendSeries {
  const TrendSeries({
    required this.testName,
    required this.unit,
    required this.points,
  });

  final String testName;

  /// Null means the source printed no unit. Never merged with any real unit.
  final String? unit;
  final List<TrendPoint> points;

  String get unitLabel => unit == null || unit!.isEmpty ? 'no unit' : unit!;

  TrendPoint get latest => points.last;
  TrendPoint get earliest => points.first;
  bool get isSinglePoint => points.length == 1;

  double get minValue =>
      points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
  double get maxValue =>
      points.map((p) => p.value).reduce((a, b) => a > b ? a : b);

  /// The printed band to shade, taken from the most recent reading that had
  /// one. A range can drift between reports; shading the latest is the honest
  /// choice and is labelled as the latest printed range in the UI.
  ({double? low, double? high})? get referenceBand {
    for (final point in points.reversed) {
      if (point.hasRange) return (low: point.rangeLow, high: point.rangeHigh);
    }
    return null;
  }
}

/// Group [points] into unit-consistent series, sorted by analyte then unit.
List<TrendSeries> buildTrendSeries(Iterable<TrendPoint> points) {
  final groups = <String, List<TrendPoint>>{};
  for (final point in points) {
    final canonical = canonicalTestName(point.testName);
    final key = '$canonical\u0000${point.unit ?? ''}';
    groups.putIfAbsent(key, () => []).add(point.withTestName(canonical));
  }

  final series = <TrendSeries>[];
  groups.forEach((_, group) {
    group.sort((a, b) => a.date.compareTo(b.date));
    series.add(
      TrendSeries(
        testName: group.first.testName,
        unit: group.first.unit,
        points: List.unmodifiable(group),
      ),
    );
  });
  series.sort((a, b) {
    final byName = a.testName.toLowerCase().compareTo(b.testName.toLowerCase());
    if (byName != 0) return byName;
    return (a.unit ?? '').compareTo(b.unit ?? '');
  });
  return series;
}

/// True when an analyte appears under more than one unit — those series must
/// never be compared or plotted together.
bool hasUnitSplit(List<TrendSeries> series) {
  final unitsByName = <String, Set<String>>{};
  for (final s in series) {
    unitsByName.putIfAbsent(s.testName, () => <String>{}).add(s.unit ?? '');
  }
  return unitsByName.values.any((units) => units.length > 1);
}

/// Canonicalise defensively: stored rows should already carry a canonical name,
/// but older ones may not, and grouping must not fragment on that.
String canonicalTestName(String raw) {
  final canonical = normalizeTestName(raw);
  return canonical.isEmpty ? raw : canonical;
}

/// Extract readings from a typed result envelope (the shape
/// `ResultEnvelope.fromJson` produces for local, stage2 and stage3 data).
List<TrendPoint> trendPointsFromResult(
  ResultEnvelope result, {
  required DateTime date,
  String? sourceLabel,
  int? sourceId,
}) {
  final points = <TrendPoint>[];
  for (final panel in result.panels) {
    for (final test in panel.tests) {
      final value = test.value;
      if (value == null) continue;
      final name = test.testName.trim();
      if (name.isEmpty || name == 'Unknown') continue;
      points.add(
        TrendPoint(
          testName: name,
          value: value.toDouble(),
          date: date,
          unit: test.unit,
          rangeLow: test.rangeLow?.toDouble(),
          rangeHigh: test.rangeHigh?.toDouble(),
          rangeRaw: test.rangeRaw,
          flagInSource: test.flagInSource,
          sourceLabel: sourceLabel,
          sourceId: sourceId,
        ),
      );
    }
  }
  return points;
}

/// Extract readings from a raw envelope map (local `result_json`, or a server
/// report's `result`).
List<TrendPoint> trendPointsFromEnvelope(
  Map<String, dynamic> envelope, {
  required DateTime date,
  String? sourceLabel,
  int? sourceId,
}) => trendPointsFromResult(
  ResultEnvelope.fromJson(envelope),
  date: date,
  sourceLabel: sourceLabel,
  sourceId: sourceId,
);

/// Readings from this device's stored lab-report rows.
List<TrendPoint> trendPointsFromLocalRows(List<Map<String, Object?>> rows) {
  final points = <TrendPoint>[];
  for (final row in rows) {
    if ('${row['kind']}' != 'lab_report') continue;
    final envelope = decodeEnvelope('${row['result_json']}');
    if (envelope == null) continue;
    final date = parseSqliteUtc('${row['created_at']}');
    if (date == null) continue;
    points.addAll(
      trendPointsFromEnvelope(
        envelope,
        date: date,
        sourceLabel: 'This device',
        sourceId: (row['id'] as num?)?.toInt(),
      ),
    );
  }
  return points;
}

/// Server report ids already represented by a local row, so the merged history
/// does not double-count a capture that has synced.
Set<int> syncedServerIds(List<Map<String, Object?>> localRows) => {
  for (final row in localRows)
    if (row['server_id'] is int) row['server_id'] as int,
};

/// Readings from server reports, skipping any already covered by a local row.
List<TrendPoint> trendPointsFromReports(
  List<LabReport> reports, {
  Set<int> skipIds = const {},
}) {
  final points = <TrendPoint>[];
  for (final report in reports) {
    if (skipIds.contains(report.id)) continue;
    final date = report.uploadedAt;
    if (date == null) continue;
    points.addAll(
      trendPointsFromResult(
        report.result,
        date: date,
        sourceLabel: report.filename,
        sourceId: report.id,
      ),
    );
  }
  return points;
}

/// Parse a stored envelope, tolerating malformed JSON.
Map<String, dynamic>? decodeEnvelope(String? json) {
  if (json == null || json.isEmpty) return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry('$k', v));
    }
  } catch (_) {
    // Corrupt row: skip it rather than failing the whole trends view.
  }
  return null;
}

/// SQLite `datetime('now')` is UTC without a zone marker; parsing it as local
/// would shift every point by the device offset.
DateTime? parseSqliteUtc(String raw) {
  if (raw.isEmpty) return null;
  final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
  final zoned = normalized.endsWith('Z') ? normalized : '${normalized}Z';
  return DateTime.tryParse(zoned)?.toLocal();
}
