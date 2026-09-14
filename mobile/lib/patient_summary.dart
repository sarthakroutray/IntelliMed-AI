// Full-patient summary: deterministic aggregation of every stored record.
//
// The on-device SLM has a small context (2048 tokens; see slm_runtime.dart), so
// all of a patient's documents can never go into one prompt. This file turns the
// stored records into (a) a deterministic roll-up the doctor can trust and
// (b) terse per-record "cards" that a map -> reduce step can summarise.
//
// Everything factual here is arithmetic over Stage 3 data that the app already
// computed. The model never structures or flags anything (same invariant as the
// rest of the app): it only writes prose over these facts.
//
// Wording rule (see copy.dart): descriptive only — "value", "outside range",
// "pattern", "for review". Never "diagnos*", never "improving"/"worsening".

import 'api/models.dart';
import 'trends.dart';

/// Test severity tiers, most serious first.
const _testSeverityRank = <String, int>{
  'critical': 0,
  'severe': 1,
  'moderate': 2,
  'mild': 3,
  'normal': 4,
};

/// Pattern severity tiers (`clinical_engine` uses critical|warning|info).
const _patternSeverityRank = <String, int>{
  'critical': 0,
  'warning': 1,
  'info': 2,
};

/// One measurement reduced from a record.
class RecordTest {
  const RecordTest({
    required this.name,
    this.value,
    this.unit,
    this.direction,
    this.severity,
    this.panic = false,
    this.abnormal = false,
    this.flagInSource,
    this.rangeLabel,
  });

  final String name;
  final num? value;
  final String? unit;

  /// high | low
  final String? direction;

  /// critical | severe | moderate | mild | normal
  final String? severity;
  final bool panic;
  final bool abnormal;
  final String? flagInSource;
  final String? rangeLabel;

  bool get isCritical => panic || severity == 'critical';

  /// "Hemoglobin 11.2 g/dL (low)" — the way a doctor reads it.
  String get summary {
    final buffer = StringBuffer(name);
    if (value != null) buffer.write(' ${formatNumber(value)}');
    if (unit != null && unit!.isNotEmpty) buffer.write(' $unit');
    if (direction != null && direction!.isNotEmpty) {
      buffer.write(' (${direction == 'low' ? 'below range' : 'above range'})');
    } else if (panic) {
      buffer.write(' (critical)');
    }
    return buffer.toString();
  }
}

class RecordMedication {
  const RecordMedication({required this.medication, this.dosage, this.frequency});

  final String medication;
  final String? dosage;
  final String? frequency;

  String get label => [medication, dosage, frequency]
      .where((v) => v != null && v.trim().isNotEmpty)
      .map((v) => v!.trim())
      .join(' ');
}

class RecordPattern {
  const RecordPattern({
    required this.name,
    this.severity,
    this.category,
    this.implication,
  });

  final String name;
  final String? severity;
  final String? category;
  final String? implication;
}

/// One source document reduced to what a patient summary needs.
class PatientRecord {
  const PatientRecord({
    required this.kind,
    required this.sourceLabel,
    this.date,
    this.labName,
    this.storedSummary,
    this.tests = const [],
    this.meds = const [],
    this.patterns = const [],
    this.imageNote,
    this.rulesUnreviewed = false,
    this.patientName,
    this.patientAge,
    this.patientSex,
  });

  /// lab_report | prescription | xray | document
  final String kind;
  final String sourceLabel;
  final DateTime? date;
  final String? labName;

  /// The per-document summary that was already generated at capture time, when
  /// present. Reusing it keeps the map step free of new model calls.
  final String? storedSummary;

  final List<RecordTest> tests;
  final List<RecordMedication> meds;
  final List<RecordPattern> patterns;

  /// Classifier note for an X-ray record (no panels/medicines to summarise).
  final String? imageNote;

  final bool rulesUnreviewed;

  // Identity as printed on the document, used only when the profile is absent.
  final String? patientName;
  final num? patientAge;
  final String? patientSex;

