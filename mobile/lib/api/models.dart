// Typed models for the patient app.
//
// Parsing is deliberately DEFENSIVE. This backend returns plain dicts (most
// routes declare no response_model), and a lab report's stored `result` has
// THREE different shapes depending on how it was produced:
//
//   1. Local app envelope (lib/normalize.dart::buildResultEnvelope):
//        {kind, engine, latency_ms, normalized, summary_context?, ocr_excerpt, source}
//        -> no stage3: the device must never emit abnormal/direction flags.
//   2. Server app-ingest envelope (/api/v2/lab-reports/upload-structured):
//        {pipeline, stage2, stage2_engine, stage3, warnings, rules_review_status,
//         ocr_excerpt, latency_ms, summary_context?}
//        -> no stage1.
//   3. Server pipeline envelope (/api/v2/lab-reports/upload):
//        {pipeline, stage1, stage2, stage2_engine, stage3, warnings, rules_review_status}
//        -> includes a large stage1 OCR tree (with a `raw` blob) we never render.
//
// Everything tolerates missing/null keys so one viewer can render any of them.

// ---------------------------------------------------------------------------
// small coercion helpers
// ---------------------------------------------------------------------------

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? v.map((k, value) => MapEntry('$k', value)) : null;

List<Object?> _list(Object? v) => v is List ? v : const [];

String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