  /// Build from a stored/parsed envelope (local capture, stage2 or stage3).
  factory PatientRecord.fromEnvelope(
    ResultEnvelope envelope, {
    DateTime? date,
    required String sourceLabel,
  }) {
    final tests = <RecordTest>[];
    for (final panel in envelope.panels) {
      for (final test in panel.tests) {
        final name = test.testName.trim();
        if (name.isEmpty || name == 'Unknown') continue;
        tests.add(
          RecordTest(
            name: name,
            value: test.value,
            unit: test.unit,
            direction: test.direction,
            severity: test.severity,
            panic: test.isPanicValue,
            abnormal: test.abnormal == true,
            flagInSource: test.flagInSource,
            rangeLabel: test.rangeLabel,
          ),
        );
      }
    }

    final xray = envelope.xray;
    final imageNote = xray == null
        ? null
        : 'X-ray pattern: ${xray.topPattern}'
              '${xray.confidence == null ? '' : ' (${(xray.confidence! * 100).round()}%)'}';

    return PatientRecord(
      kind: envelope.kind,
      sourceLabel: sourceLabel,
      date: date,
      labName: envelope.labName,
      storedSummary: envelope.summaryContext?.medicalSummary,
      tests: tests,
      meds: [
        for (final item in envelope.prescriptionItems)
          RecordMedication(
            medication: item.medication,
            dosage: item.dosage,
            frequency: item.frequency,
          ),
      ],
      patterns: [
        for (final pattern in envelope.flaggedPatterns)
          RecordPattern(
            name: pattern.patternName,
            severity: pattern.severity,
            category: pattern.category,
            implication: pattern.clinicalImplication,
          ),
      ],
      imageNote: imageNote,
      rulesUnreviewed: envelope.rulesUnreviewed,
      patientName: envelope.patientContext?.name,
      patientAge: envelope.patientContext?.age,
      patientSex: envelope.patientContext?.sex,
    );
  }

  /// Build from the server-side v1 document analysis (used for cloud
  /// prescriptions, which have no structured envelope on the client).
  factory PatientRecord.fromDocumentAnalysis(
    DocumentAnalysis analysis, {
    DateTime? date,
    required String sourceLabel,
  }) {
    return PatientRecord(
      kind: analysis.isPrescription ? 'prescription' : 'document',
      sourceLabel: sourceLabel,
      date: date,
      storedSummary: analysis.medicalSummary,
      meds: [
        for (final item in analysis.prescriptions)
          RecordMedication(
            medication: item.medication,
            dosage: item.dosage,
            frequency: item.frequency,
          ),
      ],
      imageNote: analysis.findings.isEmpty
          ? null
          : 'Classifier: ${analysis.findings.first.label}',
    );
  }
}

/// Deterministic roll-up of every record, for the doctor-facing "at a glance".
class PatientSummaryFacts {
  const PatientSummaryFacts({
    required this.countsByKind,
    required this.recordCount,
    this.earliest,
    this.latest,
    this.name,
    this.age,
    this.sex,
    this.criticalValues = const [],
    this.abnormalHighlights = const [],
    this.patterns = const [],
    this.currentMeds = const [],
    this.trendHighlights = const [],
    this.notes = const [],
  });

  final Map<String, int> countsByKind;
  final int recordCount;
  final DateTime? earliest;
  final DateTime? latest;
  final String? name;
  final num? age;
  final String? sex;

  /// Emergency-grade values (`is_panic_value` or severity `critical`).
  final List<RecordTest> criticalValues;

  /// Tests outside their printed range, most serious first.
  final List<RecordTest> abnormalHighlights;

  final List<RecordPattern> patterns;

  /// Medicines across records, latest dose for each.
  final List<RecordMedication> currentMeds;

  /// "Hemoglobin: 13.1 (2025-01) -> 11.2 (2025-03)" for analytes with history.
  final List<String> trendHighlights;

  final List<String> notes;

  bool get isEmpty => recordCount == 0;
}

/// Roll [records] up deterministically. [records] order does not matter; the
/// aggregation is by recency, so a later reading wins.
PatientSummaryFacts buildFacts(List<PatientRecord> records) {
  if (records.isEmpty) {
    return const PatientSummaryFacts(countsByKind: {}, recordCount: 0);
  }

  final ordered = [...records]..sort(_byDateAscending);

  final counts = <String, int>{};
  DateTime? earliest;
  DateTime? latest;
  String? name;
  num? age;
  String? sex;

  // Latest-per-key maps, filled oldest -> newest so later entries win.
  final latestTest = <String, RecordTest>{};
  final latestMed = <String, RecordMedication>{};
  final patternByName = <String, RecordPattern>{};
  final trendPoints = <TrendPoint>[];
  var unreviewed = false;

  for (final record in ordered) {
    counts[record.kind] = (counts[record.kind] ?? 0) + 1;
    final date = record.date;
    if (date != null) {
      if (earliest == null || date.isBefore(earliest)) earliest = date;
      if (latest == null || date.isAfter(latest)) latest = date;
    }
    name ??= record.patientName;
    age ??= record.patientAge;
    sex ??= record.patientSex;
    unreviewed = unreviewed || record.rulesUnreviewed;

    for (final test in record.tests) {
      latestTest[test.name.toLowerCase()] = test;
      final value = test.value;
      if (value != null && date != null) {
        trendPoints.add(
          TrendPoint(
            testName: test.name,
            value: value.toDouble(),
            date: date,
            unit: test.unit,
            flagInSource: test.flagInSource,
          ),
        );
      }
    }
    for (final med in record.meds) {
      if (med.medication.trim().isEmpty) continue;
      latestMed[med.medication.trim().toLowerCase()] = med;
    }
    for (final pattern in record.patterns) {
      final key = pattern.name.toLowerCase();
      final existing = patternByName[key];
      if (existing == null || _worsePattern(pattern, existing)) {
        patternByName[key] = pattern;
      }
    }
  }

  final tests = latestTest.values.toList();
  final critical = tests.where((t) => t.isCritical).toList()
    ..sort(_byTestUrgency);
  final abnormal = tests.where((t) => t.abnormal && !t.isCritical).toList()
    ..sort(_byTestUrgency);

  final patterns = patternByName.values.toList()
    ..sort((a, b) {
      final byRank = _patternRank(a).compareTo(_patternRank(b));
      return byRank != 0 ? byRank : a.name.compareTo(b.name);
    });

  final meds = latestMed.values.toList()
    ..sort((a, b) => a.medication.compareTo(b.medication));

  final notes = <String>[];
  final series = buildTrendSeries(trendPoints);
  if (hasUnitSplit(series)) notes.add('Some measurements appear under more than one unit.');
  if (unreviewed) {
    notes.add('Flags come from an unreviewed placeholder rule table.');
  }

  return PatientSummaryFacts(
    countsByKind: counts,
    recordCount: records.length,
    earliest: earliest,
    latest: latest,
    name: name,
    age: age,
    sex: sex,
    criticalValues: critical,
    abnormalHighlights: abnormal,
    patterns: patterns,
    currentMeds: meds,
    trendHighlights: _trendHighlights(series),
    notes: notes,
  );
}

/// Terse, self-contained text for one record — the map step's unit of input.
/// Prefers the summary already generated at capture time.
String buildRecordCard(PatientRecord record) {
  final buffer = StringBuffer();
  final date = record.date == null ? 'undated' : _shortDate(record.date!);
  buffer.write('[$date] ${_kindLabel(record.kind)}');
  if (record.labName != null && record.labName!.trim().isNotEmpty) {
    buffer.write(' — ${record.labName}');
  }
  buffer.write('\n');

  final summary = record.storedSummary?.trim();
  if (summary != null && summary.isNotEmpty) {
    buffer.writeln(summary);
  }

  if (summary == null || summary.isEmpty) {
    for (final med in record.meds) {
      buffer.writeln('- ${med.label}');
    }
    for (final test in _notableTests(record)) {
      buffer.writeln('- ${test.summary}');
    }
    if (record.imageNote != null) buffer.writeln('- ${record.imageNote}');
  }

  // Always surface the highest-signal facts, even alongside a stored summary.
  for (final med in record.meds) {
    if (summary != null && summary.isNotEmpty) {
      buffer.writeln('- Medicine: ${med.label}');
    }
  }
  for (final test in record.tests.where((t) => t.isCritical || t.abnormal)) {
    if (summary != null && summary.isNotEmpty) {
      buffer.writeln('- Flagged: ${test.summary}');
    }
  }
  for (final pattern in record.patterns) {
    buffer.writeln(
      '- Pattern: ${pattern.name}'
      '${pattern.severity == null ? '' : ' (${pattern.severity})'}',
    );
  }
  return buffer.toString().trim();
}

/// Split [cards] into chunks that each fit [charBudget], preserving order.
///
/// A card longer than the budget is truncated to keep every chunk sendable to
/// the model (whose prompt budget is ~4000 chars; see slm_runtime.dart).
List<String> chunkCardsByBudget(List<String> cards, {int charBudget = 3000}) {
  final chunks = <String>[];
  final buffer = StringBuffer();
  for (final raw in cards) {
    final card = raw.length <= charBudget ? raw : raw.substring(0, charBudget);
    if (card.trim().isEmpty) continue;
    final separator = buffer.isEmpty ? '' : '\n\n';
    if (buffer.length + separator.length + card.length > charBudget &&
        buffer.isNotEmpty) {
      chunks.add(buffer.toString());
      buffer.clear();
    }
    if (buffer.isNotEmpty) buffer.write('\n\n');
    buffer.write(card);
  }
  if (buffer.isNotEmpty) chunks.add(buffer.toString());
  return chunks;
}