num? _num(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

bool? _bool(Object? v) {
  if (v is bool) return v;
  if (v is String) {
    if (v.toLowerCase() == 'true') return true;
    if (v.toLowerCase() == 'false') return false;
  }
  return null;
}

DateTime? _date(Object? v) {
  final s = _str(v);
  if (s == null) return null;
  return DateTime.tryParse(s)?.toLocal();
}

/// Renders a value the way a clinician reads it: trailing `.0` stripped.
String formatNumber(num? value) {
  if (value == null) return '—';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

// ---------------------------------------------------------------------------
// Lab report structures
// ---------------------------------------------------------------------------

/// One test row. `abnormal`/`direction` are Stage 3 fields and are null on
/// normalization-only data (local envelopes and `stage2`).
class LabTest {
  LabTest({
    required this.testName,
    required this.rawTestName,
    this.value,
    this.unit,
    this.rangeLow,
    this.rangeHigh,
    this.rangeRaw,
    this.flagInSource,
    this.ocrConfidence,
    this.sourceBbox,
    this.abnormal,
    this.direction,
  });

  final String testName;
  final String rawTestName;
  final num? value;
  final String? unit;
  final num? rangeLow;
  final num? rangeHigh;
  final String? rangeRaw;

  /// A flag that was PRINTED on the source document (H/L/etc.). Never computed.
  final String? flagInSource;

  /// high | medium | low
  final String? ocrConfidence;

  /// {page, bbox} when the extractor preserved a location.
  final Map<String, dynamic>? sourceBbox;

  /// Stage 3 only. null = no value or no range to compare against.
  final bool? abnormal;

  /// Stage 3 only: high | low.
  final String? direction;

  factory LabTest.fromJson(Map<String, dynamic> json) => LabTest(
    testName: _str(json['test_name']) ?? _str(json['raw_test_name']) ?? 'Unknown',
    rawTestName: _str(json['raw_test_name']) ?? _str(json['test_name']) ?? 'Unknown',
    value: _num(json['value']),
    unit: _str(json['unit']),
    rangeLow: _num(json['range_low']),
    rangeHigh: _num(json['range_high']),
    rangeRaw: _str(json['range_raw']),
    flagInSource: _str(json['flag_in_source']),
    ocrConfidence: _str(json['ocr_confidence']),
    sourceBbox: _map(json['source_bbox']),
    abnormal: _bool(json['abnormal']),
    direction: _str(json['direction']),
  );

  /// "13 - 17" / "> 4" style range, preferring the explicit bounds.
  String? get rangeLabel {
    if (rangeLow != null && rangeHigh != null) {
      return '${formatNumber(rangeLow)} – ${formatNumber(rangeHigh)}';
    }
    if (rangeRaw != null) return rangeRaw;
    if (rangeLow != null) return '≥ ${formatNumber(rangeLow)}';
    if (rangeHigh != null) return '≤ ${formatNumber(rangeHigh)}';
    return null;
  }

  /// Whether Stage 3 had enough information to compare at all.
  bool get comparable => abnormal != null || direction != null;

  /// Location as a short human string, for traceability.
  String? get locationLabel {
    final box = sourceBbox;
    if (box == null) return null;
    final page = box['page'];
    return page == null ? 'on source' : 'p.$page';
  }
}

class LabPanel {
  LabPanel({required this.panelName, required this.tests});

  final String panelName;
  final List<LabTest> tests;

  factory LabPanel.fromJson(Map<String, dynamic> json) => LabPanel(
    panelName: _str(json['panel_name']) ?? 'Ungrouped',
    tests: _list(json['tests'])
        .map(_map)
        .whereType<Map<String, dynamic>>()
        .map(LabTest.fromJson)
        .toList(),
  );
}

/// A Stage 3 pattern: an interpretation rule matched across tests in one panel.
/// Every entry carries the exact values that triggered it, for traceability.
class FlaggedPattern {
  FlaggedPattern({
    required this.patternName,
    required this.surfacedText,
    this.matchType,
    this.panelName,
    required this.triggeringTests,
  });

  final String patternName;
  final String surfacedText;
  final String? matchType;
  final String? panelName;
  final List<TriggeringTest> triggeringTests;

  factory FlaggedPattern.fromJson(Map<String, dynamic> json) => FlaggedPattern(
    patternName: _str(json['pattern_name']) ?? 'Pattern',
    surfacedText: _str(json['surfaced_text']) ?? '',
    matchType: _str(json['match_type']),
    panelName: _str(json['panel_name']),
    triggeringTests: _list(json['triggering_tests'])
        .map(_map)
        .whereType<Map<String, dynamic>>()
        .map(TriggeringTest.fromJson)
        .toList(),
  );
}

class TriggeringTest {
  TriggeringTest({
    required this.testName,
    this.rawTestName,
    this.value,
    this.unit,
    this.direction,
  });

  final String testName;
  final String? rawTestName;
  final num? value;
  final String? unit;
  final String? direction;

  factory TriggeringTest.fromJson(Map<String, dynamic> json) => TriggeringTest(
    testName: _str(json['test_name']) ?? _str(json['raw_test_name']) ?? 'Unknown',
    rawTestName: _str(json['raw_test_name']),
    value: _num(json['value']),
    unit: _str(json['unit']),
    direction: _str(json['direction']),
  );

  /// "11.2 g/dL (low)" — the value plus why it matched.
  String get summary {
    final buffer = StringBuffer(formatNumber(value));
    if (unit != null) buffer.write(' $unit');
    if (direction != null) buffer.write(' ($direction)');
    return buffer.toString();
  }
}

class PatientContext {
  PatientContext({this.name, this.age, this.sex, this.reportDate});

  final String? name;
  final num? age;
  final String? sex;
  final String? reportDate;

  factory PatientContext.fromJson(Map<String, dynamic> json) => PatientContext(
    name: _str(json['name']),
    age: _num(json['age']),
    sex: _str(json['sex']),
    reportDate: _str(json['report_date']),
  );

  bool get isEmpty =>
      name == null && age == null && sex == null && reportDate == null;
}

/// T5 summariser output (app path only).
class SummaryContext {
  SummaryContext({this.medicalSummary, required this.keyFindings});

  final String? medicalSummary;
  final List<String> keyFindings;

  factory SummaryContext.fromJson(Map<String, dynamic> json) => SummaryContext(
    medicalSummary: _str(json['medical_summary']),
    keyFindings: _list(json['key_findings'])
        .map(_str)
        .whereType<String>()
        .toList(),
  );

  bool get isEmpty =>
      (medicalSummary == null || medicalSummary!.isEmpty) && keyFindings.isEmpty;
}

/// How the document type was decided on-device (`detection` in the envelope).
///
/// Recorded as provenance: detection is heuristic, so a reviewing doctor —
/// and the user — should be able to see whether the type was auto-detected or
/// chosen, and on what evidence.
class DetectionInfo {
  DetectionInfo({
    required this.type,
    this.confidence,
    this.auto = true,
    this.usedClassifier = false,
    required this.reasons,
  });

  /// Wire name: lab_report | prescription | xray.
  final String type;
  final double? confidence;

  /// False when the user picked the type explicitly.
  final bool auto;

  /// Whether the X-ray classifier had to run to make the call.
  final bool usedClassifier;

  final List<String> reasons;

  factory DetectionInfo.fromJson(Map<String, dynamic> json) => DetectionInfo(
    type: _str(json['type']) ?? 'unknown',
    confidence: _num(json['confidence'])?.toDouble(),
    auto: _bool(json['auto']) ?? true,
    usedClassifier: _bool(json['used_classifier']) ?? false,
    reasons: _list(json['reasons']).map(_str).whereType<String>().toList(),
  );

  /// A weak or ambiguous guess the user should be invited to correct.
  bool get isWeak => auto && (confidence ?? 0) < 0.6;
}

/// On-device X-ray classifier output.
class XrayResult {
  XrayResult({
    required this.topPattern,
    this.confidence,
    required this.probabilities,
    this.model,
    this.note,
  });

  final String topPattern;
  final num? confidence;

  /// label -> probability (0..1)
  final Map<String, num> probabilities;
  final String? model;
  final String? note;

  factory XrayResult.fromJson(Map<String, dynamic> json) {
    final probs = <String, num>{};
    final raw = _map(json['probabilities']);
    if (raw != null) {
      raw.forEach((key, value) {
        final n = _num(value);
        if (n != null) probs[key] = n;
      });
    }
    return XrayResult(
      topPattern: _str(json['top_pattern']) ?? 'Unknown',
      confidence: _num(json['confidence']),
      probabilities: probs,
      model: _str(json['model']),
      note: _str(json['note']),
    );
  }

  /// Highest probability first — the order a reader expects.
  List<MapEntry<String, num>> get sortedProbabilities {
    final entries = probabilities.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  bool get isNormal => topPattern.toLowerCase().contains('normal');
}

/// A prescribed item (prescription normalization).
class PrescriptionItem {
  PrescriptionItem({required this.medication, this.dosage, this.frequency});

  final String medication;
  final String? dosage;
  final String? frequency;

  factory PrescriptionItem.fromJson(Map<String, dynamic> json) => PrescriptionItem(
    medication: _str(json['medication']) ?? 'Unknown',
    dosage: _str(json['dosage']),
    frequency: _str(json['frequency']),
  );
}

// ---------------------------------------------------------------------------
// Result envelope — unifies all three stored shapes
// ---------------------------------------------------------------------------

class ResultEnvelope {
  ResultEnvelope({
    required this.kind,
    this.engine,
    this.latencyMs,
    this.labName,
    this.patientContext,
    required this.panels,
    required this.flaggedPatterns,
    this.xray,
    required this.prescriptionItems,
    this.summaryContext,
    this.ocrExcerpt,
    required this.warnings,
    this.rulesReviewStatus,
    this.detection,
    this.pageCount,
    this.pagesTruncated = false,
    this.hasStage1 = false,
    this.hasStage3 = false,
  });

  /// lab_report | prescription | xray (best effort).
  final String kind;
  final String? engine;
  final int? latencyMs;
  final String? labName;
  final PatientContext? patientContext;

  /// Prefers Stage 3 (annotated) rows, falling back to Stage 2 / normalized.
  final List<LabPanel> panels;
  final List<FlaggedPattern> flaggedPatterns;

  final XrayResult? xray;
  final List<PrescriptionItem> prescriptionItems;
  final SummaryContext? summaryContext;
  final String? ocrExcerpt;
  final List<String> warnings;

  /// The rule table's review status. The shipped table is UNREVIEWED
  /// PLACEHOLDERS, so this is surfaced rather than hidden.
  final String? rulesReviewStatus;

  /// How the document type was decided on-device, when the app recorded it.
  final DetectionInfo? detection;

  /// Pages in the source document (1 for a single image).
  final int? pageCount;

  /// True when a long PDF was capped at the on-device page limit.
  final bool pagesTruncated;

  /// Whether a stage1 OCR tree was present (pipeline uploads only).
  final bool hasStage1;

  /// Whether Stage 3 annotation rows were present at all.
  final bool hasStage3;

  factory ResultEnvelope.fromJson(Map<String, dynamic> json) {
    // stage3 (annotated) is preferred: it is stage2 plus abnormal/direction
    // and flagged_patterns. stage2/normalized fall back for local envelopes.
    final stage3 = _map(json['stage3']);
    final stage2 = _map(json['stage2']) ?? _map(json['normalized']);
    final document = stage3 ?? stage2 ?? const <String, dynamic>{};

    final documentType = _str(document['document_type']) ?? _str(json['kind']);

    final xraySource = documentType == 'xray' ? document : null;
    final panels = _list(document['panels'])
        .map(_map)
        .whereType<Map<String, dynamic>>()
        .map(LabPanel.fromJson)
        .toList();

    final items = <PrescriptionItem>[];
    for (final panel in _list(document['panels'])
        .map(_map)
        .whereType<Map<String, dynamic>>()) {
      for (final item in _list(panel['items'])
          .map(_map)
          .whereType<Map<String, dynamic>>()) {
        items.add(PrescriptionItem.fromJson(item));
      }
    }

    final summaryRaw = _map(json['summary_context']);
    final warnings = _list(json['warnings']).map(_str).whereType<String>().toList();
    final contextRaw = _map(document['patient_context']);

    return ResultEnvelope(
      kind: documentType == null ? 'unknown' : _normalizeKind(documentType),
      engine: _str(json['engine']) ?? _str(json['stage2_engine']),
      latencyMs: _num(json['latency_ms'])?.toInt(),
      labName: _str(document['lab_name']),
      patientContext:
          contextRaw == null ? null : PatientContext.fromJson(contextRaw),
      panels: panels,
      flaggedPatterns: _list((stage3 ?? document)['flagged_patterns'])
          .map(_map)
          .whereType<Map<String, dynamic>>()
          .map(FlaggedPattern.fromJson)
          .toList(),
      xray: xraySource == null ? null : XrayResult.fromJson(xraySource),
      prescriptionItems: items,
      summaryContext: summaryRaw == null ? null : SummaryContext.fromJson(summaryRaw),
      ocrExcerpt: _str(json['ocr_excerpt']),
      warnings: warnings,
      rulesReviewStatus: _str(json['rules_review_status']),
      detection: _map(json['detection']) == null
          ? null
          : DetectionInfo.fromJson(_map(json['detection'])!),
      pageCount: _num(json['page_count'])?.toInt(),
      pagesTruncated: _bool(json['pages_truncated']) ?? false,
      hasStage1: json['stage1'] != null,
      hasStage3: stage3 != null,
    );
  }

  static String _normalizeKind(String value) {
    final v = value.toLowerCase();
    if (v.contains('lab')) return 'lab_report';
    if (v.contains('prescription')) return 'prescription';
    if (v.contains('xray') || v.contains('x-ray')) return 'xray';
    return v;
  }

  /// Total tests across all panels.
  int get testCount =>
      panels.fold(0, (sum, panel) => sum + panel.tests.length);

  /// Tests Stage 3 marked abnormal. Not a diagnosis — a comparison against the
  /// document's own printed reference range.
  List<LabTest> get abnormalTests =>
      panels.expand((p) => p.tests).where((t) => t.abnormal == true).toList();

  /// Tests Stage 3 could not evaluate (no value, or no range printed).
  List<LabTest> get incomparableTests =>
      panels.expand((p) => p.tests).where((t) => !t.comparable).toList();

  /// Whether the rule engine's table still needs clinical review.
  bool get rulesUnreviewed {
    final status = rulesReviewStatus?.toLowerCase();
    if (status == null) return false;
    return status.contains('unreviewed') || status.contains('placeholder');
  }

  bool get isEmpty =>
      panels.isEmpty &&
      flaggedPatterns.isEmpty &&
      xray == null &&
      prescriptionItems.isEmpty &&
      (summaryContext?.isEmpty ?? true);
}

// ---------------------------------------------------------------------------
// Lab report wrappers (v2 read endpoints)
// ---------------------------------------------------------------------------

class LabReport {
  LabReport({
    required this.id,
    this.patientId,
    this.source,
    required this.filename,
    this.uploadedAt,
    this.fileUrl,
    required this.result,
  });

  final int id;
  final int? patientId;
  final String? source;
  final String filename;
  final DateTime? uploadedAt;
  final String? fileUrl;
  final ResultEnvelope result;

  factory LabReport.fromJson(Map<String, dynamic> json) => LabReport(
    id: _num(json['id'])?.toInt() ?? -1,
    patientId: _num(json['patient_id'])?.toInt(),
    source: _str(json['source']),
    filename: _str(json['filename']) ?? 'report',
    uploadedAt: _date(json['upload_timestamp']),
    fileUrl: _str(json['file_url']),
    result: ResultEnvelope.fromJson(_map(json['result']) ?? const {}),
  );

  bool get fromApp => source == 'app';
}

// ---------------------------------------------------------------------------
// Documents (v1)
// ---------------------------------------------------------------------------

class DocumentSummary {
  DocumentSummary({
    required this.id,
    required this.filename,
    this.uploadedAt,
    this.hasAnalysis = false,
    this.detectedType,
  });

  final int id;
  final String filename;
  final DateTime? uploadedAt;
  final bool hasAnalysis;
  final String? detectedType;

  factory DocumentSummary.fromJson(Map<String, dynamic> json) {
    final analysis = _map(json['ai_analysis']);
    final detected = analysis == null ? null : _str(analysis['detected_type']);
    return DocumentSummary(
      id: _num(json['id'])?.toInt() ?? -1,
      filename: _str(json['filename']) ?? 'document',
      uploadedAt: _date(json['upload_timestamp']),
      hasAnalysis: json['ai_analysis'] != null,
      detectedType: detected,
    );
  }
}

class DocumentFinding {
  DocumentFinding({required this.label, this.confidence, this.description});

  final String label;
  final num? confidence;
  final String? description;

  factory DocumentFinding.fromJson(Map<String, dynamic> json) => DocumentFinding(
    label: _str(json['label']) ?? 'Finding',
    confidence: _num(json['confidence']),
    description: _str(json['description']),
  );
}

class NlpEntity {
  NlpEntity({required this.text, this.label, this.confidence});

  final String text;
  final String? label;
  final num? confidence;

  factory NlpEntity.fromJson(Map<String, dynamic> json) => NlpEntity(
    text: _str(json['text']) ?? _str(json['word']) ?? '',
    label: _str(json['label']) ?? _str(json['entity']),
    confidence: _num(json['confidence']) ?? _num(json['score']),
  );
}

class DocumentAnalysis {
  DocumentAnalysis({
    this.status,
    this.title,
    this.description,
    this.classification,
    this.confidence,
    required this.findings,
    this.nlpSummary,
    required this.entities,
    required this.medications,
    required this.prescriptions,
    this.isPrescription = false,
    this.medicalSummary,
    required this.keyFindings,
    this.ocrText,
  });

  final String? status;
  final String? title;
  final String? description;
  final String? classification;
  final num? confidence;
  final List<DocumentFinding> findings;
  final String? nlpSummary;
  final List<NlpEntity> entities;
  final List<String> medications;
  final List<PrescriptionItem> prescriptions;
  final bool isPrescription;
  final String? medicalSummary;
  final List<String> keyFindings;
  final String? ocrText;

  factory DocumentAnalysis.fromJson(Map<String, dynamic> json) {
    final summary = _map(json['summary']) ?? const <String, dynamic>{};
    final nlp = _map(json['nlp']) ?? const <String, dynamic>{};

    final meds = _list(nlp['medications']).map((m) {
      if (m is String) return m;
      final map = _map(m);
      return map == null ? _str(m) : _str(map['name']) ?? _str(map['medication']);
    }).whereType<String>().toList();

    return DocumentAnalysis(
      status: _str(summary['status']),
      title: _str(summary['title']),
      description: _str(summary['description']),
      classification: _str(summary['classification']),
      confidence: _num(summary['confidence']),
      findings: _list(json['findings'])
          .map(_map)
          .whereType<Map<String, dynamic>>()
          .map(DocumentFinding.fromJson)
          .toList(),
      nlpSummary: _str(nlp['summary']),
      entities: _list(nlp['entities'])
          .map(_map)
          .whereType<Map<String, dynamic>>()
          .map(NlpEntity.fromJson)
          .where((e) => e.text.isNotEmpty)
          .toList(),
      medications: meds,
      prescriptions: _list(nlp['prescriptions'])
          .map(_map)
          .whereType<Map<String, dynamic>>()
          .map(PrescriptionItem.fromJson)
          .toList(),
      isPrescription: _bool(nlp['is_prescription']) ?? false,
      medicalSummary: _str(json['medical_summary']),
      keyFindings:
          _list(json['key_findings']).map(_str).whereType<String>().toList(),
      ocrText: _str(json['ocr_text']),
    );
  }

  bool get hasContent =>
      findings.isNotEmpty ||
      entities.isNotEmpty ||
      medications.isNotEmpty ||
      prescriptions.isNotEmpty ||
      (medicalSummary?.isNotEmpty ?? false) ||
      keyFindings.isNotEmpty ||
      (ocrText?.isNotEmpty ?? false);
}

class DocumentDetail {
  DocumentDetail({
    required this.id,
    this.title,
    this.patientName,
    this.timestamp,
    this.status,
    this.fileType,
    this.fileSize,
    this.fileName,
    this.fileUrl,
    required this.analysis,
  });

  final int id;
  final String? title;
  final String? patientName;
  final String? timestamp;
  final String? status;
  final String? fileType;
  final String? fileSize;
  final String? fileName;
  final String? fileUrl;
  final DocumentAnalysis analysis;

  factory DocumentDetail.fromJson(Map<String, dynamic> json) {
    final patient = _map(json['patient']);
    return DocumentDetail(
      id: _num(json['id'])?.toInt() ?? -1,
      title: _str(json['title']),
      patientName: patient == null ? null : _str(patient['name']),
      timestamp: _str(json['timestamp']),
      status: _str(json['status']),
      fileType: _str(json['fileType']),
      fileSize: _str(json['fileSize']),
      fileName: _str(json['fileName']),
      fileUrl: _str(json['fileUrl']),
      analysis: DocumentAnalysis.fromJson(_map(json['analysis']) ?? const {}),
    );
  }

  bool get isPending => (status ?? '').toLowerCase() == 'pending';
}

// ---------------------------------------------------------------------------
// Profile / doctors
// ---------------------------------------------------------------------------

class Profile {
  Profile({
    required this.id,
    required this.email,
    this.name,
    this.role,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.address,
    this.emergencyContact,
    this.emergencyPhone,
    this.bloodType,
    this.allergies,
    this.chronicConditions,
    this.darkMode = false,
    this.emailNotifications = true,
    this.pushNotifications = true,
    this.createdAt,
  });

  final int id;
  final String email;
  final String? name;
  final String? role;
  final String? phone;
  final String? dateOfBirth;
  final String? gender;
  final String? address;
  final String? emergencyContact;
  final String? emergencyPhone;
  final String? bloodType;
  final String? allergies;
  final String? chronicConditions;
  final bool darkMode;
  final bool emailNotifications;
  final bool pushNotifications;
  final DateTime? createdAt;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: _num(json['id'])?.toInt() ?? -1,
    email: _str(json['email']) ?? '',
    name: _str(json['name']),
    role: _str(json['role']),
    phone: _str(json['phone']),
    dateOfBirth: _str(json['date_of_birth']),
    gender: _str(json['gender']),
    address: _str(json['address']),
    emergencyContact: _str(json['emergency_contact']),
    emergencyPhone: _str(json['emergency_phone']),
    bloodType: _str(json['blood_type']),
    allergies: _str(json['allergies']),
    chronicConditions: _str(json['chronic_conditions']),
    darkMode: _bool(json['dark_mode']) ?? false,
    emailNotifications: _bool(json['email_notifications']) ?? true,
    pushNotifications: _bool(json['push_notifications']) ?? true,
    createdAt: _date(json['created_at']),
  );

  String get displayName {
    final n = name;
    if (n != null && n.isNotEmpty) return n;
    return email.isEmpty ? 'Patient' : email.split('@').first;
  }
}

class LinkedDoctor {
  LinkedDoctor({required this.id, required this.email, this.name});

  final int id;
  final String email;
  final String? name;

  factory LinkedDoctor.fromJson(Map<String, dynamic> json) => LinkedDoctor(
    id: _num(json['id'])?.toInt() ?? -1,
    email: _str(json['email']) ?? '',
    name: _str(json['name']),
  );

  String get displayName {
    final n = name;
    if (n != null && n.isNotEmpty) return n;
    return email.isEmpty ? 'Doctor' : email.split('@').first;
  }

  String get initial =>
      displayName.isEmpty ? '?' : displayName[0].toUpperCase();
}

class SharedDoctor {
  SharedDoctor({required this.doctorId, required this.doctorEmail});

  final int doctorId;
  final String doctorEmail;

  factory SharedDoctor.fromJson(Map<String, dynamic> json) => SharedDoctor(
    doctorId: _num(json['doctor_id'])?.toInt() ?? -1,
    doctorEmail: _str(json['doctor_email']) ?? '',
  );
}