/// Plain-text rendering for the clipboard / share sheet.
String renderPatientSummaryText(
  PatientSummaryFacts facts,
  List<PatientRecord> records,
  String? narrative,
) {
  final buffer = StringBuffer();
  final identity = <String>[
    if (facts.name != null && facts.name!.trim().isNotEmpty) facts.name!.trim(),
    if (facts.age != null) 'age ${formatNumber(facts.age)}',
    if (facts.sex != null && facts.sex!.trim().isNotEmpty) facts.sex!.trim(),
  ];
  buffer.writeln('PATIENT SUMMARY');
  if (identity.isNotEmpty) buffer.writeln(identity.join(', '));
  buffer.writeln('Generated on this device. For review with your doctor.');
  buffer.writeln();

  buffer.writeln('SUMMARY');
  final text = narrative?.trim();
  buffer.writeln(
    text == null || text.isEmpty
        ? 'Summary not available on this device.'
        : text,
  );
  buffer.writeln();

  buffer.writeln('AT A GLANCE');
  buffer.writeln(_recordsLine(facts));
  if (facts.criticalValues.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Critical values:');
    for (final test in facts.criticalValues) {
      buffer.writeln('- ${test.summary}');
    }
  }
  if (facts.abnormalHighlights.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Outside printed range:');
    for (final test in facts.abnormalHighlights) {
      buffer.writeln('- ${test.summary}');
    }
  }
  if (facts.patterns.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Patterns for review:');
    for (final pattern in facts.patterns) {
      final category =
          pattern.category == null || pattern.category == 'General'
          ? ''
          : ' · ${pattern.category}';
      buffer.writeln(
        '- ${pattern.name}$category'
        '${pattern.severity == null ? '' : ' (${pattern.severity})'}',
      );
    }
  }
  if (facts.currentMeds.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Medicines:');
    for (final med in facts.currentMeds) {
      buffer.writeln('- ${med.label}');
    }
  }
  if (facts.trendHighlights.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Changes over time:');
    for (final highlight in facts.trendHighlights) {
      buffer.writeln('- $highlight');
    }
  }
  if (facts.notes.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Notes:');
    for (final note in facts.notes) {
      buffer.writeln('- $note');
    }
  }
  buffer.writeln();
  buffer.writeln(
    'Structured context generated on this device — not medical advice.',
  );
  return buffer.toString().trimRight();
}

/// "3 lab reports, 2 prescriptions (2025-01-12 to 2025-03-04)".
String _recordsLine(PatientSummaryFacts facts) {
  if (facts.recordCount == 0) return 'No records.';
  final parts = facts.countsByKind.entries
      .map((e) => '${e.value} ${_kindLabel(e.key).toLowerCase()}'
          '${e.value == 1 ? '' : 's'}')
      .toList()
    ..sort();
  final range = facts.earliest == null || facts.latest == null
      ? ''
      : ' (${_shortDate(facts.earliest!)} to ${_shortDate(facts.latest!)})';
  return '${parts.join(', ')}$range';
}

int _byDateAscending(PatientRecord a, PatientRecord b) {
  final da = a.date;
  final db = b.date;
  if (da == null && db == null) return 0;
  if (da == null) return -1;
  if (db == null) return 1;
  return da.compareTo(db);
}

int _byTestUrgency(RecordTest a, RecordTest b) {
  if (a.panic != b.panic) return a.panic ? -1 : 1;
  final byRank =
      _testRank(a).compareTo(_testRank(b));
  return byRank != 0 ? byRank : a.name.compareTo(b.name);
}

int _testRank(RecordTest test) => _testSeverityRank[test.severity] ?? 5;

int _patternRank(RecordPattern pattern) =>
    _patternSeverityRank[pattern.severity] ?? 3;

bool _worsePattern(RecordPattern candidate, RecordPattern existing) =>
    _patternRank(candidate) < _patternRank(existing);

/// Tests worth putting in a card: critical/abnormal first, then the rest.
Iterable<RecordTest> _notableTests(PatientRecord record) {
  final flagged = record.tests.where((t) => t.isCritical || t.abnormal);
  if (flagged.isNotEmpty) return flagged;
  return record.tests.take(12);
}

List<String> _trendHighlights(List<TrendSeries> series) {
  final highlights = <String>[];
  for (final s in series) {
    if (s.points.length < 2) continue;
    final earliest = s.points.first;
    final latest = s.points.last;
    if (earliest.value == latest.value) continue;
    highlights.add(
      '${s.testName}: ${formatNumber(earliest.value)}'
      '${s.unit == null || s.unit!.isEmpty ? '' : ' ${s.unit}'}'
      ' (${_shortDate(earliest.date)}) -> '
      '${formatNumber(latest.value)}'
      '${s.unit == null || s.unit!.isEmpty ? '' : ' ${s.unit}'}'
      ' (${_shortDate(latest.date)})',
    );
    if (highlights.length >= 10) break;
  }
  return highlights;
}

String _kindLabel(String kind) {
  switch (kind) {
    case 'prescription':
      return 'Prescription';
    case 'xray':
      return 'X-ray';
    case 'lab_report':
      return 'Lab report';
    case 'document':
      return 'Document';
    default:
      return kind.isEmpty ? 'Record' : kind;
  }
}

String _shortDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
